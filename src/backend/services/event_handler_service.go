package services

import (
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/thinkstack/broker"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

type EventHandlerServiceInterface interface {
	Start()
	Stop()
	ProcessPendingEvents()
	IsKafkaAvailable() bool
}

type EventHandlerService struct {
	db            *database.Database
	isRunning     bool
	ticker        *time.Ticker
	kafkaProducer broker.Producer
	kafkaEnabled  bool
}

func NewEventHandlerService(db *database.Database) EventHandlerServiceInterface {
	return &EventHandlerService{
		db:           db,
		isRunning:    false,
		ticker:       time.NewTicker(1 * time.Second),
		kafkaEnabled: broker.IsKafkaEnabled(),
		// By default, use the global producer. This can be overridden for testing
		kafkaProducer: nil, // Will use the global producer via broker.PublishMessage
	}
}

// NewEventHandlerServiceWithProducer creates a new EventHandlerService with a custom producer
func NewEventHandlerServiceWithProducer(db *database.Database, producer broker.Producer) EventHandlerServiceInterface {
	return &EventHandlerService{
		db:            db,
		isRunning:     false,
		ticker:        time.NewTicker(1 * time.Second),
		kafkaProducer: producer,
		kafkaEnabled:  producer != nil && producer.IsAvailable(),
	}
}

func (s *EventHandlerService) Start() {
	if s.isRunning {
		return
	}
	
	// Check if Kafka is available before starting
	s.kafkaEnabled = broker.IsKafkaEnabled()
	
	if !s.kafkaEnabled {
		log.Println("Warning: EventHandlerService started with Kafka disabled - events will not be dispatched")
	} else {
		log.Println("EventHandlerService started successfully with Kafka enabled")
	}
	
	s.isRunning = true
	go s.ProcessPendingEvents()
}

func (s *EventHandlerService) Stop() {
	if !s.isRunning {
		return
	}
	s.isRunning = false
	s.ticker.Stop()
}

// IsKafkaAvailable reports whether events can be dispatched
func (s *EventHandlerService) IsKafkaAvailable() bool {
	return s.kafkaEnabled
}

func (s *EventHandlerService) ProcessPendingEvents() {
	for range s.ticker.C {
		if !s.isRunning {
			return
		}

		// Check if Kafka is available
		s.kafkaEnabled = broker.IsKafkaEnabled()
		if !s.kafkaEnabled {
			// Don't attempt to process events if Kafka is unavailable
			continue
		}

		var events []models.Event
		if err := s.db.DB.Where("dispatched = ?", false).Find(&events).Error; err != nil {
			log.Printf("Error fetching events: %v", err)
			continue
		}

		if len(events) > 0 {
			log.Printf("Found %d pending events to process", len(events))
		}

		for _, event := range events {
			if err := s.dispatchEvent(event); err != nil {
				log.Printf("Error dispatching event %s: %v", event.ID, err)
				continue
			}
			log.Printf("Successfully dispatched event %s of type %s for entity %s",
				event.ID, event.Event, event.Entity)
		}
	}
}

func (s *EventHandlerService) dispatchEvent(event models.Event) error {
	// Check if Kafka is enabled before trying to dispatch
	if (!s.kafkaEnabled) {
		return fmt.Errorf("cannot dispatch event: Kafka is not available")
	}

	// Parse event data into a proper object
	var dataMap map[string]interface{}
	if err := json.Unmarshal(event.Data, &dataMap); err != nil {
		log.Printf("Warning: Could not unmarshal event data: %v", err)
		dataMap = make(map[string]interface{})
	}

	// Build a consistent event structure for all resources
	eventPayload := map[string]interface{}{
		"data": dataMap, // Original event data
	}

	// Add standard metadata
	eventPayload["event_id"] = event.ID.String()
	eventPayload["timestamp"] = event.Timestamp
	eventPayload["entity"] = event.Entity
	eventPayload["type"] = event.Event

	// Get topic based on entity type
	topic := getTopicForEvent(event.Entity)

	// Extract and add resource IDs to the top level for easier access
	if noteId, exists := dataMap["note_id"]; exists {
		eventPayload["note_id"] = noteId
	}
	if notebookId, exists := dataMap["notebook_id"]; exists {
		eventPayload["notebook_id"] = notebookId
	}
	if blockId, exists := dataMap["block_id"]; exists {
		eventPayload["block_id"] = blockId
	}
	if userId, exists := dataMap["user_id"]; exists {
		eventPayload["user_id"] = userId
	}

	log.Printf("Dispatching event to topic %s: %v", topic, eventPayload)

	// The type is only needed at the top level, not duplicated in the payload
	fullPayload := map[string]interface{}{
		"type":    event.Event,
		"payload": eventPayload,
	}

	// Publish the event
	jsonData, err := json.Marshal(fullPayload)
	if err != nil {
		return err
	}

	// Use either the custom producer if set, or the global function
	var publishErr error
	if s.kafkaProducer != nil {
		publishErr = s.kafkaProducer.PublishMessage(topic, event.Event, string(jsonData))
	} else {
		publishErr = broker.PublishMessage(topic, event.Event, string(jsonData))
	}

	if publishErr != nil {
		return publishErr
	}

	// Mark the event as dispatched in the database
	now := time.Now()
	return s.db.DB.Model(&event).Updates(map[string]interface{}{
		"dispatched":    true,
		"dispatched_at": now,
		"status":        "completed",
	}).Error
}

func getTopicForEvent(entity string) string {
	switch entity {
	case "block":
		return broker.BlockEventsTopic
	case "note":
		return broker.NoteEventsTopic
	case "notebook":
		return broker.NotebookEventsTopic
	default:
		return broker.SyncEventsTopic
	}
}

// Don't initialize with database here, will be set properly in main.go
var EventHandlerServiceInstance EventHandlerServiceInterface
