package broker

import (
	"fmt"
	"log"
	"os"
	"sync"

	"owlistic-notes/owlistic/config"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
)

// Producer defines the interface for message production
type Producer interface {
	// PublishMessage publishes a message to the specified topic
	PublishMessage(topic string, key string, value string) error
	// Close closes the producer and frees resources
	Close()
	// IsAvailable returns whether the producer is available for sending messages
	IsAvailable() bool
}

// KafkaProducer is the concrete implementation of the Producer interface
type KafkaProducer struct {
	producer  *kafka.Producer
	mutex     sync.RWMutex
	available bool
}

var (
	// DefaultProducer is the global producer instance
	DefaultProducer Producer
	producerMutex   sync.RWMutex
)

// NewKafkaProducer creates a new KafkaProducer instance
func NewKafkaProducer(brokerAddress string) (Producer, error) {
	// Use localhost as fallback if not specified
	if brokerAddress == "" {
		brokerAddress = "localhost:9092"
	}

	log.Printf("Connecting to Kafka broker at: %s", brokerAddress)

	// Create the Kafka producer with client ID for better traceability
	producer, err := kafka.NewProducer(&kafka.ConfigMap{
		"bootstrap.servers":  brokerAddress,
		"socket.timeout.ms":  10000,
		"client.id":          "owlistic-producer-main",
		"message.timeout.ms": 30000,
		"retries":            5,
		"retry.backoff.ms":   1000,
		"security.protocol":  "plaintext",
	})

	if err != nil {
		return nil, fmt.Errorf("failed to create Kafka producer: %v", err)
	}

	kp := &KafkaProducer{
		producer:  producer,
		available: true,
	}

	// Start event handler
	go kp.handleProducerEvents()

	log.Println("Kafka producer initialized successfully")
	return kp, nil
}

// InitProducer initializes the default global producer instance
func InitProducer() error {
	cfg := config.Load()
	broker := cfg.KafkaBroker

	// Allow override from environment
	if envBroker := os.Getenv("KAFKA_BROKER"); envBroker != "" {
		broker = envBroker
	}

	var err error
	producerMutex.Lock()
	DefaultProducer, err = NewKafkaProducer(broker)
	producerMutex.Unlock()

	return err
}

// Handle asynchronous producer events
func (kp *KafkaProducer) handleProducerEvents() {
	kp.mutex.RLock()
	p := kp.producer
	kp.mutex.RUnlock()

	if p == nil {
		return
	}

	for e := range p.Events() {
		switch ev := e.(type) {
		case *kafka.Message:
			if ev.TopicPartition.Error != nil {
				log.Printf("Failed to deliver message: %v", ev.TopicPartition.Error)
			}
		case kafka.Error:
			log.Printf("Kafka producer error: %v", ev)
			// If the broker is down, mark producer as unavailable
			if ev.Code() == kafka.ErrAllBrokersDown {
				kp.mutex.Lock()
				kp.available = false
				kp.mutex.Unlock()
				log.Printf("All Kafka brokers are down")
			}
		}
	}
}

// PublishMessage implements the Producer interface for KafkaProducer
func (kp *KafkaProducer) PublishMessage(topic string, key string, value string) error {
	kp.mutex.RLock()
	isAvailable := kp.available && kp.producer != nil
	p := kp.producer
	kp.mutex.RUnlock()

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

	err := p.Produce(message, deliveryChan)
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

// Close implements the Producer interface
func (kp *KafkaProducer) Close() {
	kp.mutex.Lock()
	defer kp.mutex.Unlock()

	if kp.producer != nil {
		// Wait for messages to be delivered
		kp.producer.Flush(5000)
		kp.producer.Close()
		kp.producer = nil
		kp.available = false
	}
}

// IsAvailable implements the Producer interface
func (kp *KafkaProducer) IsAvailable() bool {
	kp.mutex.RLock()
	defer kp.mutex.RUnlock()
	return kp.available
}

// CloseProducer closes the default producer instance
func CloseProducer() {
	producerMutex.Lock()
	defer producerMutex.Unlock()

	if DefaultProducer != nil {
		DefaultProducer.Close()
		DefaultProducer = nil
	}
}

// IsProducerAvailable returns whether the default producer is available
func IsProducerAvailable() bool {
	producerMutex.RLock()
	defer producerMutex.RUnlock()

	if DefaultProducer == nil {
		return false
	}
	return DefaultProducer.IsAvailable()
}
