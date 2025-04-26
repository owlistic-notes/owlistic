package broker

import (
	"testing"
	"time"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

// MockConsumer implements Consumer interface for testing
type MockConsumer struct {
	messages []*kafka.Message
	closed   bool
}

// NewMockConsumer creates a new mock consumer with optional test messages
func NewMockConsumer() *MockConsumer {
	topic := "mock_topic"
	return &MockConsumer{
		messages: []*kafka.Message{
			{
				TopicPartition: kafka.TopicPartition{Topic: &topic},
				Key:            []byte("mock_key"),
				Value:          []byte("mock_value"),
			},
		},
	}
}

func (m *MockConsumer) ReadMessage(timeoutMs int) (*kafka.Message, error) {
	if m.closed {
		// Use a standard error code instead of ErrConsumerClosed which doesn't exist
		return nil, kafka.NewError(kafka.ErrFail, "Consumer closed", false)
	}

	if len(m.messages) == 0 {
		return nil, kafka.NewError(kafka.ErrTimedOut, "No messages", false)
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
	messageChan := make(chan KafkaMessage, 1)

	// Simulate reading a message and sending it to the channel
	go func() {
		msg, err := mockConsumer.ReadMessage(-1)
		if err != nil {
			t.Errorf("Failed to read message: %v", err)
			return
		}

		messageChan <- KafkaMessage{
			Topic: *msg.TopicPartition.Topic,
			Key:   string(msg.Key),
			Value: string(msg.Value),
		}
	}()

	// Receive the message from the channel
	var receivedMsg KafkaMessage
	select {
	case receivedMsg = <-messageChan:
		// Message received successfully
	case <-time.After(1 * time.Second):
		t.Fatal("Timed out waiting for message")
	}

	// Verify the message content
	if receivedMsg.Topic != "mock_topic" ||
		receivedMsg.Key != "mock_key" ||
		receivedMsg.Value != "mock_value" {
		t.Errorf("Unexpected message content: %+v", receivedMsg)
	}
}
