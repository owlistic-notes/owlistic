package config

import (
	"log"
	"os"
	"strconv"
)

type Config struct {
	AppPort            string
	EventBroker        string
	DBHost             string
	DBPort             string
	DBUser             string
	DBPassword         string
	DBName             string
	JWTSecret          string
	JWTExpirationHours int
	AppOrigins         string
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

	cfg := Config{
		AppPort:            getEnv("APP_PORT", "8080"),
		AppOrigins:         getEnv("APP_ORIGINS", "*"),
		EventBroker:        getEnv("BROKER_ADDRESS", "localhost:4222"),
		DBHost:             getEnv("DB_HOST", "localhost"),
		DBPort:             getEnv("DB_PORT", "5432"),
		DBUser:             getEnv("DB_USER", "owlistic"),
		DBPassword:         getEnv("DB_PASSWORD", "owlistic"),
		DBName:             getEnv("DB_NAME", "owlistic"),
		JWTSecret:          getEnv("JWT_SECRET", "your-super-secret-key-change-this-in-production"),
		JWTExpirationHours: getEnvAsInt("JWT_EXPIRATION_HOURS", 24),
	}
	Print(cfg)

	return cfg
}

func Print(cfg Config) {
	log.Printf("App Port: %s\n", cfg.AppPort)
	log.Printf("App Origins: %s\n", cfg.AppOrigins)
	log.Printf("Event Broker Address %s\n", cfg.EventBroker)
	log.Printf("DB Host: %s\n", cfg.DBHost)
	log.Printf("DB Port: %s\n", cfg.DBPort)
	log.Printf("DB Name: %s\n", cfg.DBName)
	log.Printf("DB User: %s\n", cfg.DBUser)
	log.Printf("DB Password: %s\n", cfg.DBPassword)
	log.Printf("JWT Secret: %s\n", cfg.JWTSecret)
	log.Printf("JWT Expiration Hours: %d\n", cfg.JWTExpirationHours)
}
