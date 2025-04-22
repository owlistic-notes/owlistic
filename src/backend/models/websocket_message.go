package models

import (
	"time"

	"github.com/google/uuid"
)

// WebSocketMessageType represents message type constants
type WebSocketMessageType string

const (
	// Message types
	EventMessage     WebSocketMessageType = "event"
	SubscribeMessage WebSocketMessageType = "subscribe"
	ErrorMessage     WebSocketMessageType = "error"
)

// StandardMessage represents a standardized WebSocket message format
type StandardMessage struct {
	ID          string                 `json:"id"`
	Type        WebSocketMessageType   `json:"type"`
	Event       string                 `json:"event,omitempty"` // For event messages
	Timestamp   time.Time              `json:"timestamp"`
	Payload     map[string]interface{} `json:"payload"`
	ResourceID  string                 `json:"resource_id,omitempty"`  // Used for RBAC
	ResourceType string                `json:"resource_type,omitempty"` // Used for RBAC
}

// NewStandardMessage creates a new standard message
func NewStandardMessage(msgType WebSocketMessageType, event string, payload map[string]interface{}) *StandardMessage {
	return &StandardMessage{
		ID:        uuid.New().String(),
		Type:      msgType,
		Event:     event,
		Timestamp: time.Now(),
		Payload:   payload,
	}
}

// WithResource adds resource information to the message
func (m *StandardMessage) WithResource(resourceType string, resourceID string) *StandardMessage {
	m.ResourceType = resourceType
	m.ResourceID = resourceID
	return m
}
