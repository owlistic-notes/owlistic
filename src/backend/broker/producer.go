package broker

import (
	"fmt"
	"log"
	"os"
	"sync"

	"owlistic-notes/owlistic/config"

	// "github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/nats-io/nats.go"
)

type NatsDeliveryChan struct {
	Ack *nats.PubAck
	Err error
}

// Producer defines the interface for message production
type Producer interface {
	PublishMessage(topic string, value string) error
	CreateTopics(string, []string) error
	Close()
	IsAvailable() bool
}

// NatsProducer is the concrete implementation of the Producer interface
type NatsProducer struct {
	nc        *nats.Conn
	js        nats.JetStreamContext
	mutex     sync.RWMutex
	available bool
}

func (p *NatsProducer) PublishAsync(subject string, data []byte) (nats.PubAckFuture, error) {
	msg := &nats.Msg{
		Subject: subject,
		Data:    data,
	}

	future, err := p.js.PublishMsgAsync(msg)
	if err != nil {
		return nil, fmt.Errorf("failed to queue message: %w", err)
	}

	return future, nil
}

func (p *NatsProducer) CreateTopics(streamName string, topics []string) error {
	_, err := p.js.StreamInfo(streamName)
	if err != nil {
		_, err = p.js.AddStream(&nats.StreamConfig{
			Name:     streamName,
			Subjects: topics,
			Storage:  nats.FileStorage,
			Retention: nats.LimitsPolicy,
		})
		if err != nil {
			log.Printf("Failed to create stream: %v", err)
			return err
		}
	}
	return nil
}


var (
	// DefaultProducer is the global producer instance
	DefaultProducer Producer
	producerMutex   sync.RWMutex
)

// NewNATSProducer creates a new NATSProducer instance
func NewNATSProducer(natsServerAddress string) (Producer, error) {
	// Use localhost as fallback if not specified
	if natsServerAddress == "" {
		natsServerAddress = nats.DefaultURL
	}

	log.Printf("Connecting to NATS server at: %s", natsServerAddress)

	// Create the NATS natsServer
	nc, err := nats.Connect(
		natsServerAddress,
		nats.Name("owlistic-consumer"), // Set client ID for better traceability
		nats.MaxReconnects(5),
	)

	if err != nil {
		return nil, fmt.Errorf(
			"failed to establish connection to NATS server %s: %v", natsServerAddress, err)
	}

	js, err := nc.JetStream()
	if err != nil {
		return nil, fmt.Errorf("failed to get JetStream context: %v", err)
	}

	// Create the NATS producer instance
	producer := &NatsProducer{
		js:        js,
		nc:        nc,
		available: true,
	}

	log.Println("event producer initialized successfully")
	return producer, nil
}

// InitProducer initializes the default global producer instance
func InitProducer() error {
	cfg := config.Load()
	broker := cfg.EventBroker


	// Allow override from environment
	if envBroker := os.Getenv("BROKER_ADDRESS"); envBroker != "" {
		broker = envBroker
	}

	var err error
	producerMutex.Lock()
	DefaultProducer, err = NewNATSProducer(broker)
	producerMutex.Unlock()

	DefaultProducer.CreateTopics("owlistic", StreamNames)

	return err
}

// PublishMessage implements the Producer interface for NATSProducer
func (producer *NatsProducer) PublishMessage(topic string, value string) error {
	producer.mutex.RLock()
	isAvailable := producer.available && producer.nc != nil
	producer.mutex.RUnlock()

	if !isAvailable {
		return fmt.Errorf("event producer is not available, message not sent")
	}

	// Use delivery channel for this message
	deliveryChan := make(chan NatsDeliveryChan)

	producer.PublishAsync(topic, []byte(value))

	// Wait for delivery report
	msg := <-deliveryChan
	close(deliveryChan)

	if msg.Err == nil {
		return fmt.Errorf("message delivery failed: %v", msg.Err)
	}

	log.Printf("Message delivered to topic %s [%d] at offset %v",
		msg.Ack.Domain, msg.Ack.Sequence, msg.Ack.Stream)

	return nil
}

// Close implements the Producer interface
func (p *NatsProducer) Close() {
	p.mutex.Lock()
	defer p.mutex.Unlock()

	if p.js != nil {
		p.js.PublishAsyncComplete()
		p.js = nil
	}

	if p.nc != nil {
		p.nc.Flush()
		p.nc.Close()
		p.nc = nil
		p.available = false
	}
}

// IsAvailable implements the Producer interface
func (p *NatsProducer) IsAvailable() bool {
	p.mutex.RLock()
	defer p.mutex.RUnlock()
	return p.available
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
