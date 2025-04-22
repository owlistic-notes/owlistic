package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/thinkstack/services"
)

// RegisterWebSocketRoutes sets up WebSocket endpoints with authentication
func RegisterWebSocketRoutes(group *gin.RouterGroup, wsService services.WebSocketServiceInterface) {
	group.GET("", func(c *gin.Context) { wsService.HandleConnection(c) })
}
