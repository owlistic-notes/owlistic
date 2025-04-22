package routes

import (
	"github.com/gin-gonic/gin"
	"github.com/thinkstack/middleware"
	"github.com/thinkstack/services"
)

// RegisterWebSocketRoutes sets up WebSocket endpoints with authentication
func RegisterWebSocketRoutes(router *gin.Engine, authService services.AuthServiceInterface, wsService services.WebSocketServiceInterface) {
	// Ensure WebSocketService has the auth service available
	if wsServiceWithAuth, ok := wsService.(*services.WebSocketService); ok {
		wsServiceWithAuth.SetAuthService(authService)
	}

	// Create a WebSocket group with authentication middleware
	wsGroup := router.Group("/api/v1/ws")
	wsGroup.Use(middleware.WebSocketAuthMiddleware(authService))
	{
		// WebSocket connection endpoint
		wsGroup.GET("", func(c *gin.Context) {
			wsService.HandleConnection(c)
		})
	}
}
