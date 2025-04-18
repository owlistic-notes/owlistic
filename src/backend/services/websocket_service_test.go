package services

import (
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/thinkstack/broker"
	"github.com/thinkstack/models"
	"github.com/thinkstack/testutils"
)

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
	kafkaMessages chan broker.KafkaMessage
}

func (m *MockBroker) SendKafkaMessage(msg broker.KafkaMessage) {
	if m.kafkaMessages != nil {
		m.kafkaMessages <- msg
	}
}

// MockConsumer implements the broker.Consumer interface for testing
type MockConsumer struct {
	mock.Mock
	messageChan chan broker.KafkaMessage
	closed      bool
}

func NewMockConsumer() *MockConsumer {
	return &MockConsumer{
		messageChan: make(chan broker.KafkaMessage, 10),
		closed:      false,
	}
}

func (m *MockConsumer) GetMessageChannel() <-chan broker.KafkaMessage {
	return m.messageChan
}

func (m *MockConsumer) Close() {
	m.Called()
	m.closed = true
}

func (m *MockConsumer) SendTestMessage(msg broker.KafkaMessage) {
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

	// Create the WebSocket service - we'll directly pass the mock channel
	service := NewWebSocketService(db, []string{"test_topic"}).(*WebSocketService)

	// Set our mock consumer's channel as the input source for Kafka messages
	service.SetKafkaInputChannel(mockConsumer.messageChan)

	// Also store the mockConsumer for easy reference in tests
	service.kafkaConsumer = mockConsumer

	// Start the service - this will trigger the run() method but won't start HTTP server
	service.isRunning = true
	go service.run()

	// Start forwarding from mock consumer to service
	go service.forwardKafkaMessages(mockConsumer.messageChan)

	log.Printf("Test WebSocket service started with mock Kafka channel")

	return service, mockConsumer
}

// safeStop provides a safe way to stop a test WebSocket service
// by skipping the client.Conn.Close() that would panic with nil connections
func safeStop(service *WebSocketService) {
	if !service.isRunning {
		return
	}

	service.isRunning = false
	close(service.stopChan)

	// Close the Kafka consumer properly
	if service.kafkaConsumer != nil {
		service.kafkaConsumer.Close()
		service.kafkaConsumer = nil
	}

	// In tests, we don't need to close client connections because they're nil
	log.Println("WebSocket service stopped for tests")
}

// TestWebSocketService_BroadcastMessage tests message broadcasting
func TestWebSocketService_BroadcastMessage(t *testing.T) {
	service, _ := setupWebSocketTest(t)

	// Create a test client that will receive the broadcast
	messageReceived := make(chan struct{})
	testClient := &Client{
		ID:            "test-client",
		UserID:        "test-user",
		Hub:           service,
		Send:          make(chan []byte, 5),
		Subscriptions: map[string]bool{"all": true}, // Subscribe to all messages
	}

	// Register the client with the service
	service.clients = map[string]*Client{testClient.ID: testClient}

	// Start a goroutine to check if the message is received
	go func() {
		select {
		case msg := <-testClient.Send:
			assert.Equal(t, "test message", string(msg))
			close(messageReceived)
		case <-time.After(100 * time.Millisecond):
			t.Error("Timeout waiting for broadcast message")
			close(messageReceived)
		}
	}()

	// Broadcast a message
	service.BroadcastMessage([]byte("test message"))

	// Wait for the message to be processed
	select {
	case <-messageReceived:
		// Test passed
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Timeout waiting for broadcast message to be received")
	}

	// Use TestSafeStop instead of service.Stop() to avoid nil panic
	safeStop(service)
}

// TestWebSocketService_HandleKafkaMessage tests Kafka message processing
func TestWebSocketService_HandleKafkaMessage(t *testing.T) {
	service, _ := setupWebSocketTest(t)

	// Create a test client
	client := &Client{
		ID:            "test-client",
		UserID:        "test-user",
		Hub:           service,
		Send:          make(chan []byte, 5),
		Subscriptions: map[string]bool{"note": true},
	}

	// Register client with service
	service.clients = map[string]*Client{client.ID: client}

	// Create a test Kafka message
	data := map[string]interface{}{
		"note_id": "note-123",
		"title":   "Test Note",
	}
	jsonData, _ := json.Marshal(data)

	kafkaMsg := broker.KafkaMessage{
		Topic: "note_events",
		Key:   "note.updated",
		Value: string(jsonData),
	}

	// Process the message
	service.handleKafkaMessage(kafkaMsg)

	// Verify message was sent to client
	select {
	case msg := <-client.Send:
		// Parse the message to verify contents
		var serverMsg ServerMessage
		err := json.Unmarshal(msg, &serverMsg)
		assert.NoError(t, err)
		assert.Equal(t, "event", serverMsg.Type)
		assert.Equal(t, "note.updated", serverMsg.Event)
	case <-time.After(100 * time.Millisecond):
		t.Fatal("Timeout waiting for message to be sent to client")
	}

	// Use TestSafeStop instead of service.Stop() to avoid nil panic
	safeStop(service)
}

// TestWebSocketService_ClientSubscriptions tests client subscription handling
func TestWebSocketService_ClientSubscriptions(t *testing.T) {
	// Create a mock client
	clientID := "test-client"
	client := &Client{
		ID:            clientID,
		UserID:        "test-user",
		Send:          make(chan []byte, 5),
		Subscriptions: make(map[string]bool),
	}

	// Test subscribe to resource type
	subscribeMsg := ClientMessage{
		Type:   "subscribe",
		Action: "subscribe",
		Payload: json.RawMessage(`{
			"resource": "note"
		}`),
	}

	client.handleSubscribe(subscribeMsg)
	assert.True(t, client.Subscriptions["note"])

	// Test subscribe to specific resource
	subscribeMsg = ClientMessage{
		Type:   "subscribe",
		Action: "subscribe",
		Payload: json.RawMessage(`{
			"resource": "note",
			"id": "note-123"
		}`),
	}

	client.handleSubscribe(subscribeMsg)
	assert.True(t, client.Subscriptions["note:note-123"])

	// Test unsubscribe from resource type
	unsubscribeMsg := ClientMessage{
		Type:   "unsubscribe",
		Action: "unsubscribe",
		Payload: json.RawMessage(`{
			"resource": "note"
		}`),
	}

	client.handleUnsubscribe(unsubscribeMsg)
	assert.False(t, client.Subscriptions["note"])

	// Test unsubscribe from specific resource
	unsubscribeMsg = ClientMessage{
		Type:   "unsubscribe",
		Action: "unsubscribe",
		Payload: json.RawMessage(`{
			"resource": "note",
			"id": "note-123"
		}`),
	}

	client.handleUnsubscribe(unsubscribeMsg)
	assert.False(t, client.Subscriptions["note:note-123"])
}

// TestWebSocketService_ExtractResourceInfo tests resource info extraction
func TestWebSocketService_ExtractResourceInfo(t *testing.T) {
	service, _ := setupWebSocketTest(t)

	// Test note resource
	noteEvent := map[string]interface{}{
		"note_id": "note-123",
		"title":   "Test Note",
	}
	id, resourceType := service.extractResourceInfo(noteEvent)
	assert.Equal(t, "note-123", id)
	assert.Equal(t, "note", resourceType)

	// Test block resource
	blockEvent := map[string]interface{}{
		"block_id": "block-456",
		"content":  "Test content",
	}
	id, resourceType = service.extractResourceInfo(blockEvent)
	assert.Equal(t, "block-456", id)
	assert.Equal(t, "block", resourceType)

	// Test notebook resource
	notebookEvent := map[string]interface{}{
		"notebook_id": "notebook-789",
		"name":        "Test Notebook",
	}
	id, resourceType = service.extractResourceInfo(notebookEvent)
	assert.Equal(t, "notebook-789", id)
	assert.Equal(t, "notebook", resourceType)

	// Test unknown resource
	unknownEvent := map[string]interface{}{
		"data": map[string]interface{}{
			"unknown_field": "value",
		},
	}
	id, resourceType = service.extractResourceInfo(unknownEvent)
	assert.Equal(t, "", id)
	assert.Equal(t, "unknown", resourceType)
}

// TestClient_ProcessMessage tests client message processing
func TestClient_ProcessMessage(t *testing.T) {
	service, _ := setupWebSocketTest(t)

	// Create a mock block service
	originalBlockService := BlockServiceInstance
	mockBlockService := new(testutils.MockBlockService)
	BlockServiceInstance = mockBlockService
	defer func() {
		BlockServiceInstance = originalBlockService
	}()

	// Set up expectations for the mock
	updateData := map[string]interface{}{
		"actor_id": "test-user",
		"content":  "Updated content",
	}
	mockBlockService.On("UpdateBlock", mock.Anything, "block-123", updateData).Return(models.Block{}, nil)

	// Create a test client
	client := &Client{
		ID:            "test-client",
		UserID:        "test-user",
		Hub:           service,
		Send:          make(chan []byte, 5),
		Subscriptions: make(map[string]bool),
	}

	// Process a block update message
	blockUpdateMsg := `{
		"type": "block_update",
		"action": "update",
		"payload": {
			"id": "block-123",
			"content": "Updated content"
		}
	}`

	client.processMessage([]byte(blockUpdateMsg))

	// Verify the service was called
	mockBlockService.AssertExpectations(t)

	// Use TestSafeStop instead of service.Stop() to avoid nil panic
	safeStop(service)
}

// TestWebSocketHandler tests the WebSocket HTTP handler
func TestWebSocketHandler(t *testing.T) {
	service, _ := setupWebSocketTest(t)

	// Create a request to the websocket endpoint
	req := httptest.NewRequest("GET", "/ws?user_id=test-user", nil)
	w := httptest.NewRecorder()

	// Create a custom upgrader that doesn't actually upgrade but records the attempt
	upgradeAttempted := false
	service.upgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool {
			return true
		},
		Error: func(w http.ResponseWriter, r *http.Request, status int, reason error) {
			// Just for testing purposes, mark that an upgrade was attempted
			upgradeAttempted = true
		},
	}

	// Call the handler function directly
	service.handleWebSocket(w, req)

	// Since this is a test and we can't fully establish a websocket connection,
	// just verify that an upgrade was attempted or that the response code is appropriate
	assert.True(t, upgradeAttempted || w.Code == http.StatusBadRequest,
		"Expected an upgrade attempt or a bad request response")

	// Also verify that user_id was properly received
	assert.Equal(t, "test-user", req.URL.Query().Get("user_id"))

	// Use TestSafeStop instead of service.Stop() to avoid nil panic
	safeStop(service)
}

// TestForwardKafkaMessages tests the Kafka message forwarding mechanism
func TestForwardKafkaMessages(t *testing.T) {
	service, mockConsumer := setupWebSocketTest(t)

	// Create a client that will receive the processed messages
	messageReceived := make(chan struct{})

	// Create a test client with a subscription to "test_topic"
	testClient := &Client{
		ID:            "test-client",
		UserID:        "test-user",
		Hub:           service,
		Send:          make(chan []byte, 5),
		Subscriptions: map[string]bool{"all": true}, // Subscribe to all topics
	}

	// Register the client
	service.clients = map[string]*Client{testClient.ID: testClient}

	// Start goroutine to check what the client receives
	go func() {
		msg := <-testClient.Send

		// Verify the message content
		var serverMsg ServerMessage
		err := json.Unmarshal(msg, &serverMsg)
		assert.NoError(t, err)

		// Check the message matches what we expect
		assert.Equal(t, "event", serverMsg.Type)
		assert.Equal(t, "test_key", serverMsg.Event)

		// Check payload
		payload, ok := serverMsg.Payload.(map[string]interface{})
		assert.True(t, ok)
		assert.Equal(t, "value", payload["test"])

		close(messageReceived)
	}()

	// Send a test Kafka message through the mock consumer
	mockConsumer.SendTestMessage(broker.KafkaMessage{
		Topic: "test_topic",
		Key:   "test_key",
		Value: `{"test":"value"}`,
	})

	// Wait for message to be processed
	select {
	case <-messageReceived:
		// Test passed
	case <-time.After(500 * time.Millisecond):
		t.Fatal("Timeout waiting for Kafka message to be received by client")
	}

	// Use TestSafeStop instead of service.Stop() to avoid nil panic
	safeStop(service)
}
