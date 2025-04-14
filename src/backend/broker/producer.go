package broker

import (
	"context"
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

	CreateTopics()
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

func CreateTopics() {
	cfg := config.Load()
	adminClient, err := kafka.NewAdminClient(&kafka.ConfigMap{
		"bootstrap.servers": cfg.KafkaBroker,
	})
	if err != nil {
		log.Fatalf("Failed to create Kafka admin client: %v", err)
	}
	defer adminClient.Close()

	topics := []kafka.TopicSpecification{
		{Topic: UserEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: NoteEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: TaskEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: SyncEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: NotificationTopic, NumPartitions: 1, ReplicationFactor: 1},
	}

	results, err := adminClient.CreateTopics(context.TODO(), topics)
	if err != nil {
		log.Fatalf("Failed to create topics: %v", err)
	}

	for _, result := range results {
		if result.Error.Code() != kafka.ErrNoError {
			log.Printf("Failed to create topic %s: %v", result.Topic, result.Error)
		} else {
			log.Printf("Topic %s created successfully", result.Topic)
		}
	}
}
