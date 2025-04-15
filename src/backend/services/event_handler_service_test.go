package services

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"github.com/thinkstack/testutils"
)

func TestEventHandlerService_ProcessPendingEvents(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	// Setup test data
	mock.ExpectQuery(`SELECT \* FROM "events" WHERE dispatched = \$1`).
		WithArgs(false).
		WillReturnRows(testutils.MockEventRows([]models.Event{
			{
				Event:     "test.created",
				Entity:    "test",
				Operation: "create",
				ActorID:   "user-123",
			},
		}))

	// Expect update after processing
	mock.ExpectBegin()
	mock.ExpectExec(`UPDATE "events" SET`).
		WillReturnResult(testutils.NewResult(1, 1))
	mock.ExpectCommit()

	service := NewEventHandlerService(db)
	service.Start()
	time.Sleep(2 * time.Second) // Allow some time for processing
	service.Stop()

	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestEventHandlerService_Lifecycle(t *testing.T) {
	db := &database.Database{}
	service := NewEventHandlerService(db)

	// Test Start
	service.Start()
	assert.True(t, service.(*EventHandlerService).isRunning)

	// Test double Start
	service.Start() // Should be no-op
	assert.True(t, service.(*EventHandlerService).isRunning)

	// Test Stop
	service.Stop()
	assert.False(t, service.(*EventHandlerService).isRunning)

	// Test double Stop
	service.Stop() // Should be no-op
	assert.False(t, service.(*EventHandlerService).isRunning)
}
