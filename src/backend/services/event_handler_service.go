package services

import (
	"encoding/json"
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
}

type EventHandlerService struct {
	db        *database.Database
	isRunning bool
	ticker    *time.Ticker
}

func NewEventHandlerService(db *database.Database) EventHandlerServiceInterface {
	return &EventHandlerService{
		db:        db,
		isRunning: false,
		ticker:    time.NewTicker(1 * time.Second),
	}
}

func (s *EventHandlerService) Start() {
	if s.isRunning {
		return
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

func (s *EventHandlerService) dispatchEvent(event models.Event) error {
	topic := getTopicForEvent(event.Entity)

	// Parse event data into a proper object
	var dataMap map[string]interface{}
	if err := json.Unmarshal(event.Data, &dataMap); err != nil {
		log.Printf("Warning: Could not unmarshal event data: %v", err)
		dataMap = make(map[string]interface{})
	}

	// Add ID directly to the event data for easier extraction
	if id, ok := dataMap["id"]; ok {
		switch event.Entity {
		case "note":
			dataMap["note_id"] = id
		case "notebook":
			dataMap["notebook_id"] = id
		case "block":
			dataMap["block_id"] = id
		}
	}

	// Build a more consistent event structure that matches what the WebSocket handler expects
	eventPayload := map[string]interface{}{
		"event_id":  event.ID.String(),
		"timestamp": event.Timestamp,
		"type":      event.Event,  // Add event type at top level too
		"entity":    event.Entity, // Add entity type at top level
		"data":      dataMap,      // Original event data
	}

	// Extract ID fields and promote them to the top level for better matching
	if id, idExists := dataMap["id"]; idExists {
		switch event.Entity {
		case "note":
			eventPayload["note_id"] = id
		case "notebook":
			eventPayload["notebook_id"] = id
		case "block":
			eventPayload["block_id"] = id
		}
	}

	// Explicitly copy important fields to the top level
	if noteId, exists := dataMap["note_id"]; exists {
		eventPayload["note_id"] = noteId
	}
	if notebookId, exists := dataMap["notebook_id"]; exists {
		eventPayload["notebook_id"] = notebookId
	}
	if blockId, exists := dataMap["block_id"]; exists {
		eventPayload["block_id"] = blockId
	}

	log.Printf("Dispatching event to topic %s: %v", topic, eventPayload)

	// Include the proper payload structure as expected by the client
	fullPayload := map[string]interface{}{
		"type":    event.Event,
		"payload": eventPayload,
	}

	// Publish the event
	jsonData, err := json.Marshal(fullPayload)
	if err != nil {
		return err
	}

	if err := broker.PublishMessage(topic, event.Event, string(jsonData)); err != nil {
		return err
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

var EventHandlerServiceInstance EventHandlerServiceInterface = NewEventHandlerService(nil)
