package broker

import (
	"testing"

	"github.com/thinkstack/models"
)

func TestStartNotificationConsumer(t *testing.T) {
	mockHandler := func(topic, key, value string) {
		event := models.NotificationEvent{}
		if err := event.FromJSON([]byte(value)); err != nil {
			t.Fatalf("Failed to unmarshal notification event: %v", err)
		}
		if event.UserID != "mock_user" || event.Message != "mock_message" {
			t.Errorf("Unexpected notification event: %+v", event)
		}
	}

	mockHandler("notification_events", "mock_key", `{"user_id":"mock_user","event_type":"mock_type","message":"mock_message","timestamp":"2023-01-01T00:00:00Z"}`)
}
