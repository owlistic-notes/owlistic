package config

import (
	"log"
	"os"
)

type Config struct {
	AppEnv      string
	KafkaBroker string
	KafkaTopic  string
	DBHost      string
	DBPort      string
	DBUser      string
	DBPassword  string
	DBName      string
	RedisHost   string
	RedisPort   string
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	log.Printf("%s not set, defaulting to %s", key, defaultValue)
	return defaultValue
}

func Load() Config {
	log.Println("Loading configuration...")

	return Config{
		AppEnv:      getEnv("APP_ENV", "development"),
		KafkaBroker: getEnv("KAFKA_BROKER", "localhost:9092"),
		KafkaTopic:  getEnv("KAFKA_TOPIC", "default-topic"),
		DBHost:      getEnv("DB_HOST", "localhost"),
		DBPort:      getEnv("DB_PORT", "5432"),
		DBUser:      getEnv("DB_USER", "thinkstack"),
		DBPassword:  getEnv("DB_PASSWORD", "thinkstack"),
		DBName:      getEnv("DB_NAME", "thinkstack"),
		RedisHost:   getEnv("REDIS_HOST", "localhost"),
		RedisPort:   getEnv("REDIS_PORT", "6379"),
	}
}
