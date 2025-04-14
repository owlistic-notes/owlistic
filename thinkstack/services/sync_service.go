package services

import (
	"github.com/thinkstack/broker"
	"github.com/thinkstack/models"
)

type SyncServiceInterface interface {
	PublishSyncEvent(deviceID, lastEventID, timestamp string) error
}

type SyncService struct{}

func (s *SyncService) PublishSyncEvent(deviceID, lastEventID, timestamp string) error {
	event := models.SyncEvent{
		DeviceID:    deviceID,
		LastEventID: lastEventID,
		Timestamp:   timestamp,
	}

	eventJSON, err := event.ToJSON()
	if err != nil {
		return err
	}

	broker.PublishMessage(broker.SyncEventsTopic, deviceID, string(eventJSON))
	return nil
}

var SyncServiceInstance SyncServiceInterface = &SyncService{}
