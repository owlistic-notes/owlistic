package broker

import (
	"log"
	"os"
	"sync"
	"time"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"github.com/thinkstack/config"
)

// KafkaMessage represents a message received from Kafka
type KafkaMessage struct {
	Topic string
	Key   string
	Value string
}

// Consumer defines the interface for message consumption
type Consumer interface {
	// GetMessageChannel returns the channel that will receive messages
	GetMessageChannel() <-chan KafkaMessage
	// Close stops the consumer and releases resources
	Close()
}

// KafkaConsumer implements the Consumer interface
type KafkaConsumer struct {
	consumer    *kafka.Consumer
	messageChan chan KafkaMessage
	topics      []string
	groupID     string
	mutex       sync.RWMutex
	closed      bool
}

// Global variables for consumer management
var (
	consumers     map[string]*KafkaConsumer = make(map[string]*KafkaConsumer)
	consumerMutex sync.RWMutex
)

// NewKafkaConsumer creates a new KafkaConsumer for the specified topics and group ID
func NewKafkaConsumer(broker string, topics []string, groupID string) (Consumer, error) {
	consumerKey := groupID + ":" + topics[0] // Use first topic as part of the key

	consumerMutex.RLock()
	if c, exists := consumers[consumerKey]; exists {
		consumerMutex.RUnlock()
		log.Printf("Reusing existing Kafka consumer for group %s", groupID)
		return c, nil
	}
	consumerMutex.RUnlock()

	// Use localhost as fallback if not specified
	if broker == "" {
		broker = "localhost:9092"
	}

	// Log the actual broker address we're trying to connect to
	log.Printf("Kafka consumer connecting to broker: %s for topics: %v with group: %s", broker, topics, groupID)

	// Create a buffered channel for messages
	messageChan := make(chan KafkaMessage, 100)

	consumer := &KafkaConsumer{
		messageChan: messageChan,
		topics:      topics,
		groupID:     groupID,
		closed:      false,
	}

	// Store reference to consumer immediately so we can return it even on error
	consumerMutex.Lock()
	consumers[consumerKey] = consumer
	consumerMutex.Unlock()

	// Create consumer with robust configuration
	kafkaConsumer, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers":         broker,
		"group.id":                  groupID,
		"auto.offset.reset":         "earliest",
		"socket.timeout.ms":         10000,
		"session.timeout.ms":        30000,
		"max.poll.interval.ms":      300000,
		"enable.auto.commit":        true,
		"auto.commit.interval.ms":   5000,
		"enable.partition.eof":      false,
		"client.id":                 "thinkstack-consumer-" + groupID,
		"broker.address.family":     "v4",
	})

	if err != nil {
		log.Printf("Warning: Failed to create Kafka consumer: %v", err)
		// Start a fallback goroutine that keeps the channel open but doesn't send any messages
		go consumer.retryConnection(broker)
		return consumer, nil
	}

	err = kafkaConsumer.SubscribeTopics(topics, nil)
	if err != nil {
		kafkaConsumer.Close()
		log.Printf("Warning: Failed to subscribe to topics: %v", err)
		// Handle the same way as connection error
		go consumer.retryConnection(broker)
		return consumer, nil
	}

	// Store reference to Kafka consumer
	consumer.mutex.Lock()
	consumer.consumer = kafkaConsumer
	consumer.mutex.Unlock()

	// Start consuming messages
	go consumer.consumeMessages()

	return consumer, nil
}

// InitConsumer initializes a Kafka consumer with configuration from environment or config
// and returns a channel that will receive messages from the topics
func InitConsumer(topics []string, groupID string) (chan KafkaMessage, error) {
	// Get Kafka broker from config or environment
	cfg := config.Load()
	broker := cfg.KafkaBroker

	// Allow override from environment
	if envBroker := os.Getenv("KAFKA_BROKER"); envBroker != "" {
		broker = envBroker
	}

	consumer, err := NewKafkaConsumer(broker, topics, groupID)
	if err != nil {
		return nil, err
	}

	return consumer.(*KafkaConsumer).messageChan, nil
}

// GetMessageChannel implements the Consumer interface
func (c *KafkaConsumer) GetMessageChannel() <-chan KafkaMessage {
	return c.messageChan
}

// Close implements the Consumer interface
func (c *KafkaConsumer) Close() {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	if !c.closed {
		c.closed = true

		// Close the underlying Kafka consumer if it exists
		if c.consumer != nil {
			c.consumer.Close()
		}

		// We intentionally don't close the message channel
		// as other goroutines might still be reading from it
		// The channel will be garbage collected when no references remain
	}
}

// retryConnection attempts to reconnect to Kafka
func (c *KafkaConsumer) retryConnection(broker string) {
	for retries := 0; retries < 5; retries++ {
		time.Sleep(10 * time.Second)
		log.Printf("Retrying Kafka connection (attempt %d/5)...", retries+1)

		c.mutex.RLock()
		isClosed := c.closed
		c.mutex.RUnlock()

		if isClosed {
			return // Don't retry if consumer has been closed
		}

		retryConsumer, retryErr := kafka.NewConsumer(&kafka.ConfigMap{
			"bootstrap.servers":         broker,
			"group.id":                  c.groupID,
			"auto.offset.reset":         "earliest",
			"broker.address.family":     "v4", 
		})

		if retryErr == nil {
			if retryConsumer.SubscribeTopics(c.topics, nil) == nil {
				log.Println("Successfully reconnected to Kafka")

				c.mutex.Lock()
				c.consumer = retryConsumer
				c.mutex.Unlock()

				// Start consuming messages
				go c.consumeMessages()
				return
			}
			retryConsumer.Close()
		}
	}
	log.Println("Failed to reconnect to Kafka after 5 attempts, no messages will be consumed")
}

// consumeMessages reads messages from Kafka and forwards them to the channel
func (c *KafkaConsumer) consumeMessages() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Recovered from panic in Kafka consumer: %v", r)
		}
	}()

	c.mutex.RLock()
	kafkaConsumer := c.consumer
	c.mutex.RUnlock()

	if kafkaConsumer == nil {
		log.Println("Cannot consume messages: Kafka consumer is nil")
		return
	}

	// Continuously read messages
	for {
		c.mutex.RLock()
		isClosed := c.closed
		kafkaConsumer = c.consumer
		c.mutex.RUnlock()

		if isClosed || kafkaConsumer == nil {
			return
		}

		msg, err := kafkaConsumer.ReadMessage(-1)
		if err != nil {
			kafkaErr, ok := err.(kafka.Error)
			if ok && kafkaErr.Code() == kafka.ErrAllBrokersDown {
				log.Printf("All Kafka brokers are down, stopping consumer")
				return
			}
			// Log other errors but continue trying
			log.Printf("Error reading message: %v", err)
			time.Sleep(1 * time.Second) // Avoid tight loop on repeated errors
			continue
		}

		// Skip messages with empty keys or values
		if msg.Key == nil || msg.Value == nil || msg.TopicPartition.Topic == nil {
			continue
		}

		// Send message to channel
		select {
		case c.messageChan <- KafkaMessage{
			Topic: *msg.TopicPartition.Topic,
			Key:   string(msg.Key),
			Value: string(msg.Value),
		}:
			// Message sent successfully
		case <-time.After(100 * time.Millisecond):
			// Channel is blocked, log warning but continue
			log.Printf("Warning: Message channel is blocked, discarding message")
		}
	}
}

// CloseAllConsumers closes all active Kafka consumers
func CloseAllConsumers() {
	consumerMutex.Lock()
	defer consumerMutex.Unlock()

	for key, consumer := range consumers {
		log.Printf("Closing Kafka consumer: %s", key)
		consumer.Close()
	}

	// Clear the map
	consumers = make(map[string]*KafkaConsumer)
}
