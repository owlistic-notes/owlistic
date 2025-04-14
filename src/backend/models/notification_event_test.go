package models

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNotificationEventToJSON(t *testing.T) {
	event := NotificationEvent{
		UserID:    "user123",
		EventType: "info",
		Message:   "Test message",
		Timestamp: "2023-01-01T00:00:00Z",
	}

	data, err := event.ToJSON()
	assert.NoError(t, err)

	var result NotificationEvent
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, event, result)
}

func TestNotificationEventFromJSON(t *testing.T) {
	data := `{
		"user_id": "user123",
		"event_type": "info",
		"message": "Test message",
		"timestamp": "2023-01-01T00:00:00Z"
	}`

	var event NotificationEvent
	err := event.FromJSON([]byte(data))
	assert.NoError(t, err)
	assert.Equal(t, "user123", event.UserID)
	assert.Equal(t, "info", event.EventType)
	assert.Equal(t, "Test message", event.Message)
	assert.Equal(t, "2023-01-01T00:00:00Z", event.Timestamp)
}
