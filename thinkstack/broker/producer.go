package broker

import (
	"log"

	"github.com/confluentinc/confluent-kafka-go/kafka"
	"github.com/thinkstack/config"
)

var producer *kafka.Producer

func InitProducer() {
	cfg := config.Load()
	var err error
	producer, err = kafka.NewProducer(&kafka.ConfigMap{
		"bootstrap.servers": cfg.KafkaBroker,
	})
	if err != nil {
		log.Fatalf("Failed to create Kafka producer: %v", err)
	}
	log.Println("Kafka producer initialized")
}

func PublishMessage(topic string, key string, value string) {
	if producer == nil {
		log.Println("Kafka producer is not initialized")
		return
	}

	message := &kafka.Message{
		TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
		Key:            []byte(key),
		Value:          []byte(value),
	}

	err := producer.Produce(message, nil)
	if err != nil {
		log.Printf("Failed to publish message to Kafka: %v", err)
	} else {
		log.Printf("Published message to topic %s: %s", topic, value)
	}
}

func CloseProducer() {
	if producer != nil {
		producer.Close()
	}
}
