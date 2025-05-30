package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type Event struct {
	ID           uuid.UUID       `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Event        string          `gorm:"not null" json:"event"`
	Version      int             `gorm:"not null" json:"version"`
	Entity       string          `gorm:"not null" json:"entity"`
	Timestamp    time.Time       `gorm:"not null" json:"timestamp"`
	Data         json.RawMessage `gorm:"type:jsonb;not null" json:"data"`
	Status       string          `gorm:"not null;default:'pending'" json:"status"`
	Dispatched   bool            `gorm:"not null;default:false" json:"dispatched"`
	DispatchedAt *time.Time      `json:"dispatched_at,omitempty"`
}

func NewEvent(event, entity, operation, actorID string, data interface{}) (*Event, error) {
	dataBytes, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}

	// Use standardized event name format
	return &Event{
		ID:        uuid.New(),
		Event:     event,
		Version:   1,
		Entity:    entity,
		Timestamp: time.Now().UTC(),
		Data:      dataBytes,
		Status:    "pending",
	}, nil
}
