package main

import (
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/thinkstack/broker"
	"github.com/thinkstack/config"
	"github.com/thinkstack/database"
	"github.com/thinkstack/routes"
	"github.com/thinkstack/services"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.Load()

	db, err := database.Setup(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// Initialize Kafka producer with better error handling
	kafkaAvailable := true
	err = broker.InitProducer()
	if err != nil {
		log.Printf("Warning: Failed to initialize Kafka producer: %v", err)
		log.Println("The application will continue, but some Kafka-dependent features will be disabled")
		kafkaAvailable = false
	} else {
		defer broker.CloseProducer()
	}

	// Initialize WebSocket service
	kafkaTopics := []string{
		broker.NoteEventsTopic,
		broker.NotebookEventsTopic,
		broker.SyncEventsTopic,
		broker.BlockEventsTopic,
	}

	// Create and initialize the WebSocket service
	webSocketService := services.NewWebSocketService(db, kafkaTopics)
	services.WebSocketServiceInstance = webSocketService
	webSocketService.Start() // This runs in a goroutine
	defer webSocketService.Stop()

	// Only initialize Kafka-dependent services if Kafka is available
	if kafkaAvailable {
		// Initialize eventHandler service
		eventHandlerService := services.NewEventHandlerService(db)
		services.EventHandlerServiceInstance = eventHandlerService
		eventHandlerService.Start()
		defer eventHandlerService.Stop()
	} else {
		log.Println("EventHandler service is disabled due to Kafka unavailability")
	}

	// Initialize authentication service
	authService := services.NewAuthService(cfg.JWTSecret, cfg.JWTExpirationHours)
	services.AuthServiceInstance = authService

	// Initialize user service with auth service dependency
	userService := services.NewUserService(authService)
	services.UserServiceInstance = userService

	router := gin.Default()

	// Register authentication routes
	routes.RegisterAuthRoutes(router, db, authService)

	// Register user routes with auth service
	routes.RegisterUserRoutes(router, db, userService, authService)

	// Register other service routes
	routes.RegisterNoteRoutes(router, db, services.NoteServiceInstance)
	routes.RegisterTaskRoutes(router, db, services.TaskServiceInstance)
	routes.RegisterNotebookRoutes(router, db, services.NotebookServiceInstance)
	routes.RegisterBlockRoutes(router, db, services.BlockServiceInstance)
	routes.RegisterTrashRoutes(router, db, services.TrashServiceInstance)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-quit
		log.Println("Shutting down server...")
		// Explicitly close Kafka consumers before exiting
		broker.CloseAllConsumers()
		os.Exit(0)
	}()

	log.Println("API server is running on port 8080")
	if err := http.ListenAndServe(":8080", router); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
