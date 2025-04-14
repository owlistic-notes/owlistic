package services

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPublishNotification_Success(t *testing.T) {
	notificationService := &NotificationService{}
	err := notificationService.PublishNotification("user-id", "event-type", "message", "timestamp")
	assert.NoError(t, err)
}
