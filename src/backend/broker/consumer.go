package broker

import (
	"fmt"
	"log"
	"os"
	"sync"

	"owlistic-notes/owlistic/config"

	"github.com/nats-io/nats.go"
)

// Message represents a message received
type Message *nats.Msg

// Consumer defines the interface for message consumption
type Consumer interface {
	// GetMessageChannel returns the channel that will receive messages
	GetMessageChannel() chan *nats.Msg
	// Close stops the consumer and releases resources
	Close()
}

// NatsConsumer implements the Consumer interface
type NatsConsumer struct {
	nc      *nats.Conn
	js      nats.JetStreamContext
	subs    []*nats.Subscription
	msgChan chan *nats.Msg
	mutex   sync.RWMutex
	closed  bool
}

// Global variables for consumer management
var (
	consumers     map[string]*NatsConsumer = make(map[string]*NatsConsumer)
	consumerMutex sync.RWMutex
)

// NewNatsConsumer creates a new NatsConsumer for the specified topics and group ID
func NewNatsConsumer(natsServerAddress string, topics []string, groupID string) (Consumer, error) {
	if natsServerAddress == "" {
		natsServerAddress = nats.DefaultURL
	}

	log.Printf("Connecting to NATS server at: %s", natsServerAddress)

	nc, err := nats.Connect(
		natsServerAddress,
		nats.Name("owlistic-producer-" + groupID ),
		nats.MaxReconnects(5),
	)
	if err != nil {
		log.Printf("Failed to connect to NATS: %v", err)
		return nil, err
	}

	js, err := nc.JetStream()
	if err != nil {
		log.Printf("Failed to open NATS stream: %v", err)
		return nil, err
	}

	consumerMutex.RLock()
	if c, exists := consumers[groupID]; exists {
		consumerMutex.RUnlock()
		log.Printf("Reusing existing consumer for group %s", groupID)
		return c, nil
	}
	consumerMutex.RUnlock()
	
	log.Printf("Creating NATS consumer %s on topics %v", groupID, topics)
	
	consumer := &NatsConsumer{
		nc:     nc,
		js:     js,
		closed: false,
		msgChan: make(chan *nats.Msg, 8192),
	}

	for _, subject := range topics {
		sub, err := js.ChanSubscribe(subject, consumer.msgChan)
		if err != nil {
			return nil, fmt.Errorf("failed to subscribe to topic %s: %v", subject, err)
		}
		consumer.subs = append(consumer.subs, sub)
	}

	consumerMutex.Lock()
	consumers[groupID] = consumer
	consumerMutex.Unlock()

	return consumer, nil
}

// InitConsumer initializes an event consumer with configuration from environment or config
// and returns a channel that will receive messages from the topics
func InitConsumer(cfg config.Config, topics []string, groupID string) (Consumer, error) {
	// Get broker from config or environment
	broker := cfg.EventBroker

	// Allow override from environment
	if envBroker := os.Getenv("BROKER_ADDRESS"); envBroker != "" {
		broker = envBroker
	}

	consumer, err := NewNatsConsumer(broker, topics, groupID)
	if err != nil {
		return nil, err
	}

	return consumer, nil
}

// GetMessageChannel implements the Consumer interface
func (c *NatsConsumer) GetMessageChannel() chan *nats.Msg {
	return c.msgChan
}

// Close implements the Consumer interface
func (c *NatsConsumer) Close() {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	if !c.closed {
		c.closed = true

		// Close the underlying connection if it exists
		if c.nc != nil {
			c.nc.Close()
		}

		// We intentionally don't close the message channel
		// as other goroutines might still be reading from it
		// The channel will be garbage collected when no references remain
	}
}

// CloseAllConsumers closes all active consumers
func CloseAllConsumers() {
	consumerMutex.Lock()
	defer consumerMutex.Unlock()

	for key, consumer := range consumers {
		log.Printf("Closing consumer: %s", key)
		consumer.Close()
	}

	// Clear the map
	consumers = make(map[string]*NatsConsumer)
}
