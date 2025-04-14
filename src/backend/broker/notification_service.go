package broker

import (
	"log"

	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

func StartNotificationConsumer(db *database.Database) {
	topics := []string{NotificationTopic}
	groupID := "notification_service"

	StartConsumer(topics, groupID, func(topic string, key string, value string) {
		var event models.NotificationEvent
		if err := event.FromJSON([]byte(value)); err != nil {
			log.Printf("Failed to unmarshal notification event: %v", err)
			return
		}

		log.Printf("Sending notification to user %s: %s", event.UserID, event.Message)

	})
}
