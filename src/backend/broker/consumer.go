package broker

import (
	"log"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"github.com/thinkstack/config"
)

func StartConsumer(topics []string, groupID string, handler func(topic string, key string, value string)) {
	cfg := config.Load()
	consumer, err := kafka.NewConsumer(&kafka.ConfigMap{
		"bootstrap.servers": cfg.KafkaBroker,
		"group.id":          groupID,
		"auto.offset.reset": "earliest",
	})
	if err != nil {
		log.Fatalf("Failed to create Kafka consumer: %v", err)
	}
	defer consumer.Close()

	err = consumer.SubscribeTopics(topics, nil)
	if err != nil {
		log.Fatalf("Failed to subscribe to topics: %v", err)
	}

	log.Printf("Kafka consumer started, listening to topics: %v", topics)

	for {
		msg, err := consumer.ReadMessage(-1)
		if err != nil {
			log.Printf("Error reading message: %v", err)
			continue
		}

		log.Printf("Received message: topic=%s, key=%s, value=%s", *msg.TopicPartition.Topic, string(msg.Key), string(msg.Value))
		handler(*msg.TopicPartition.Topic, string(msg.Key), string(msg.Value))
	}
}
