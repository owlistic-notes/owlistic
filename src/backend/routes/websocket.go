package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/owlistic/services"
)

// RegisterWebSocketRoutes sets up WebSocket endpoints with authentication
func RegisterWebSocketRoutes(group *gin.RouterGroup, wsService services.WebSocketServiceInterface) {
	// Register the WebSocket route without middleware - auth happens in the handler
	// by extracting the token from query parameter
	group.GET("", func(c *gin.Context) { wsService.HandleConnection(c) })
}
