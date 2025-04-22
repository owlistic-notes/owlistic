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
	"github.com/thinkstack/middleware"
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
		log.Println("The application will continue, but event publishing will be disabled")
		kafkaAvailable = false
		broker.SetKafkaEnabled(false)
	} else {
		broker.SetKafkaEnabled(true)
		defer broker.CloseProducer()
	}

	// Initialize all service instances properly with database
	// Initialize authentication service
	authService := services.NewAuthService(cfg.JWTSecret, cfg.JWTExpirationHours)
	services.AuthServiceInstance = authService

	// Initialize user service with auth service dependency
	userService := services.NewUserService(authService)
	services.UserServiceInstance = userService

	// Properly initialize other service instances with the database
	services.NoteServiceInstance = services.NewNoteService()
	services.NotebookServiceInstance = services.NewNotebookService()
	services.BlockServiceInstance = services.NewBlockService()
	services.TaskServiceInstance = services.NewTaskService()
	services.TrashServiceInstance = services.NewTrashService()

	// Initialize eventHandler service with the database
	eventHandlerService := services.NewEventHandlerService(db)
	services.EventHandlerServiceInstance = eventHandlerService

	// Initialize WebSocket service with the database
	kafkaTopics := []string{
		broker.NoteEventsTopic,
		broker.NotebookEventsTopic,
		broker.SyncEventsTopic,
		broker.BlockEventsTopic,
	}
	webSocketService := services.NewWebSocketService(db, kafkaTopics)
	services.WebSocketServiceInstance = webSocketService

	// Only start Kafka-dependent services if Kafka is available
	if kafkaAvailable {
		log.Println("Starting event handler service...")
		eventHandlerService.Start()
		defer eventHandlerService.Stop()

		log.Println("Starting WebSocket service...")
		webSocketService.Start()
		defer webSocketService.Stop()
	} else {
		log.Println("Kafka-dependent services are disabled due to Kafka unavailability")
	}

	router := gin.Default()

	// CORS middleware
	router.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")
		c.Writer.Header().Set("Access-Control-Max-Age", "3600") // Cache preflight request for 1 hour

		// Handle preflight requests
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}

		c.Next()
	})

	// Create public API groups
	authGroup := router.Group("/api/v1/auth")
	userPublicGroup := router.Group("/api/v1")

	// Register public routes (no auth required)
	routes.RegisterAuthRoutes(authGroup, db, authService)
	routes.RegisterUserRoutes(userPublicGroup, db, userService, authService)

	// Register WebSocket routes with authentication
	routes.RegisterWebSocketRoutes(router, authService, webSocketService)

	// Create protected API group with auth middleware
	apiGroup := router.Group("/api/v1")
	apiGroup.Use(middleware.AuthMiddleware(authService))

	// Enable access control middleware for RBAC
	apiGroup.Use(middleware.AccessControlMiddleware(db))

	// Register protected API routes using the API group
	routes.RegisterNoteRoutes(apiGroup, db, services.NoteServiceInstance)
	routes.RegisterTaskRoutes(apiGroup, db, services.TaskServiceInstance)
	routes.RegisterNotebookRoutes(apiGroup, db, services.NotebookServiceInstance)
	routes.RegisterBlockRoutes(apiGroup, db, services.BlockServiceInstance)
	routes.RegisterTrashRoutes(apiGroup, db, services.TrashServiceInstance)
	routes.RegisterRoleRoutes(apiGroup, db, services.RoleServiceInstance)

	// Register debug routes for monitoring events
	routes.SetupDebugRoutes(router, db)

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
