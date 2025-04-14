package services

import (
	"github.com/thinkstack/broker"
	"github.com/thinkstack/models"
)

type NotificationServiceInterface interface {
	PublishNotification(userID, eventType, message, timestamp string) error
}

type NotificationService struct{}

func (s *NotificationService) PublishNotification(userID, eventType, message, timestamp string) error {
	event := models.NotificationEvent{
		UserID:    userID,
		EventType: eventType,
		Message:   message,
		Timestamp: timestamp,
	}

	eventJSON, err := event.ToJSON()
	if err != nil {
		return err
	}

	broker.PublishMessage(broker.NotificationTopic, userID, string(eventJSON))
	return nil
}

var NotificationServiceInstance NotificationServiceInterface = &NotificationService{}
