package broker

import (
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"github.com/thinkstack/config"
)

var (
	producer          *kafka.Producer
	producerAvailable bool = false
	producerMutex     sync.RWMutex
)

func InitProducer() error {
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

	log.Printf("Attempting to connect to Kafka broker at: %s", broker)

	// Create the Kafka producer with client ID for better traceability
	var err error
	producer, err = kafka.NewProducer(&kafka.ConfigMap{
		"bootstrap.servers":  broker,
		"socket.timeout.ms":  10000,
		"client.id":          "thinkstack-producer-main",
		"message.timeout.ms": 30000,
		"retries":            5,
		"retry.backoff.ms":   1000,
	})

	if err != nil {
		producerMutex.Lock()
		producerAvailable = false
		producerMutex.Unlock()
		SetKafkaEnabled(false)

		// Start a background task to retry connection
		go retryProducerConnection(broker)

		return fmt.Errorf("failed to create Kafka producer: %v", err)
	}

	// Start event handler
	go handleProducerEvents()

	producerMutex.Lock()
	producerAvailable = true
	producerMutex.Unlock()
	SetKafkaEnabled(true)
	log.Println("Kafka producer initialized successfully")
	return nil
}

// Try to reconnect in the background
func retryProducerConnection(broker string) {
	for retries := 0; retries < 5; retries++ {
		time.Sleep(10 * time.Second)
		log.Printf("Retrying Kafka producer connection (attempt %d/5)...", retries+1)

		p, err := kafka.NewProducer(&kafka.ConfigMap{
			"bootstrap.servers": broker,
			"socket.timeout.ms": 10000,
			"client.id":         "thinkstack-producer-retry",
		})

		if err == nil {
			producerMutex.Lock()
			producer = p
			producerAvailable = true
			producerMutex.Unlock()
			SetKafkaEnabled(true)
			log.Println("Successfully reconnected Kafka producer")
			go handleProducerEvents()
			return
		}
	}
	log.Println("Failed to reconnect Kafka producer after 5 attempts")
}

// Handle asynchronous producer events
func handleProducerEvents() {
	if producer == nil {
		return
	}

	for e := range producer.Events() {
		switch ev := e.(type) {
		case *kafka.Message:
			if ev.TopicPartition.Error != nil {
				log.Printf("Failed to deliver message: %v", ev.TopicPartition.Error)
			}
		case kafka.Error:
			log.Printf("Kafka producer error: %v", ev)
			// If the broker is down, mark producer as unavailable
			if ev.Code() == kafka.ErrAllBrokersDown {
				producerMutex.Lock()
				producerAvailable = false
				producerMutex.Unlock()
				SetKafkaEnabled(false)
			}
		}
	}
}

func PublishMessage(topic string, key string, value string) error {
	producerMutex.RLock()
	isAvailable := producerAvailable && producer != nil
	producerMutex.RUnlock()

	if !isAvailable {
		return fmt.Errorf("kafka producer is not available, message not sent")
	}

	message := &kafka.Message{
		TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
		Key:            []byte(key),
		Value:          []byte(value),
	}

	// Use delivery channel for this message
	deliveryChan := make(chan kafka.Event)

	err := producer.Produce(message, deliveryChan)
	if err != nil {
		close(deliveryChan)
		return fmt.Errorf("failed to queue message: %v", err)
	}

	// Wait for delivery report
	e := <-deliveryChan
	close(deliveryChan)

	m := e.(*kafka.Message)
	if m.TopicPartition.Error != nil {
		return fmt.Errorf("message delivery failed: %v", m.TopicPartition.Error)
	}

	log.Printf("Message delivered to topic %s [%d] at offset %v",
		*m.TopicPartition.Topic, m.TopicPartition.Partition, m.TopicPartition.Offset)

	return nil
}

func CloseProducer() {
	producerMutex.Lock()
	defer producerMutex.Unlock()

	if producer != nil {
		// Wait for messages to be delivered
		producer.Flush(5000)
		producer.Close()
		producer = nil
		producerAvailable = false
	}
}

func IsProducerAvailable() bool {
	producerMutex.RLock()
	defer producerMutex.RUnlock()
	return producerAvailable
}
