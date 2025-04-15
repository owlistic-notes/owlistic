package services

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/thinkstack/broker"
	"github.com/thinkstack/database"
)

// WebSocketServiceInterface defines the operations provided by the WebSocket service
type WebSocketServiceInterface interface {
	Start()
	Stop()
	StartWithPort(port string)
	BroadcastMessage(message []byte)
	GetKafkaChannel() chan broker.KafkaMessage
	SetKafkaInputChannel(ch <-chan broker.KafkaMessage)
}

// Client represents a connected WebSocket client
type Client struct {
	ID            string
	UserID        string
	Hub           *WebSocketService
	Conn          *websocket.Conn
	Send          chan []byte
	Subscriptions map[string]bool // Resources this client is subscribed to
}

// ClientMessage represents a message from the client
type ClientMessage struct {
	Type    string          `json:"type"`
	Action  string          `json:"action"`
	Payload json.RawMessage `json:"payload"`
}

// ServerMessage represents a message to the client
type ServerMessage struct {
	Type    string      `json:"type"`
	Event   string      `json:"event"`
	Payload interface{} `json:"payload"`
}

// WebSocketService manages WebSocket connections
type WebSocketService struct {
	// Client management
	clients      map[string]*Client
	register     chan *Client
	unregister   chan *Client
	broadcast    chan []byte
	clientsMutex sync.RWMutex

	// Configuration
	upgrader    websocket.Upgrader
	db          *database.Database
	kafkaTopics []string

	// Message channels
	kafkaMessages chan broker.KafkaMessage

	// Control
	isRunning bool
	stopChan  chan struct{}

	// For testing
	kafkaInputChannel <-chan broker.KafkaMessage
}

// NewWebSocketService creates a new WebSocket service
func NewWebSocketService(db *database.Database, topics []string) WebSocketServiceInterface {
	return &WebSocketService{
		// Client management
		clients:    make(map[string]*Client),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		broadcast:  make(chan []byte),

		// Configuration
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				return true // Allow all origins for development
			},
		},
		db:          db,
		kafkaTopics: topics,

		// Message channels
		kafkaMessages: make(chan broker.KafkaMessage, 256),

		// Control
		isRunning: false,
		stopChan:  make(chan struct{}),

		// Initialize kafkaInputChannel as nil - will be set in StartWithPort
		kafkaInputChannel: nil,
	}
}

// Start begins the WebSocket service on a standard port
func (ws *WebSocketService) Start() {
	ws.StartWithPort(":8082") // Use a different port from main API
}

// BroadcastMessage sends a message to all connected clients
func (ws *WebSocketService) BroadcastMessage(message []byte) {
	ws.broadcast <- message
}

// GetKafkaChannel returns the internal kafka message channel - useful for testing
func (ws *WebSocketService) GetKafkaChannel() chan broker.KafkaMessage {
	return ws.kafkaMessages
}

// SetKafkaInputChannel allows setting a custom channel for Kafka messages - useful for testing
func (ws *WebSocketService) SetKafkaInputChannel(ch <-chan broker.KafkaMessage) {
	ws.kafkaInputChannel = ch
}

// StartWithPort begins the WebSocket service on a specific port
func (ws *WebSocketService) StartWithPort(port string) {
	if ws.isRunning {
		return
	}
	ws.isRunning = true

	// Start the main hub routine
	go ws.run()

	// If a custom Kafka input channel was provided (for testing), use it
	if ws.kafkaInputChannel != nil {
		go ws.forwardKafkaMessages(ws.kafkaInputChannel)
	} else {
		// Otherwise initialize real Kafka consumer and connect it to our channel
		kafkaChan, err := broker.InitConsumer(ws.kafkaTopics, "websocket-group")
		if err != nil {
			log.Printf("Failed to initialize Kafka consumer: %v", err)
			log.Println("WebSocket service will run with reduced functionality")
		}

		// Start forwarding Kafka messages
		go ws.forwardKafkaMessages(kafkaChan)
	}

	// Setup HTTP handler for WebSocket connections
	http.HandleFunc("/ws", ws.handleWebSocket)

	log.Printf("WebSocket service started on %s", port)

	// Start HTTP server
	go func() {
		if err := http.ListenAndServe(port, nil); err != nil {
			log.Printf("WebSocket server error: %v", err)
		}
	}()
}

// forwardKafkaMessages forwards messages from the Kafka channel to our internal channel
func (ws *WebSocketService) forwardKafkaMessages(kafkaChan <-chan broker.KafkaMessage) {
	// Recover from panics to prevent service disruption
	defer func() {
		if r := recover(); r != nil {
			log.Printf("Recovered from panic in forwardKafkaMessages: %v", r)
			// Try to restart after a short delay
			go func() {
				time.Sleep(5 * time.Second)
				ws.forwardKafkaMessages(kafkaChan)
			}()
		}
	}()

	for msg := range kafkaChan {
		if !ws.isRunning {
			return
		}

		// Send message to our internal channel
		select {
		case ws.kafkaMessages <- msg:
			// Message forwarded successfully
		default:
			// Channel is full, log warning
			log.Printf("Warning: Kafka message channel is full, discarding message")
		}
	}

	// If we get here, the Kafka channel was closed
	log.Println("Kafka message channel closed, WebSocket service will no longer receive Kafka events")
}

// Stop gracefully shuts down the WebSocket service
func (ws *WebSocketService) Stop() {
	if !ws.isRunning {
		return
	}

	ws.isRunning = false
	close(ws.stopChan)

	// Close all client connections
	ws.clientsMutex.Lock()
	for _, client := range ws.clients {
		// Add a nil check before closing the connection
		if client != nil && client.Conn != nil {
			client.Conn.Close()
		}
	}
	ws.clientsMutex.Unlock()

	log.Println("WebSocket service stopped")
}

// run handles the main client message hub
func (ws *WebSocketService) run() {
	for {
		select {
		case <-ws.stopChan:
			return

		case client := <-ws.register:
			ws.clientsMutex.Lock()
			ws.clients[client.ID] = client
			ws.clientsMutex.Unlock()
			log.Printf("Client connected: %s (user: %s)", client.ID, client.UserID)

		case client := <-ws.unregister:
			ws.clientsMutex.Lock()
			if _, ok := ws.clients[client.ID]; ok {
				delete(ws.clients, client.ID)
				close(client.Send)
				log.Printf("Client disconnected: %s", client.ID)
			}
			ws.clientsMutex.Unlock()

		case message := <-ws.broadcast:
			// Send to all clients
			ws.clientsMutex.RLock()
			for _, client := range ws.clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(ws.clients, client.ID)
				}
			}
			ws.clientsMutex.RUnlock()

		case kafkaMsg := <-ws.kafkaMessages:
			// Process and route Kafka message
			ws.handleKafkaMessage(kafkaMsg)
		}
	}
}

// handleWebSocket upgrades HTTP connection to WebSocket
func (ws *WebSocketService) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// Upgrade the HTTP connection to WebSocket
	conn, err := ws.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Error upgrading to WebSocket: %v", err)
		return
	}

	// Get user ID from query param, header, or cookie - in production use proper auth
	userID := r.URL.Query().Get("user_id")
	if userID == "" {
		userID = r.Header.Get("X-User-ID")
	}
	if userID == "" {
		userID = "anonymous"
	}

	// Create new client
	client := &Client{
		ID:            uuid.New().String(),
		UserID:        userID,
		Hub:           ws,
		Conn:          conn,
		Send:          make(chan []byte, 256),
		Subscriptions: make(map[string]bool),
	}

	// Register this client
	ws.register <- client

	// Start goroutines for reading and writing
	go client.readPump()
	go client.writePump()
}

// handleKafkaMessage processes Kafka messages and routes to subscribed clients
func (ws *WebSocketService) handleKafkaMessage(msg broker.KafkaMessage) {
	// Parse the message
	var eventData map[string]interface{}
	if err := json.Unmarshal([]byte(msg.Value), &eventData); err != nil {
		log.Printf("Error parsing Kafka message: %v", err)
		return
	}

	// Log full message for debugging
	log.Printf("WebSocket service: Received Kafka message: Key=%s, Type=%T", msg.Key, eventData)

	// Extract event type from the event data (for more reliable event type handling)
	eventType := msg.Key // Default to Kafka message key
	if typeVal, ok := eventData["type"].(string); ok {
		eventType = typeVal
	}

	// Extract resource information
	resourceID, resourceType := ws.extractResourceInfo(eventData)
	log.Printf("Extracted resource info: type=%s, id=%s", resourceType, resourceID)

	// Create server message
	serverMsg := ServerMessage{
		Type:    "event",
		Event:   eventType,
		Payload: eventData,
	}

	// Serialize the message
	jsonData, err := json.Marshal(serverMsg)
	if err != nil {
		log.Printf("Error serializing server message: %v", err)
		return
	}

	// Count number of clients that received this message
	clientCount := 0
	connectedCount := 0

	ws.clientsMutex.RLock()
	for clientID, client := range ws.clients {
		connectedCount++

		// IMPORTANT: More flexible matching for subscriptions using various formats
		shouldSend := false

		log.Printf("Checking client %s subscriptions for event %s (resource: %s, id: %s)",
			clientID, eventType, resourceType, resourceID)

		// Check if client is subscribed to:
		// 1. All events
		if client.Subscriptions["all"] {
			shouldSend = true
			log.Printf("Client %s is subscribed to 'all'", clientID)
		}

		// 2. This entity type (e.g., "note")
		if !shouldSend && client.Subscriptions[resourceType] {
			shouldSend = true
			log.Printf("Client %s is subscribed to resource type '%s'", clientID, resourceType)
		}

		// 3. This specific entity (e.g., "note:123")
		if !shouldSend && resourceID != "" && client.Subscriptions[resourceType+":"+resourceID] {
			shouldSend = true
			log.Printf("Client %s is subscribed to specific resource '%s:%s'",
				clientID, resourceType, resourceID)
		}

		// 4. Notebook-specific notes subscription
		if !shouldSend && resourceType == "note" {
			// Try to extract notebook ID from the payload
			notebookID := ""

			if payload, ok := eventData["payload"].(map[string]interface{}); ok {
				if nbID, ok := payload["notebook_id"].(string); ok {
					notebookID = nbID
				} else if data, ok := payload["data"].(map[string]interface{}); ok {
					if nbID, ok := data["notebook_id"].(string); ok {
						notebookID = nbID
					}
				}
			}

			if notebookID != "" {
				// Check if client is subscribed to this notebook's notes
				if client.Subscriptions["notebook:notes:"+notebookID] ||
					client.Subscriptions["notebook:"+notebookID] {
					shouldSend = true
					log.Printf("Client %s is subscribed to notebook %s notes", clientID, notebookID)
				}
			}
		}

		// 5. Plural form for collection subscriptions
		if !shouldSend && client.Subscriptions[resourceType+"s"] {
			shouldSend = true
			log.Printf("Client %s is subscribed to plural form '%ss'", clientID, resourceType)
		}

		log.Printf("Final decision - send to client %s: %v", clientID, shouldSend)

		if shouldSend {
			select {
			case client.Send <- jsonData:
				clientCount++
				log.Printf("Sent %s event to client %s", eventType, clientID)
			default:
				log.Printf("Client %s send buffer full, removing client", clientID)
				close(client.Send)
				delete(ws.clients, clientID)
			}
		}
	}
	ws.clientsMutex.RUnlock()

	log.Printf("Sent %s event to %d clients (out of %d connected)", eventType, clientCount, connectedCount)

	// If no clients received this message, log all subscriptions for debugging
	if clientCount == 0 && connectedCount > 0 {
		ws.logAllSubscriptions()
	}
}

// logAllSubscriptions logs all current subscriptions for debugging
func (ws *WebSocketService) logAllSubscriptions() {
	ws.clientsMutex.RLock()
	defer ws.clientsMutex.RUnlock()

	log.Printf("--- Current Subscriptions (Clients: %d) ---", len(ws.clients))
	for clientID, client := range ws.clients {
		log.Printf("Client %s has %d subscriptions:", clientID, len(client.Subscriptions))
		for sub := range client.Subscriptions {
			log.Printf("  - %s", sub)
		}
	}
	log.Printf("------------------------------------------")
}

// extractResourceInfo gets resource info from event data
func (ws *WebSocketService) extractResourceInfo(eventData map[string]interface{}) (string, string) {
	resourceID := ""
	resourceType := "unknown"

	// Log the complete event data for debugging
	jsonBytes, _ := json.MarshalIndent(eventData, "", "  ")
	log.Printf("WebSocket extractResourceInfo raw data: %s", string(jsonBytes))

	// First check for direct top-level fields which are most reliable
	if noteID, ok := eventData["note_id"].(string); ok && noteID != "" {
		resourceID = noteID
		resourceType = "note"
		log.Printf("Found direct note_id: %s", noteID)
	} else if notebookID, ok := eventData["notebook_id"].(string); ok && notebookID != "" {
		resourceID = notebookID
		resourceType = "notebook"
		log.Printf("Found direct notebook_id: %s", notebookID)
	} else if blockID, ok := eventData["block_id"].(string); ok && blockID != "" {
		resourceID = blockID
		resourceType = "block"
		log.Printf("Found direct block_id: %s", blockID)
	}

	// If we have the event type, we can determine the resource type from it
	if eventType, ok := eventData["type"].(string); ok && resourceType == "unknown" {
		parts := strings.Split(eventType, ".")
		if len(parts) >= 1 {
			// First part should be the entity type (note.created, notebook.updated, etc.)
			entityType := parts[0]
			if entityType == "note" || entityType == "notebook" || entityType == "block" {
				resourceType = entityType
				log.Printf("Determined resource type from event type: %s", resourceType)
			}
		}
	}

	// If we still don't have a resourceID or resourceType, look in the payload
	if resourceID == "" || resourceType == "unknown" {
		if payload, ok := eventData["payload"].(map[string]interface{}); ok {
			// Try extracting directly from payload
			if noteID, ok := payload["note_id"].(string); ok && noteID != "" {
				resourceID = noteID
				resourceType = "note"
				log.Printf("Found payload note_id: %s", noteID)
			} else if notebookID, ok := payload["notebook_id"].(string); ok && notebookID != "" {
				resourceID = notebookID
				resourceType = "notebook"
				log.Printf("Found payload notebook_id: %s", notebookID)
			} else if blockID, ok := payload["block_id"].(string); ok && blockID != "" {
				resourceID = blockID
				resourceType = "block"
				log.Printf("Found payload block_id: %s", blockID)
			}

			// If there's a data field, also check there
			if data, ok := payload["data"].(map[string]interface{}); ok {
				if resourceID == "" {
					if noteID, ok := data["note_id"].(string); ok && noteID != "" {
						resourceID = noteID
						resourceType = "note"
						log.Printf("Found data.note_id: %s", noteID)
					} else if id, ok := data["id"].(string); ok && data["entity"] == "note" {
						resourceID = id
						resourceType = "note"
						log.Printf("Found data.id for note: %s", id)
					} else if notebookID, ok := data["notebook_id"].(string); ok && notebookID != "" {
						resourceID = notebookID
						resourceType = "notebook"
						log.Printf("Found data.notebook_id: %s", notebookID)
					} else if id, ok := data["id"].(string); ok && data["entity"] == "notebook" {
						resourceID = id
						resourceType = "notebook"
						log.Printf("Found data.id for notebook: %s", id)
					} else if blockID, ok := data["block_id"].(string); ok && blockID != "" {
						resourceID = blockID
						resourceType = "block"
						log.Printf("Found data.block_id: %s", blockID)
					} else if id, ok := data["id"].(string); ok && data["entity"] == "block" {
						resourceID = id
						resourceType = "block"
						log.Printf("Found data.id for block: %s", id)
					}
				}

				// If we have ID but no type, try to detect type from content
				if resourceID != "" && resourceType == "unknown" {
					if _, ok := data["title"]; ok {
						resourceType = "note"
					} else if _, ok := data["name"]; ok {
						resourceType = "notebook"
					} else if _, ok := data["content"]; ok {
						resourceType = "block"
					}
				}
			}
		}
	}

	// Fallback: If we have the event type but still don't have a resource type
	if resourceType == "unknown" && eventData["event"] != nil {
		event := eventData["event"].(string)
		if strings.HasPrefix(event, "note") {
			resourceType = "note"
		} else if strings.HasPrefix(event, "notebook") {
			resourceType = "notebook"
		} else if strings.HasPrefix(event, "block") {
			resourceType = "block"
		}
	}

	log.Printf("Final extracted resource info: type=%s, id=%s", resourceType, resourceID)
	return resourceID, resourceType
}

// readPump handles incoming messages from the WebSocket client
func (c *Client) readPump() {
	defer func() {
		c.Hub.unregister <- c
		c.Conn.Close()
	}()

	c.Conn.SetReadLimit(4096)
	c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Error reading from WebSocket: %v", err)
			}
			break
		}

		// Process the received message
		c.processMessage(message)
	}
}

// writePump pumps messages from the hub to the WebSocket connection
func (c *Client) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				// The hub closed the channel
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Add queued messages to the current websocket message
			n := len(c.Send)
			for i := 0; i < n; i++ {
				w.Write(<-c.Send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// processMessage handles messages received from the client
func (c *Client) processMessage(msg []byte) {
	var clientMsg ClientMessage
	if err := json.Unmarshal(msg, &clientMsg); err != nil {
		log.Printf("Error parsing client message: %v", err)
		return
	}

	switch clientMsg.Type {
	case "subscribe":
		c.handleSubscribe(clientMsg)
	case "unsubscribe":
		c.handleUnsubscribe(clientMsg)
	case "block_update":
		c.handleBlockUpdate(clientMsg)
	case "note_update":
		c.handleNoteUpdate(clientMsg)
	case "ping":
		// Just a keepalive, no response needed
	default:
		log.Printf("Unknown message type: %s", clientMsg.Type)
	}
}

// handleSubscribe processes subscription requests
func (c *Client) handleSubscribe(msg ClientMessage) {
	var payload struct {
		Resource string `json:"resource"`
		ID       string `json:"id,omitempty"`
	}

	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		log.Printf("Error parsing subscription payload: %v", err)
		return
	}

	subscriptionKey := payload.Resource
	if payload.ID != "" {
		subscriptionKey = payload.Resource + ":" + payload.ID
	}

	// Check if already subscribed to avoid duplicate confirmations
	if _, alreadySubscribed := c.Subscriptions[subscriptionKey]; alreadySubscribed {
		log.Printf("Client %s already subscribed to %s, skipping", c.ID, subscriptionKey)
		return
	}

	// Add this subscription
	if payload.ID != "" {
		c.Subscriptions[payload.Resource+":"+payload.ID] = true
		log.Printf("Client %s subscribed to %s:%s", c.ID, payload.Resource, payload.ID)
	} else {
		c.Subscriptions[payload.Resource] = true
		log.Printf("Client %s subscribed to all %s", c.ID, payload.Resource)
	}

	// Send confirmation message back to client
	confirmationMsg := ServerMessage{
		Type:  "subscription",
		Event: "confirmed",
		Payload: map[string]interface{}{
			"resource": payload.Resource,
			"id":       payload.ID,
		},
	}

	jsonData, err := json.Marshal(confirmationMsg)
	if err == nil {
		// Important: Add a short delay before sending confirmation
		// to avoid multiple confirmations being concatenated
		time.Sleep(10 * time.Millisecond)
		c.Send <- jsonData
	}
}

// handleUnsubscribe processes unsubscription requests
func (c *Client) handleUnsubscribe(msg ClientMessage) {
	var payload struct {
		Resource string `json:"resource"`
		ID       string `json:"id,omitempty"`
	}

	if err := json.Unmarshal(msg.Payload, &payload); err != nil {
		log.Printf("Error parsing unsubscription payload: %v", err)
		return
	}

	// Remove this subscription
	if payload.ID != "" {
		delete(c.Subscriptions, payload.Resource+":"+payload.ID)
	} else {
		delete(c.Subscriptions, payload.Resource)
	}
}

// handleBlockUpdate processes block update requests
func (c *Client) handleBlockUpdate(msg ClientMessage) {
	var blockUpdate struct {
		ID      string `json:"id"`
		Content string `json:"content"`
		Type    string `json:"type,omitempty"`
	}

	if err := json.Unmarshal(msg.Payload, &blockUpdate); err != nil {
		log.Printf("Error parsing block update: %v", err)
		return
	}

	log.Printf("Received block update request for block ID: %s", blockUpdate.ID)

	// Create update request
	updateData := map[string]interface{}{
		"actor_id": c.UserID,
		"content":  blockUpdate.Content,
	}

	if blockUpdate.Type != "" {
		updateData["type"] = blockUpdate.Type
	}

	// Save via block service
	if c.Hub.db != nil {
		blockService := BlockServiceInstance
		log.Printf("Updating block %s with content: %s", blockUpdate.ID, blockUpdate.Content)
		updatedBlock, err := blockService.UpdateBlock(c.Hub.db, blockUpdate.ID, updateData)
		if err != nil {
			log.Printf("Error updating block: %v", err)
			// Send error back to client
			errorMsg, _ := json.Marshal(map[string]string{
				"type":    "error",
				"message": "Failed to update block: " + err.Error(),
			})
			c.Send <- errorMsg
		} else {
			log.Printf("Block updated successfully: %s", updatedBlock.ID)
		}
	} else {
		log.Printf("Cannot update block: database connection is nil")
	}
}

// handleNoteUpdate processes note update requests
func (c *Client) handleNoteUpdate(msg ClientMessage) {
	var noteUpdate struct {
		ID    string `json:"id"`
		Title string `json:"title"`
	}

	if err := json.Unmarshal(msg.Payload, &noteUpdate); err != nil {
		log.Printf("Error parsing note update: %v", err)
		return
	}

	// Create update request
	updateData := map[string]interface{}{
		"user_id": c.UserID,
		"title":   noteUpdate.Title,
	}

	// Save via note service
	if c.Hub.db != nil {
		noteService := NoteServiceInstance
		_, err := noteService.UpdateNote(c.Hub.db, noteUpdate.ID, updateData)
		if err != nil {
			log.Printf("Error updating note: %v", err)
			// Send error back to client
			errorMsg, _ := json.Marshal(map[string]string{
				"type":    "error",
				"message": "Failed to update note: " + err.Error(),
			})
			c.Send <- errorMsg
		}
	}
}

// Global instance
var WebSocketServiceInstance WebSocketServiceInterface
