package models

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSyncEventToJSON(t *testing.T) {
	event := SyncEvent{
		DeviceID:    "device123",
		LastEventID: "event456",
		Timestamp:   "2023-01-01T00:00:00Z",
	}

	data, err := event.ToJSON()
	assert.NoError(t, err)

	var result SyncEvent
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, event, result)
}

func TestSyncEventFromJSON(t *testing.T) {
	data := `{
		"device_id": "device123",
		"last_event_id": "event456",
		"timestamp": "2023-01-01T00:00:00Z"
	}`

	var event SyncEvent
	err := event.FromJSON([]byte(data))
	assert.NoError(t, err)
	assert.Equal(t, "device123", event.DeviceID)
	assert.Equal(t, "event456", event.LastEventID)
	assert.Equal(t, "2023-01-01T00:00:00Z", event.Timestamp)
}
