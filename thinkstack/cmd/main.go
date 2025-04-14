package main

import (
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/thinkstack/config"
	"github.com/thinkstack/database"
	"github.com/thinkstack/routes"
	"github.com/thinkstack/services"
	"github.com/thinkstack/broker"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg := config.Load()

	db, err := database.Setup(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer db.Close()

	broker.InitProducer()
	defer broker.CloseProducer()

	go broker.StartNotificationConsumer(db)
	go broker.StartSyncConsumer(db)

	router := gin.Default()

	routes.RegisterUserRoutes(router, db, services.UserServiceInstance)
	routes.RegisterNoteRoutes(router, db, services.NoteServiceInstance)
	routes.RegisterTaskRoutes(router, db, services.TaskServiceInstance)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-quit
		log.Println("Shutting down server...")
		os.Exit(0)
	}()

	log.Println("Server is running on port 5000")
	if err := http.ListenAndServe(":5000", router); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
