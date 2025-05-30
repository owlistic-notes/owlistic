package services

import (
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"
	"owlistic-notes/owlistic/testutils"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
)

// MockAuthService for testing
type MockAuthService struct{}

func (m *MockAuthService) Login(db *database.Database, email, password string) (string, error) {
	return "mock.jwt.token", nil
}

func (m *MockAuthService) ValidateToken(tokenString string) (*JWTClaims, error) {
	return &JWTClaims{
		UserID: uuid.New(),
		Email:  "test@example.com",
	}, nil
}

func (m *MockAuthService) HashPassword(password string) (string, error) {
	return "hashed-password", nil
}

func (m *MockAuthService) ComparePasswords(hashedPassword, password string) error {
	return nil
}

// MockWebSocketConnection mocks a WebSocket connection
type MockWebSocketConnection struct {
	mock.Mock
	receivedMessages []string
}

func (m *MockWebSocketConnection) ReadMessage() (int, []byte, error) {
	args := m.Called()
	return args.Int(0), args.Get(1).([]byte), args.Error(2)
}

func (m *MockWebSocketConnection) WriteMessage(messageType int, data []byte) error {
	m.receivedMessages = append(m.receivedMessages, string(data))
	return nil
}

func (m *MockWebSocketConnection) Close() error {
	m.Called()
	return nil
}

func (m *MockWebSocketConnection) SetReadDeadline(t time.Time) error {
	return nil
}

func (m *MockWebSocketConnection) SetWriteDeadline(t time.Time) error {
	return nil
}

func (m *MockWebSocketConnection) NextWriter(messageType int) (interface{}, error) {
	return nil, nil
}

// Mock Broker
type MockBroker struct {
	mock.Mock
	messages chan broker.Message
}

func (m *MockBroker) SendMessage(msg broker.Message) {
	if m.messages != nil {
		m.messages <- msg
	}
}

// MockConsumer implements the broker.Consumer interface for testing
type MockConsumer struct {
	mock.Mock
	messageChan chan broker.Message
	closed      bool
}

func NewMockConsumer() *MockConsumer {
	return &MockConsumer{
		messageChan: make(chan broker.Message, 10),
		closed:      false,
	}
}

func (m *MockConsumer) GetMessageChannel() <-chan broker.Message {
	return m.messageChan
}

func (m *MockConsumer) Close() {
	m.Called()
	m.closed = true
}

func (m *MockConsumer) SendTestMessage(msg broker.Message) {
	if !m.closed {
		m.messageChan <- msg
	}
}

// Setup helper that uses our testable service
func setupWebSocketTest(t *testing.T) (*WebSocketService, *MockConsumer) {
	db, _, _ := testutils.SetupMockDB()

	// Create a mock consumer
	mockConsumer := NewMockConsumer()
	mockConsumer.On("Close").Return()

	// Create the WebSocket service
	service := NewWebSocketServiceWithTopics(db, []string{"test_topic"}).(*WebSocketService)
	service.isRunning = true
	service.messageChan = mockConsumer.messageChan

	// Also store the mockConsumer for easy reference in tests
	// Create a test connection to add to the websocket service
	userId := uuid.New()
	testConnection := &websocketConnection{
		userID: userId,
		send:   make(chan []byte, 10),
	}
	service.connections = map[string]*websocketConnection{
		"test-conn-id": testConnection,
	}

	log.Printf("Test WebSocket service started with mock channel")

	return service, mockConsumer
}

// safeStop provides a safe way to stop a test WebSocket service
func safeStop(service *WebSocketService) {
	if !service.isRunning {
		return
	}

	service.isRunning = false

	// Close all connections
	for id, conn := range service.connections {
		close(conn.send)
		delete(service.connections, id)
	}

	log.Println("WebSocket service stopped for tests")
}

// TestWebSocketService_BroadcastMessage tests message broadcasting
func TestWebSocketService_BroadcastMessage(t *testing.T) {
	service, _ := setupWebSocketTest(t)

	// Get the test connection we created in setup
	var testConn *websocketConnection
	for _, conn := range service.connections {
		testConn = conn
		break
	}

	if testConn == nil {
		t.Fatal("Test connection not found")
	}

	// Start a goroutine to check if the message is received
	messageReceived := make(chan struct{})
	go func() {
		select {
		case msg := <-testConn.send:
			// Convert the event to a StandardMessage to verify its contents
			var event models.StandardMessage
			err := json.Unmarshal(msg, &event)
			assert.NoError(t, err)
			assert.Equal(t, models.EventMessage, event.Type)
			assert.Equal(t, "test_event", event.Event)
			close(messageReceived)
		case <-time.After(100 * time.Millisecond):
			t.Error("Timeout waiting for broadcast message")
			close(messageReceived)
		}
	}()

	// Create a test event and broadcast it
	testEvent := &models.StandardMessage{
		Type:  models.EventMessage,
		Event: "test_event",
	}
	service.BroadcastEvent(testEvent)

	// Wait for the message to be processed
	select {
	case <-messageReceived:
		// Test passed
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Timeout waiting for broadcast message to be received")
	}

	safeStop(service)
}

// TestWebSocketService_HandleMessage tests message processing
func TestWebSocketService_HandleMessage(t *testing.T) {
	service, mockConsumer := setupWebSocketTest(t)

	// Get the test connection we created in setup
	var testConn *websocketConnection
	for _, conn := range service.connections {
		testConn = conn
		break
	}

	if testConn == nil {
		t.Fatal("Test connection not found")
	}

	// Start a goroutine that consumes messages
	go service.consumeMessages()

	// Create a channel to signal test completion
	messageReceived := make(chan struct{})

	// Start goroutine to check what the client receives
	go func() {
		select {
		case msg := <-testConn.send:
			// Parse the message to verify contents
			var event models.StandardMessage
			err := json.Unmarshal(msg, &event)
			assert.NoError(t, err)
			assert.Equal(t, models.EventMessage, event.Type)
			assert.Equal(t, "note.updated", event.Event)

			// Check payload
			assert.Equal(t, "Test Note", event.Payload["title"])

			close(messageReceived)
		case <-time.After(500 * time.Millisecond):
			t.Error("Timeout waiting for message")
			close(messageReceived)
		}
	}()

	// Create a test message
	eventData := models.StandardMessage{
		Type:         models.EventMessage,
		Event:        "note.updated",
		ResourceType: "note",
		ResourceID:   "note-123",
		Payload: map[string]interface{}{
			"title": "Test Note",
		},
	}
	eventJson, _ := json.Marshal(eventData)

	// Send the message through the mock consumer
	mockConsumer.SendTestMessage(broker.Message{
		Subject: "note.updated",
		Data: []byte(eventJson),
	})

	// Wait for message to be processed
	select {
	case <-messageReceived:
		// Test passed
	case <-time.After(1000 * time.Millisecond):
		t.Fatal("Timeout waiting for message to be received by client")
	}

	safeStop(service)
}

// TestWebSocketHandler tests the WebSocket HTTP handler
func TestWebSocketHandler(t *testing.T) {
	service, _ := setupWebSocketTest(t)

	// Create a request to the websocket endpoint
	req := httptest.NewRequest("GET", "/ws", nil)
	w := httptest.NewRecorder()

	// Set the userID in the request context, simulating auth middleware
	testUserID := uuid.New()

	// Replace the service's upgrader with our test version
	originalUpgrader := upgrader
	defer func() { upgrader = originalUpgrader }()

	upgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool {
			return true
		},
		Error: func(w http.ResponseWriter, r *http.Request, status int, reason error) {
		},
	}

	// Since we can't fully test the websocket handler without a real connection,
	// we'll just verify that the handler accepts the request with the user ID

	// In a real server context with Gin, this would be populated by middleware
	c := testutils.GetTestGinContext(w, req)
	c.Set("userID", testUserID)

	// This is not a complete test since we can't establish a real websocket connection,
	// but at least we can verify the handler accepts the context with userID
	assert.NotPanics(t, func() {
		service.HandleConnection(c)
	})

	safeStop(service)
}

// TestForwardMessages tests the  message consumption mechanism
func TestForwardMessages(t *testing.T) {
	service, mockConsumer := setupWebSocketTest(t)

	// Get the test connection we created in setup
	var testConn *websocketConnection
	for _, conn := range service.connections {
		testConn = conn
		break
	}

	if testConn == nil {
		t.Fatal("Test connection not found")
	}

	// Start a goroutine that consumes messages
	go service.consumeMessages()

	// Create a channel to signal test completion
	messageReceived := make(chan struct{})

	// Start goroutine to check what the client receives
	go func() {
		select {
		case msg := <-testConn.send:
			// Parse the message to verify contents
			var event models.StandardMessage
			err := json.Unmarshal(msg, &event)
			assert.NoError(t, err)
			assert.Equal(t, models.EventMessage, event.Type)
			assert.Equal(t, "test_event", event.Event)

			// Check payload
			assert.Equal(t, "value", event.Payload["test"])

			close(messageReceived)
		case <-time.After(500 * time.Millisecond):
			t.Error("Timeout waiting for message")
			close(messageReceived)
		}
	}()

	// Create a test event
	eventData := models.StandardMessage{
		Type:  models.EventMessage,
		Event: "test_event",
		Payload: map[string]interface{}{
			"test": "value",
		},
	}
	eventJson, _ := json.Marshal(eventData)

	// Send a test message through the mock consumer
	mockConsumer.SendTestMessage(broker.Message{
		Subject: "test.key",
		Data:    []byte(eventJson),
	})

	// Wait for message to be processed
	select {
	case <-messageReceived:
		// Test passed
	case <-time.After(1000 * time.Millisecond):
		t.Fatal("Timeout waiting for message to be received by client")
	}

	safeStop(service)
}
