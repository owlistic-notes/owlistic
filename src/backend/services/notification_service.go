package services

import (
	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/models"
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

	// Always use the DefaultProducer directly - it will never be null
	return broker.DefaultProducer.PublishMessage(broker.NotificationTopic, userID, string(eventJSON))
}

var NotificationServiceInstance NotificationServiceInterface = &NotificationService{}
