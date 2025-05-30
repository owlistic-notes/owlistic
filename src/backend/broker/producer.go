package broker

import (
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"owlistic-notes/owlistic/config"

	// "github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/nats-io/nats.go"
)

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

func (p *NatsProducer) CreateTopics(streamName string, topics []string) error {
	_, err := p.js.StreamInfo(streamName)
	if err != nil {
		_, err = p.js.AddStream(&nats.StreamConfig{
			Name:      streamName,
			Subjects:  topics,
			Storage:   nats.FileStorage,
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
func InitProducer(cfg config.Config) error {
	broker := cfg.EventBroker

	// Allow override from environment
	if envBroker := os.Getenv("BROKER_ADDRESS"); envBroker != "" {
		broker = envBroker
	}

	var err error
	producerMutex.Lock()
	DefaultProducer, err = NewNATSProducer(broker)
	producerMutex.Unlock()

	DefaultProducer.CreateTopics("owlistic", SubjectNames)

	return err
}

// PublishMessage implements the Producer interface for NATSProducer
func (p *NatsProducer) PublishMessage(topic string, value string) error {
	p.mutex.Lock()
	isAvailable := p.available && p.nc != nil
	p.mutex.Unlock()

	if !isAvailable {
		return fmt.Errorf("event producer is not available, message not sent")
	}

	msg := &nats.Msg{
		Subject: topic,
		Data:    []byte(value),
	}

	ack, err := p.js.PublishMsgAsync(msg)
	if err != nil {
		return fmt.Errorf("failed to queue message: %w", err)
	}

	// Wait for delivery report
	select {
	case <-p.js.PublishAsyncComplete():
		log.Printf("Message delivered to topic %s %v",
			ack.Msg().Subject, ack.Msg())
	case <-time.After(5 * time.Second):
		return fmt.Errorf("message delivery failed with error %v", ack.Err())
	}

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
