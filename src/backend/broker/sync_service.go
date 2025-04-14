package broker

import (
	"log"

	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

func StartSyncConsumer(db *database.Database) {
	topics := []string{SyncEventsTopic}
	groupID := "sync_service"

	StartConsumer(topics, groupID, func(topic string, key string, value string) {
		var event models.SyncEvent
		if err := event.FromJSON([]byte(value)); err != nil {
			log.Printf("Failed to unmarshal sync event: %v", err)
			return
		}

		log.Printf("Syncing data for device %s with last event ID %s", event.DeviceID, event.LastEventID)

		var note models.Note
		if err := db.DB.First(&note, "id = ?", event.LastEventID).Error; err != nil {
			log.Printf("Failed to fetch note for sync: %v", err)
			return
		}

		log.Printf("Syncing note: %v", note)
	})
}
