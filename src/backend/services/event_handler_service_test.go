package services

import (
	"testing"
	"time"

	"daviderutigliano/owlistic/database"
	"daviderutigliano/owlistic/models"
	"daviderutigliano/owlistic/testutils"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// MockProducer implements the broker.Producer interface for testing
type MockProducer struct {
	mock.Mock
	available bool
}

func NewMockProducer() *MockProducer {
	return &MockProducer{available: true}
}

func (m *MockProducer) PublishMessage(topic string, key string, value string) error {
	args := m.Called(topic, key, value)
	return args.Error(0)
}

func (m *MockProducer) Close() {
	m.Called()
}

func (m *MockProducer) IsAvailable() bool {
	args := m.Called()
	return args.Bool(0)
}

func TestEventHandlerService_ProcessPendingEvents(t *testing.T) {
	db, dbMock, close := testutils.SetupMockDB()
	defer close()

	// Create a mock producer
	mockProducer := NewMockProducer()
	mockProducer.On("PublishMessage", mock.Anything, mock.Anything, mock.Anything).Return(nil)

	// Setup test data
	dbMock.ExpectQuery("SELECT \\* FROM \"events\" WHERE dispatched = \\$1").
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
	dbMock.ExpectBegin()
	dbMock.ExpectExec("UPDATE \"events\" SET").
		WillReturnResult(testutils.NewResult(1, 1))
	dbMock.ExpectCommit()

	// Create service with our mock producer
	service := NewEventHandlerServiceWithProducer(db, mockProducer)

	service.Start()
	time.Sleep(2 * time.Second) // Allow some time for processing
	service.Stop()

	assert.NoError(t, dbMock.ExpectationsWereMet())
	mockProducer.AssertExpectations(t)
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
