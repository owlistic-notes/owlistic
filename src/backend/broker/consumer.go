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

// Global variables for consumer management
var (
	consumers     map[string]*kafka.Consumer   = make(map[string]*kafka.Consumer)
	messageChans  map[string]chan KafkaMessage = make(map[string]chan KafkaMessage)
	consumerMutex sync.RWMutex
)

// InitConsumer initializes a Kafka consumer for the specified topics and group ID
// Returns a channel that will receive messages from the topics
func InitConsumer(topics []string, groupID string) (chan KafkaMessage, error) {
	consumerKey := groupID + ":" + topics[0] // Use first topic as part of the key

	consumerMutex.RLock()
	if ch, exists := messageChans[consumerKey]; exists {
		consumerMutex.RUnlock()
		log.Printf("Reusing existing Kafka consumer for group %s", groupID)
		return ch, nil
	}
	consumerMutex.RUnlock()

	// Get Kafka broker from config or environment
	cfg := config.Load()
	broker := cfg.KafkaBroker

	// Allow override from environment
	if envBroker := os.Getenv("KAFKA_BROKER"); envBroker != "" {
		broker = envBroker
	}

	// Use localhost as fallback if not specified
	if broker == "" {
		broker = "localhost:9092"
	}

	// Log the actual broker address we're trying to connect to
	log.Printf("Kafka consumer connecting to broker: %s for topics: %v with group: %s", broker, topics, groupID)

	// Create a buffered channel for messages
	messageChan := make(chan KafkaMessage, 100)

	// Store reference to channel immediately so we can return it even on error
	consumerMutex.Lock()
	messageChans[consumerKey] = messageChan
	consumerMutex.Unlock()

	// Create consumer with robust configuration
	consumer, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers":       broker,
		"group.id":                groupID,
		"auto.offset.reset":       "earliest",
		"socket.timeout.ms":       10000,
		"session.timeout.ms":      30000,
		"max.poll.interval.ms":    300000,
		"enable.auto.commit":      true,
		"auto.commit.interval.ms": 5000,
		"enable.partition.eof":    false,
		"client.id":               "thinkstack-consumer-" + groupID,
	})

	if err != nil {
		log.Printf("Warning: Failed to create Kafka consumer: %v", err)
		// Start a fallback goroutine that keeps the channel open but doesn't send any messages
		go func() {
			log.Println("Using fallback consumer (will retry connection)")
			// Try to reconnect periodically
			for retries := 0; retries < 5; retries++ {
				time.Sleep(10 * time.Second)
				log.Printf("Retrying Kafka connection (attempt %d/5)...", retries+1)

				retryConsumer, retryErr := kafka.NewConsumer(&kafka.ConfigMap{
					"bootstrap.servers": broker,
					"group.id":          groupID,
					"auto.offset.reset": "earliest",
				})

				if retryErr == nil {
					if retryConsumer.SubscribeTopics(topics, nil) == nil {
						log.Println("Successfully reconnected to Kafka")
						// Store reference to new consumer
						consumerMutex.Lock()
						consumers[consumerKey] = retryConsumer
						consumerMutex.Unlock()

						// Start consuming messages
						go realConsumeMessages(consumerKey, retryConsumer, messageChan)
						return
					}
					retryConsumer.Close()
				}
			}
			log.Println("Failed to reconnect to Kafka after 5 attempts, no messages will be consumed")
			// Keep channel open but don't send any messages
			select {} // Block forever
		}()

		return messageChan, nil
	}

	err = consumer.SubscribeTopics(topics, nil)
	if err != nil {
		consumer.Close()
		log.Printf("Warning: Failed to subscribe to topics: %v", err)
		// Handle the same way as connection error
		go func() {
			log.Println("Using fallback consumer due to topic subscription failure")
			// Keep channel open but don't send messages
			select {}
		}()
		return messageChan, nil
	}

	// Store reference to consumer
	consumerMutex.Lock()
	consumers[consumerKey] = consumer
	consumerMutex.Unlock()

	// Start consuming messages
	go realConsumeMessages(consumerKey, consumer, messageChan)

	return messageChan, nil
}

// realConsumeMessages reads messages from Kafka and forwards them to the channel
func realConsumeMessages(consumerKey string, consumer *kafka.Consumer, messageChan chan KafkaMessage) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Recovered from panic in Kafka consumer: %v", r)
		}

		// This is important: when this goroutine exits, clean up the consumer
		consumerMutex.Lock()
		delete(consumers, consumerKey)
		consumerMutex.Unlock()

		consumer.Close()
		// Don't close the channel as it might be used by other goroutines
		log.Printf("Kafka consumer for key %s stopped", consumerKey)
	}()

	// Continuously read messages
	for {
		msg, err := consumer.ReadMessage(-1)
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
		case messageChan <- KafkaMessage{
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

	// Clear the maps
	consumers = make(map[string]*kafka.Consumer)
	// Don't close channels as they might be used by other goroutines
}
