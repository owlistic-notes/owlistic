package broker

import (
	"testing"

	"github.com/thinkstack/models"
)

func TestStartSyncConsumer(t *testing.T) {
	mockHandler := func(topic, key, value string) {
		event := models.SyncEvent{}
		if err := event.FromJSON([]byte(value)); err != nil {
			t.Fatalf("Failed to unmarshal sync event: %v", err)
		}
		if event.DeviceID != "mock_device" || event.LastEventID != "mock_event" {
			t.Errorf("Unexpected sync event: %+v", event)
		}
	}

	mockHandler("sync_events", "mock_key", `{"device_id":"mock_device","last_event_id":"mock_event","timestamp":"2023-01-01T00:00:00Z"}`)
}
