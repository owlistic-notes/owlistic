package main

import (
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"daviderutigliano/owlistic/broker"
	"daviderutigliano/owlistic/config"
	"daviderutigliano/owlistic/database"
	"daviderutigliano/owlistic/middleware"
	"daviderutigliano/owlistic/routes"
	"daviderutigliano/owlistic/services"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.Load()

	db, err := database.Setup(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// Initialize Kafka producer - fail if not available
	err = broker.InitProducer()
	if err != nil {
		log.Fatalf("Failed to initialize Kafka producer: %v", err)
	}
	defer broker.CloseProducer()

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
		broker.UserEventsTopic,
		broker.NotebookEventsTopic,
		broker.NoteEventsTopic,
		broker.BlockEventsTopic,
		broker.TaskEventsTopic,
		broker.NotificationTopic,
	}
	webSocketService := services.NewWebSocketService(db, kafkaTopics)
	webSocketService.SetJWTSecret([]byte(cfg.JWTSecret))
	services.WebSocketServiceInstance = webSocketService

	// Initialize BlockTaskSyncHandler service with the database
	syncHandler := services.NewSyncHandlerService(db)

	// Start event-based services
	log.Println("Starting event handler service...")
	eventHandlerService.Start()
	defer eventHandlerService.Stop()

	log.Println("Starting WebSocket service...")
	webSocketService.Start()
	defer webSocketService.Stop()

	// Start block-task sync handler
	log.Println("Starting Block-Task Sync Handler...")
	syncHandler.Start()
	defer syncHandler.Stop()

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
	publicGroup := router.Group("/api/v1")
	
	// Register public routes (no auth required)
	routes.RegisterAuthRoutes(publicGroup, db, authService)
	routes.RegisterPublicUserRoutes(publicGroup, db, userService, authService)

	// Create protected API group with auth middleware
	protectedGroup := router.Group("/api/v1")
	protectedGroup.Use(middleware.AuthMiddleware(authService))

	// Register protected API routes using the API group
	routes.RegisterProtectedUserRoutes(publicGroup, db, userService, authService)
	routes.RegisterNoteRoutes(protectedGroup, db, services.NoteServiceInstance)
	routes.RegisterTaskRoutes(protectedGroup, db, services.TaskServiceInstance)
	routes.RegisterNotebookRoutes(protectedGroup, db, services.NotebookServiceInstance)
	routes.RegisterBlockRoutes(protectedGroup, db, services.BlockServiceInstance)
	routes.RegisterTrashRoutes(protectedGroup, db, services.TrashServiceInstance)
	routes.RegisterRoleRoutes(protectedGroup, db, services.RoleServiceInstance)

	// Register WebSocket routes with consistent auth middleware
	wsGroup := router.Group("/ws")
	wsGroup.Use(middleware.AuthMiddleware(authService))
	routes.RegisterWebSocketRoutes(wsGroup, webSocketService)

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
