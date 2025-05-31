package services

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/config"
	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"
	"owlistic-notes/owlistic/utils/token"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/nats-io/nats.go"
)

type WebSocketServiceInterface interface {
	Start(cfg config.Config)
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
	jwtSecret   []byte
	eventTopics []string
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

func NewWebSocketService(db *database.Database) WebSocketServiceInterface {
	// Initialize WebSocket service with the database
	return &WebSocketService{
		db:          db,
		connections: make(map[string]*websocketConnection),
		isRunning:   false,
		eventTopics: broker.SubjectNames,
	}
}

func NewWebSocketServiceWithTopics(db *database.Database, topics []string) WebSocketServiceInterface {
	// Initialize WebSocket service with the database
	return &WebSocketService{
		db:          db,
		connections: make(map[string]*websocketConnection),
		isRunning:   false,
		eventTopics: topics,
	}
}

// SetJWTSecret sets the JWT secret for token validation
func (s *WebSocketService) SetJWTSecret(secret []byte) {
	s.jwtSecret = secret
}

func (s *WebSocketService) Start(cfg config.Config) {
	if s.isRunning {
		return
	}
	s.isRunning = true

	// Initialize consumer for all relevant topics
	consumer, err := broker.InitConsumer(cfg, s.eventTopics, "websocket-service")
	if err != nil {
		log.Printf("Failed to initialize consumer: %v", err)
		return
	}

	messageChan := consumer.GetMessageChannel()

	// Start listening for messages
	go s.consumeMessages(messageChan)
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
		createdAt: time.Now().UTC(),
	}

	// Register the connection
	s.connMutex.Lock()
	s.connections[connID] = wsConn
	s.connMutex.Unlock()

	log.Printf("New WebSocket connection established: %s for user: %s", connID, userID)

	// Handle the connection (read/write routines)
	go s.readPump(connID, wsConn)
	go s.writePump(connID, wsConn)
}

// consumeMessages processes messages and dispatches them to clients
func (s *WebSocketService) consumeMessages(messageChan chan *nats.Msg) {
	for {
		select {
		case msg := <-messageChan:
			// Parse the message
			var event models.StandardMessage
			if err := json.Unmarshal(msg.Data, &event); err != nil {
				log.Printf("Error unmarshalling event: %v", err)
				continue
			}
			// Broadcast the event to all connected clients
			s.BroadcastEvent(&event)
		case <-time.After(1 * time.Second):
		}
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

	wsConn.conn.SetReadLimit(1024)                                       // Increase read limit to handle larger messages
	wsConn.conn.SetReadDeadline(time.Now().UTC().Add(120 * time.Second)) // Increase timeout
	wsConn.conn.SetPongHandler(func(string) error {
		wsConn.conn.SetReadDeadline(time.Now().UTC().Add(120 * time.Second))
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

		case "ping":
			// Handle ping messages
			log.Printf("Ping message from user %s", wsConn.userID)
			// Send a pong response
			pong := models.NewStandardMessage("pong", "pong", nil)
			pongBytes, _ := json.Marshal(pong)
			wsConn.send <- pongBytes
			log.Printf("Pong sent to user %s", wsConn.userID)

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
				if clientMsg.Event != "" {
					log.Printf("User %s subscribed to event: %s", wsConn.userID, clientMsg.Event)

					payload := map[string]interface{}{
						"event_type": clientMsg.Event,
					}
					// Send confirmation
					confirm := models.NewStandardMessage("subscription", "confirmed", payload)
					confirmBytes, _ := json.Marshal(confirm)
					wsConn.send <- confirmBytes
				}

				// Check for resource subscription
				if resource, ok := clientMsg.Payload["resource"].(string); ok {
					resourceID, hasID := clientMsg.Payload["id"].(string)

					log.Printf("User %s subscribed to resource: %s ID: %s",
						wsConn.userID, resource, resourceID)

					// Send confirmation - only include ID if it's not empty
					payload := map[string]interface{}{
						"resource": resource,
					}

					// Only add the ID to the payload if it exists and is not empty
					if hasID && resourceID != "" {
						payload["id"] = resourceID
					}

					confirm := models.NewStandardMessage("subscription", "confirmed", payload)
					confirmBytes, _ := json.Marshal(confirm)
					wsConn.send <- confirmBytes
				}
			}

		case models.UnsubscribeMessage:
			// Handle unsubscription requests
			log.Printf("Unsubscription request from user %s", wsConn.userID)

			// Extract unsubscription details
			if clientMsg.Payload != nil {
				// Check for event_type unsubscription
				if et, ok := clientMsg.Payload["event_type"].(string); ok {
					log.Printf("User %s unsubscribed from event: %s", wsConn.userID, et)

					// Send confirmation
					confirm := models.NewStandardMessage("unsubscription", "confirmed", map[string]interface{}{
						"event_type": et,
					})
					confirmBytes, _ := json.Marshal(confirm)
					wsConn.send <- confirmBytes
				}

				// Check for resource unsubscription
				if resource, ok := clientMsg.Payload["resource"].(string); ok {
					resourceID, hasID := clientMsg.Payload["id"].(string)

					log.Printf("User %s unsubscribed from resource: %s ID: %s",
						wsConn.userID, resource, resourceID)

					// Send confirmation - only include ID if it's not empty
					payload := map[string]interface{}{
						"resource": resource,
					}

					// Only add the ID to the payload if it exists and is not empty
					if hasID && resourceID != "" {
						payload["id"] = resourceID
					}

					confirm := models.NewStandardMessage("unsubscription", "confirmed", payload)
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
			wsConn.conn.SetWriteDeadline(time.Now().UTC().Add(15 * time.Second)) // Longer deadline
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
			wsConn.conn.SetWriteDeadline(time.Now().UTC().Add(15 * time.Second))
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
