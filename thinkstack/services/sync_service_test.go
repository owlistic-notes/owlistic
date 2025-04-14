package services

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPublishSyncEvent_Success(t *testing.T) {
	syncService := &SyncService{}
	err := syncService.PublishSyncEvent("device-id", "event-id", "timestamp")
	assert.NoError(t, err)
}
