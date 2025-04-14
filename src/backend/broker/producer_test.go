package broker

import (
	"testing"
)

type MockProducer struct {
	messages []struct {
		topic string
		key   string
		value string
	}
}

func (m *MockProducer) Produce(topic, key, value string) {
	m.messages = append(m.messages, struct {
		topic string
		key   string
		value string
	}{topic, key, value})
}

func TestPublishMessage(t *testing.T) {
	mockProducer := &MockProducer{}

	mockProducer.Produce("test_topic", "test_key", "test_value")

	if len(mockProducer.messages) != 1 {
		t.Fatalf("Expected 1 message, got %d", len(mockProducer.messages))
	}

	msg := mockProducer.messages[0]
	if msg.topic != "test_topic" || msg.key != "test_key" || msg.value != "test_value" {
		t.Errorf("Unexpected message content: %+v", msg)
	}
}
