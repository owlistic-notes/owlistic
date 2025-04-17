package broker

import (
	"encoding/json"
	"log"
	"time"

	"github.com/google/uuid"
)

type EventType string

const (
	// Standardized event types in format: <resource>.<action>
	NoteCreated     EventType = "note.created"
	NoteUpdated     EventType = "note.updated"
	NoteDeleted     EventType = "note.deleted"
	NotebookCreated EventType = "notebook.created"
	NotebookUpdated EventType = "notebook.updated"
	NotebookDeleted EventType = "notebook.deleted"
	BlockCreated    EventType = "block.created"
	BlockUpdated    EventType = "block.updated"
	BlockDeleted    EventType = "block.deleted"
	TaskCreated     EventType = "task.created"
	TaskUpdated     EventType = "task.updated"
	TaskDeleted     EventType = "task.deleted"
)

type Event struct {
	ID        string         `json:"id"`
	Type      EventType      `json:"type"`
	Timestamp time.Time      `json:"timestamp"`
	Payload   map[string]any `json:"payload"`
}

var kafkaEnabled = true

// SetKafkaEnabled allows toggling Kafka feature
func SetKafkaEnabled(enabled bool) {
	kafkaEnabled = enabled
}

// IsKafkaEnabled returns whether Kafka is currently enabled
func IsKafkaEnabled() bool {
	return kafkaEnabled
}

func PublishEvent(topic string, eventType EventType, payload map[string]any) error {
	if !kafkaEnabled {
		log.Printf("Kafka disabled: would have published %s event to %s", eventType, topic)
		return nil
	}

	event := Event{
		ID:        uuid.New().String(),
		Type:      eventType,
		Timestamp: time.Now().UTC(),
		Payload:   payload,
	}

	eventJSON, err := json.Marshal(event)
	if err != nil {
		return err
	}

	PublishMessage(topic, event.ID, string(eventJSON))
	return nil
}
