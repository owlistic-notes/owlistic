package services

import (
	"encoding/json"
	"log"
	"time"

	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"
)

type EventHandlerServiceInterface interface {
	Start()
	Stop()
	ProcessPendingEvents()
}

type EventHandlerService struct {
	db        *database.Database
	isRunning bool
	ticker    *time.Ticker
	producer  broker.Producer
}

// NewEventHandlerService creates a new service with the default producer
func NewEventHandlerService(db *database.Database) EventHandlerServiceInterface {
	return &EventHandlerService{
		db:        db,
		isRunning: false,
		ticker:    time.NewTicker(1 * time.Second),
		producer:  broker.DefaultProducer,
	}
}

// NewEventHandlerServiceWithProducer creates a service with a custom producer (for testing)
func NewEventHandlerServiceWithProducer(db *database.Database, producer broker.Producer) EventHandlerServiceInterface {
	return &EventHandlerService{
		db:        db,
		isRunning: false,
		ticker:    time.NewTicker(1 * time.Second),
		producer:  producer,
	}
}

// Start begins the event processing loop
func (s *EventHandlerService) Start() {
	if s.isRunning {
		return
	}

	log.Println("EventHandlerService started successfully")

	s.isRunning = true
	go s.ProcessPendingEvents()
}

// Stop halts the event processing loop
func (s *EventHandlerService) Stop() {
	if !s.isRunning {
		return
	}
	s.isRunning = false
	s.ticker.Stop()
}

// ProcessPendingEvents fetches and processes events from the database
func (s *EventHandlerService) ProcessPendingEvents() {
	for range s.ticker.C {
		if !s.isRunning {
			return
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

// dispatchEvent processes and publishes a single event
func (s *EventHandlerService) dispatchEvent(event models.Event) error {
	// Parse event data into a proper object
	var dataMap map[string]interface{}
	if err := json.Unmarshal(event.Data, &dataMap); err != nil {
		log.Printf("Warning: Could not unmarshal event data: %v", err)
		dataMap = make(map[string]interface{})
	}

	// Determine resource type and ID based on entity
	var resourceType, resourceId string
	resourceType = event.Entity // Default resource type to entity

	// Extract resource IDs
	if noteId, exists := dataMap["note_id"]; exists {
		if resourceType == "note" {
			resourceId = noteId.(string)
		}
	}
	if notebookId, exists := dataMap["notebook_id"]; exists {
		if resourceType == "notebook" {
			resourceId = notebookId.(string)
		}
	}
	if blockId, exists := dataMap["block_id"]; exists {
		if resourceType == "block" {
			resourceId = blockId.(string)
		}
	}

	// Also check for direct ID in the data
	if id, exists := dataMap["id"]; exists && resourceId == "" {
		resourceId = id.(string)
	}

	// Add standard metadata to the data directly (no nested payload)
	dataMap["event_id"] = event.ID.String()
	dataMap["timestamp"] = event.Timestamp
	dataMap["entity"] = event.Entity
	dataMap["type"] = event.Event

	// Get topic based on entity type
	topic := getTopicForEvent(event.Entity)

	log.Printf("Dispatching event to topic %s: %v", topic, dataMap)

	// Create StandardMessage with "event" as type and event.Event as the event name
	message := models.NewStandardMessage(models.EventMessage, event.Event, dataMap).
		WithResource(resourceType, resourceId)

	// Publish the event using the StandardMessage format
	jsonData, err := json.Marshal(message)
	if err != nil {
		return err
	}

	publishErr := s.producer.PublishMessage(topic, string(jsonData))
	if publishErr != nil {
		return publishErr
	}

	// Mark the event as dispatched in the database
	return s.db.DB.Model(&event).Updates(map[string]interface{}{
		"dispatched":    true,
		"status":        "completed",
		"dispatched_at": time.Now().UTC(),
	}).Error
}

func getTopicForEvent(entity string) string {
	switch entity {
	case "user":
		return broker.UserSubject
	case "notebook":
		return broker.NotebookSubject
	case "note":
		return broker.NoteSubject
	case "block":
		return broker.BlockSubject
	case "task":
		return broker.TaskSubject
	default:
		return broker.NotebookSubject
	}
}

// Don't initialize with database here, will be set properly in main.go
var EventHandlerServiceInstance EventHandlerServiceInterface
