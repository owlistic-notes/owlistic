package broker

import (
	"context"
	"log"

	"github.com/confluentinc/confluent-kafka-go/v2/kafka"
	"github.com/thinkstack/config"
)

const (
	UserEventsTopic     = "user_events"
	NotebookEventsTopic = "notebook_events"
	NoteEventsTopic     = "note_events"
	BlockEventsTopic    = "block_events"
	TaskEventsTopic     = "task_events"
	NotificationTopic   = "notification_events"
)

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
		{Topic: NotebookEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: NoteEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: BlockEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: TaskEventsTopic, NumPartitions: 1, ReplicationFactor: 1},
		{Topic: NotificationTopic, NumPartitions: 1, ReplicationFactor: 1},
	}

	results, err := adminClient.CreateTopics(context.TODO(), topics)
	if err != nil {
		log.Fatalf("Failed to create topics: %v", err)
	}

	for _, result := range results {
		// Ignore if topic already exists
		if result.Error.Code() != kafka.ErrNoError &&
			result.Error.Code() != kafka.ErrTopicAlreadyExists {
			log.Printf("Failed to create topic %s: %v", result.Topic, result.Error)
		} else {
			log.Printf("Topic %s created successfully", result.Topic)
		}
	}
}
