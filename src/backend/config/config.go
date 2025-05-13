package config

import (
	"log"
	"os"
	"strconv"
)

type Config struct {
	AppEnv             string
	AppPort            string
	KafkaBroker        string
	KafkaTopic         string
	DBHost             string
	DBPort             string
	DBUser             string
	DBPassword         string
	DBName             string
	DBMaxIdleConns     int
	DBMaxOpenConns     int
	RedisHost          string
	RedisPort          string
	JWTSecret          string
	JWTExpirationHours int
	AllowedOrigins     string
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	log.Printf("%s not set, defaulting to %s", key, defaultValue)
	return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
		log.Printf("Invalid integer value for %s, defaulting to %d", key, defaultValue)
	}
	return defaultValue
}

func Load() Config {
	log.Println("Loading configuration...")

	return Config{
		AppEnv:             getEnv("APP_ENV", "development"),
		AppPort:            getEnv("APP_PORT", "8080"),
		AllowedOrigins:     getEnv("ALLOWED_ORIGINS", "*"),
		KafkaBroker:        getEnv("KAFKA_BROKER", "localhost:9092"),
		KafkaTopic:         getEnv("KAFKA_TOPIC", "default-topic"),
		DBHost:             getEnv("DB_HOST", "localhost"),
		DBPort:             getEnv("DB_PORT", "5432"),
		DBUser:             getEnv("DB_USER", "owlistic"),
		DBPassword:         getEnv("DB_PASSWORD", "owlistic"),
		DBName:             getEnv("DB_NAME", "owlistic"),
		DBMaxIdleConns:     getEnvAsInt("DB_MAX_IDLE_CONNS", 10),
		DBMaxOpenConns:     getEnvAsInt("DB_MAX_OPEN_CONNS", 100),
		RedisHost:          getEnv("REDIS_HOST", "localhost"),
		RedisPort:          getEnv("REDIS_PORT", "6379"),
		JWTSecret:          getEnv("JWT_SECRET", "your-super-secret-key-change-this-in-production"),
		JWTExpirationHours: getEnvAsInt("JWT_EXPIRATION_HOURS", 24),
	}
}
