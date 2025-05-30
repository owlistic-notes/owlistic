package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/config"
	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/middleware"
	"owlistic-notes/owlistic/routes"
	"owlistic-notes/owlistic/services"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.Load()

	db, err := database.Setup(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	// Initialize producer
	err = broker.InitProducer()
	if err != nil {
		log.Fatalf("Failed to initialize producer: %v", err)
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

	webSocketService := services.NewWebSocketService(db)
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
	router.Use(middleware.CORSMiddleware(cfg.AppOrigins))

	// Create public API groups
	publicGroup := router.Group("/api/v1")

	// Register public routes (no auth required)
	routes.RegisterAuthRoutes(publicGroup, db, authService)
	routes.RegisterPublicUserRoutes(publicGroup, db, userService, authService)

	// Create protected API group with auth middleware
	protectedGroup := router.Group("/api/v1")
	protectedGroup.Use(middleware.AuthMiddleware(authService))

	// Register protected API routes using the API group
	routes.RegisterProtectedUserRoutes(protectedGroup, db, userService, authService)
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
		// Explicitly close consumers before exiting
		broker.CloseAllConsumers()
		os.Exit(0)
	}()

	log.Println("API server is running on port", cfg.AppPort)
	if err := http.ListenAndServe(fmt.Sprintf(":%v", cfg.AppPort), router); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
