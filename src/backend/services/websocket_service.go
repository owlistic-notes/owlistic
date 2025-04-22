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
	"github.com/thinkstack/utils/token"
)

type WebSocketServiceInterface interface {
	Start()
	Stop()
	HandleConnection(c *gin.Context)
	BroadcastEvent(event *models.StandardMessage)
	SetJWTSecret(secret []byte)
}

type WebSocketService struct {
	db          *database.Database
	connections map[string]*websocketConnection
	connMutex   sync.RWMutex
	isRunning   bool
	messageChan chan broker.KafkaMessage
	jwtSecret   []byte // Replace authService with just the JWT secret
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

// SetJWTSecret sets the JWT secret for token validation
func (s *WebSocketService) SetJWTSecret(secret []byte) {
	s.jwtSecret = secret
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

// HandleConnection handles a new WebSocket connection with token authentication from query parameters
func (s *WebSocketService) HandleConnection(c *gin.Context) {
	// Extract token from query parameter
	tokenString := c.Query("token")
	if tokenString == "" {
		log.Printf("WebSocket connection attempt with missing token")
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication token required"})
		return
	}

	// Validate token using token utility
	if s.jwtSecret == nil {
		log.Printf("JWT secret not set in WebSocketService")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Authentication service unavailable"})
		return
	}

	// Validate the token and get the associated user ID
	claims, err := token.ValidateToken(tokenString, s.jwtSecret)
	if err != nil {
		log.Printf("Invalid WebSocket auth token: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid authentication token"})
		return
	}

	userID := claims.UserID
	log.Printf("WebSocket authenticated for user: %s", userID)

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

	wsConn.conn.SetReadLimit(1024)                                 // Increase read limit to handle larger messages
	wsConn.conn.SetReadDeadline(time.Now().Add(120 * time.Second)) // Increase timeout
	wsConn.conn.SetPongHandler(func(string) error {
		wsConn.conn.SetReadDeadline(time.Now().Add(120 * time.Second))
		return nil
	})

	for {
		_, message, err := wsConn.conn.ReadMessage()
		if err != nil {
			log.Printf("Connection %s closing with error: %v", connID, err)
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Error reading message: %v", err)
			}
			break
		}

		// Log raw message for debugging - convert bytes to string safely
		log.Printf("Received raw message from %s: %s", connID, string(message))

		// Try to parse the message, but handle errors gracefully
		var clientMsg models.StandardMessage
		if err := json.Unmarshal(message, &clientMsg); err != nil {
			log.Printf("Error unmarshalling client message: %v, raw: %s", err, string(message))

			// Instead of just continuing, send an error message back
			errorMsg := models.NewStandardMessage(models.ErrorMessage, "parse_error", map[string]interface{}{
				"message": "Failed to parse message",
				"error":   err.Error(),
			})
			errorBytes, _ := json.Marshal(errorMsg)
			wsConn.send <- errorBytes
			continue
		}

		// Additional debugging for subscription messages
		if clientMsg.Type == models.SubscribeMessage {
			log.Printf("Subscription message details - Type: %s, Event: %s, Payload: %+v",
				clientMsg.Type, clientMsg.Event, clientMsg.Payload)
		}

		// Handle message based on type
		switch clientMsg.Type {
		case models.EventMessage:
			// Handle event messages
			log.Printf("Event message from user %s: Event=%s", wsConn.userID, clientMsg.Event)

			// Get the event name from the message
			eventName := clientMsg.Event

			// Process based on specific event type
			switch eventName {
			case "presence":
				// Handle presence notifications
				log.Printf("User %s sent presence event", wsConn.userID)

			case "typing":
				// Handle typing indicators
				log.Printf("User %s sent typing event", wsConn.userID)

				// Forward typing indicators to relevant users
				if clientMsg.ResourceType != "" && clientMsg.ResourceID != "" {
					s.BroadcastEvent(&clientMsg)
				}

			default:
				// For resource-specific events, check resource info and forward
				if clientMsg.ResourceType != "" && clientMsg.ResourceID != "" {
					log.Printf("User %s sent resource event: %s for %s:%s",
						wsConn.userID, eventName, clientMsg.ResourceType, clientMsg.ResourceID)

					// Forward to other clients with access to this resource
					s.BroadcastEvent(&clientMsg)
				} else {
					log.Printf("Unhandled event type '%s' from user %s", eventName, wsConn.userID)
				}
			}

			// Send confirmation receipt
			confirm := models.NewStandardMessage("receipt", "confirmed", map[string]interface{}{
				"event_id": clientMsg.ID,
				"status":   "processed",
			})
			confirmBytes, _ := json.Marshal(confirm)
			wsConn.send <- confirmBytes

		case models.SubscribeMessage:
			// Handle subscription requests
			log.Printf("Subscription request from user %s", wsConn.userID)

			// Extract subscription details
			if clientMsg.Payload != nil {
				// Check for event_type subscription
				if et, ok := clientMsg.Payload["event_type"].(string); ok {
					log.Printf("User %s subscribed to event: %s", wsConn.userID, et)

					// Send confirmation
					confirm := models.NewStandardMessage("subscription", "confirmed", map[string]interface{}{
						"event_type": et,
					})
					confirmBytes, _ := json.Marshal(confirm)
					wsConn.send <- confirmBytes
				}

				// Check for resource subscription
				if resource, ok := clientMsg.Payload["resource"].(string); ok {
					resourceID := ""
					if id, ok := clientMsg.Payload["id"].(string); ok {
						resourceID = id
					}

					log.Printf("User %s subscribed to resource: %s ID: %s",
						wsConn.userID, resource, resourceID)

					// Send confirmation
					confirm := models.NewStandardMessage("subscription", "confirmed", map[string]interface{}{
						"resource": resource,
						"id":       resourceID,
					})
					confirmBytes, _ := json.Marshal(confirm)
					wsConn.send <- confirmBytes
				}
			}

		default:
			log.Printf("Received unknown message type '%s' from user %s", clientMsg.Type, wsConn.userID)
		}
	}
}

func (s *WebSocketService) writePump(connID string, wsConn *websocketConnection) {
	ticker := time.NewTicker(30 * time.Second) // More frequent pings (30s instead of 54s)
	defer func() {
		ticker.Stop()
		wsConn.conn.Close()
	}()

	for {
		select {
		case message, ok := <-wsConn.send:
			wsConn.conn.SetWriteDeadline(time.Now().Add(15 * time.Second)) // Longer deadline
			if !ok {
				// Channel was closed
				wsConn.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := wsConn.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				log.Printf("Error getting next writer for conn %s: %v", connID, err)
				return
			}

			if _, err := w.Write(message); err != nil {
				log.Printf("Error writing message to conn %s: %v", connID, err)
				return
			}

			// Add queued messages to the current websocket message
			n := len(wsConn.send)
			for i := 0; i < n; i++ {
				w.Write([]byte("\n"))
				if _, err := w.Write(<-wsConn.send); err != nil {
					log.Printf("Error writing queued message to conn %s: %v", connID, err)
					return
				}
			}

			if err := w.Close(); err != nil {
				log.Printf("Error closing writer for conn %s: %v", connID, err)
				return
			}

		case <-ticker.C:
			wsConn.conn.SetWriteDeadline(time.Now().Add(15 * time.Second))
			if err := wsConn.conn.WriteMessage(websocket.PingMessage, []byte{}); err != nil {
				log.Printf("Error sending ping to conn %s: %v", connID, err)
				return
			}
			log.Printf("Sent ping to %s", connID)
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
