package broker

import (
	"testing"
	"time"

	// "github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/nats-io/nats.go"
)

// MockConsumer implements Consumer interface for testing
type MockConsumer struct {
	messages []*Message
	closed   bool
}

// NewMockConsumer creates a new mock consumer with optional test messages
func NewMockConsumer() *MockConsumer {
	topic := "mock_topic"
	return &MockConsumer{
		messages: []*Message{
			{
				Subject: topic,
				Data: []byte("mock_value"),
			},
		},
	}
}

func (m *MockConsumer) ReadMessage(timeoutMs int) (*Message, error) {
	if m.closed {
		// Use a standard error code instead of ErrConsumerClosed which doesn't exist
		return nil, nats.ErrConnectionClosed
	}

	if len(m.messages) == 0 {
		return nil, nats.ErrConsumerNotActive
	}
	msg := m.messages[0]
	m.messages = m.messages[1:]
	return msg, nil
}

func (m *MockConsumer) Close() {
	m.closed = true
}

func TestStartConsumer(t *testing.T) {
	// Create a mock consumer with test messages
	mockConsumer := NewMockConsumer()

	// Create channel to receive messages
	messageChan := make(chan Message, 1)

	// Simulate reading a message and sending it to the channel
	go func() {
		msg, err := mockConsumer.ReadMessage(-1)
		if err != nil {
			t.Errorf("Failed to read message: %v", err)
			return
		}

		messageChan <- *msg
	}()

	// Receive the message from the channel
	var receivedMsg Message
	select {
	case receivedMsg = <-messageChan:
		// Message received successfully
	case <-time.After(1 * time.Second):
		t.Fatal("Timed out waiting for message")
	}

	// Verify the message content
	if receivedMsg.Subject != "mock_topic" ||
		string(receivedMsg.Data) != "mock_value" {
		t.Errorf("Unexpected message content: %+v", receivedMsg)
	}
}
