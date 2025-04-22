package services

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/thinkstack/broker"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

type WebSocketServiceInterface interface {
	Start()
	Stop()
	HandleConnection(c *gin.Context)
	BroadcastEvent(event *models.StandardMessage)
}

type WebSocketService struct {
	db          *database.Database
	connections map[string]*websocketConnection
	connMutex   sync.RWMutex
	isRunning   bool
	messageChan chan broker.KafkaMessage
	authService AuthServiceInterface
	kafkaTopics []string
}

type websocketConnection struct {
	conn      *websocket.Conn
	userID    uuid.UUID
	send      chan []byte
	createdAt time.Time
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for development, restrict in production
	},
}

func NewWebSocketService(db *database.Database, kafkaTopics []string) WebSocketServiceInterface {
	return &WebSocketService{
		db:          db,
		connections: make(map[string]*websocketConnection),
		isRunning:   false,
		kafkaTopics: kafkaTopics,
	}
}

// SetAuthService sets the authentication service to be used for validating tokens
func (s *WebSocketService) SetAuthService(authService AuthServiceInterface) {
	s.authService = authService
}

func (s *WebSocketService) Start() {
	if s.isRunning {
		return
	}
	s.isRunning = true

	// Initialize Kafka consumer for all relevant topics
	var err error
	messageChan, err := broker.InitConsumer(s.kafkaTopics, "websocket-service")
	if err != nil {
		log.Printf("Failed to initialize Kafka consumer: %v", err)
		return
	}
	s.messageChan = messageChan

	// Start listening for Kafka messages
	go s.consumeMessages()
}

func (s *WebSocketService) Stop() {
	s.isRunning = false
	// Close all websocket connections
	s.connMutex.Lock()
	for connID, conn := range s.connections {
		conn.conn.Close()
		delete(s.connections, connID)
	}
	s.connMutex.Unlock()
}

// HandleConnection handles a new WebSocket connection with JWT authentication
func (s *WebSocketService) HandleConnection(c *gin.Context) {
	// Get authenticated user from context (set by WebSocketAuthMiddleware)
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Not authenticated"})
		return
	}

	userID, ok := userIDInterface.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
		return
	}

	// Upgrade HTTP connection to WebSocket
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("Failed to upgrade connection: %v", err)
		return
	}

	// Create a unique connection ID
	connID := uuid.New().String()

	// Create websocket connection object
	wsConn := &websocketConnection{
		conn:      conn,
		userID:    userID,
		send:      make(chan []byte, 256),
		createdAt: time.Now(),
	}

	// Register the connection
	s.connMutex.Lock()
	s.connections[connID] = wsConn
	s.connMutex.Unlock()

	log.Printf("New WebSocket connection established: %s for user: %s", connID, userID)

	// Handle the connection (read/write routines)
	go s.readPump(connID, wsConn)
	go s.writePump(connID, wsConn)

	// Send a welcome message
	welcome := models.NewStandardMessage(models.EventMessage, "connected", map[string]interface{}{
		"message": "Connected to ThinkStack WebSocket server",
		"user_id": userID.String(),
		"time":    time.Now(),
	})

	msgBytes, _ := json.Marshal(welcome)
	wsConn.send <- msgBytes
}

// consumeMessages processes messages from Kafka and dispatches them to clients
func (s *WebSocketService) consumeMessages() {
	for message := range s.messageChan {
		// Parse the Kafka message
		var event models.StandardMessage
		if err := json.Unmarshal([]byte(message.Value), &event); err != nil {
			log.Printf("Error unmarshalling event: %v", err)
			continue
		}

		// Broadcast the event to all connected clients
		s.BroadcastEvent(&event)
	}
}

func (s *WebSocketService) readPump(connID string, wsConn *websocketConnection) {
	defer func() {
		s.connMutex.Lock()
		delete(s.connections, connID)
		s.connMutex.Unlock()
		wsConn.conn.Close()
		close(wsConn.send)
		log.Printf("WebSocket connection closed: %s", connID)
	}()

	wsConn.conn.SetReadLimit(512) // Limit message size
	wsConn.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	wsConn.conn.SetPongHandler(func(string) error {
		wsConn.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, message, err := wsConn.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Error reading message: %v", err)
			}
			break
		}

		var clientMsg models.StandardMessage
		if err := json.Unmarshal(message, &clientMsg); err != nil {
			log.Printf("Error unmarshalling client message: %v", err)
			continue
		}

		// Handle message based on type
		switch clientMsg.Type {
		case models.SubscribeMessage:
			// Handle subscription requests
			log.Printf("Subscription request from user %s: %v", wsConn.userID, clientMsg)
			// Future implementation for topic-specific subscriptions
		default:
			log.Printf("Received message from user %s: %v", wsConn.userID, clientMsg)
		}
	}
}

func (s *WebSocketService) writePump(connID string, wsConn *websocketConnection) {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		wsConn.conn.Close()
	}()

	for {
		select {
		case message, ok := <-wsConn.send:
			wsConn.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				// Channel was closed
				wsConn.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := wsConn.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Add queued messages to the current websocket message
			n := len(wsConn.send)
			for i := 0; i < n; i++ {
				w.Write([]byte("\n"))
				w.Write(<-wsConn.send)
			}

			if err := w.Close(); err != nil {
				return
			}
		case <-ticker.C:
			wsConn.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := wsConn.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// BroadcastEvent sends an event to all connected clients that should receive it
func (s *WebSocketService) BroadcastEvent(event *models.StandardMessage) {
	// Prepare the message once
	msgBytes, err := json.Marshal(event)
	if err != nil {
		log.Printf("Error marshalling event: %v", err)
		return
	}

	s.connMutex.RLock()
	defer s.connMutex.RUnlock()

	// Send to all connected clients
	// Note: In a production system, you would filter based on permissions
	for _, conn := range s.connections {
		// Check if this user has access to the resource before sending the event
		if event.ResourceType != "" && event.ResourceID != "" {
			// Skip RBAC check for public events with no resource
			resourceUUID, err := uuid.Parse(event.ResourceID)
			if err == nil {
				hasAccess, err := RoleServiceInstance.HasAccess(
					s.db,
					conn.userID,
					resourceUUID,
					models.ResourceType(event.ResourceType),
					models.ViewerRole,
				)
				if err != nil || !hasAccess {
					// Skip this client if they don't have access
					continue
				}
			}
		}

		// Send the event
		select {
		case conn.send <- msgBytes:
			// Message sent successfully
		default:
			// Buffer full, client is likely slow or disconnected
			log.Printf("Client buffer full, dropping message")
		}
	}
}

// Global instance for the application
var WebSocketServiceInstance WebSocketServiceInterface
