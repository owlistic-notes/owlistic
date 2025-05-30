package broker

import (
	"encoding/json"
	"log"
	"os"
	"sync"
	"time"

	"owlistic-notes/owlistic/config"

	// "github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/nats-io/nats.go"
)

// Message represents a message received
type Message nats.Msg

// Consumer defines the interface for message consumption
type Consumer interface {
	// GetMessageChannel returns the channel that will receive messages
	GetMessageChannel() <-chan Message
	// Close stops the consumer and releases resources
	Close()
}

// NatsConsumer implements the Consumer interface
type NatsConsumer struct {
	nc      *nats.Conn
	js      nats.JetStreamContext
	subs    []*nats.Subscription
	msgChan chan Message
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
	consumerKey := groupID + ":" + topics[0] // Use first topic as part of the key

	consumerMutex.RLock()
	if c, exists := consumers[consumerKey]; exists {
		consumerMutex.RUnlock()
		log.Printf("Reusing existing consumer for group %s", groupID)
		return c, nil
	}
	consumerMutex.RUnlock()

	if natsServerAddress == "" {
		natsServerAddress = nats.DefaultURL
	}

	nc, err := nats.Connect(
		natsServerAddress,
		nats.Name("owlistic-producer"), // Set client ID for better traceability
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

	consumer := &NatsConsumer{
		nc:     nc,
		js:     js,
		closed: false,
		msgChan: make(chan Message, 100),
	}

	for _, subject := range topics {
		sub, err := js.Subscribe(subject, func(msg *nats.Msg) {
			var payload struct {
				Event   string `json:"event"`
				Data 	string `json:"data"`
			}

			if err := json.Unmarshal(msg.Data, &payload); err != nil {
				log.Printf("Failed to decode message on subject %s: %v", msg.Subject, err)
				_ = msg.Term()
				return
			}

			select {
			case consumer.msgChan <- Message{
				Subject: msg.Subject,
				Header: nats.Header(map[string][]string{"event": {payload.Event}}),
				Data: []byte(payload.Data),
			}:
				_ = msg.Ack()
			case <-time.After(100 * time.Millisecond):
				log.Printf("Message channel is blocked, discarding NATS message")
				_ = msg.Nak()
			}
		}, nats.ManualAck(), nats.AckWait(30*time.Second))
		if err != nil {
			nc.Close()
			log.Printf("Failed to subscribe to subject '%s': %v", subject, err)
			return nil, err
		}

		consumer.subs = append(consumer.subs, sub)
	}

			
	consumerMutex.RLock()
	consumers[consumerKey] = consumer
	consumerMutex.RUnlock()

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

	return consumer.(*NatsConsumer).msgChan, nil
}

// GetMessageChannel implements the Consumer interface
func (c *NatsConsumer) GetMessageChannel() <-chan Message {
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
