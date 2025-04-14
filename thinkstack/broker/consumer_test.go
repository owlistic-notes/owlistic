package broker

import (
	"testing"

	"github.com/confluentinc/confluent-kafka-go/kafka"
)

type MockConsumer struct {
	messages []*kafka.Message
}

func (m *MockConsumer) ReadMessage(timeoutMs int) (*kafka.Message, error) {
	if len(m.messages) == 0 {
		return nil, kafka.NewError(kafka.ErrTimedOut, "No messages", false)
	}
	msg := m.messages[0]
	m.messages = m.messages[1:]
	return msg, nil
}

func TestStartConsumer(t *testing.T) {
	mockConsumer := &MockConsumer{
		messages: []*kafka.Message{
			{
				TopicPartition: kafka.TopicPartition{Topic: strPtr("mock_topic")},
				Key:            []byte("mock_key"),
				Value:          []byte("mock_value"),
			},
		},
	}

	messages := []struct {
		topic string
		key   string
		value string
	}{}

	mockHandler := func(topic, key, value string) {
		messages = append(messages, struct {
			topic string
			key   string
			value string
		}{topic, key, value})
	}

	msg, err := mockConsumer.ReadMessage(-1)
	if err != nil {
		t.Fatalf("Failed to read message: %v", err)
	}
	mockHandler(*msg.TopicPartition.Topic, string(msg.Key), string(msg.Value))

	if len(messages) != 1 {
		t.Fatalf("Expected 1 message, got %d", len(messages))
	}

	if messages[0].topic != "mock_topic" || messages[0].key != "mock_key" || messages[0].value != "mock_value" {
		t.Errorf("Unexpected message content: %+v", messages[0])
	}
}

func strPtr(s string) *string {
	return &s
}
