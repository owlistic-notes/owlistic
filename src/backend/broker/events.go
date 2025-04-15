package broker

import (
	"encoding/json"
	"log"
	"time"

	"github.com/google/uuid"
)

type EventType string

const (
	NoteCreated     EventType = "NOTE_CREATED"
	NoteUpdated     EventType = "NOTE_UPDATED"
	NoteDeleted     EventType = "NOTE_DELETED"
	NotebookCreated EventType = "NOTEBOOK_CREATED"
	NotebookUpdated EventType = "NOTEBOOK_UPDATED"
	NotebookDeleted EventType = "NOTEBOOK_DELETED"
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
