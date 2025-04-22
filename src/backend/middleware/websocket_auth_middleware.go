package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/thinkstack/services"
)

// WebSocketAuthMiddleware validates JWT tokens for WebSocket connections
func WebSocketAuthMiddleware(authService services.AuthServiceInterface) gin.HandlerFunc {
	return func(c *gin.Context) {
		// First try to get token from query parameter (common for WebSocket connections)
		token := c.Query("token")

		// If not in query, try header (like regular API auth)
		if token == "" {
			authHeader := c.GetHeader("Authorization")
			if authHeader == "" {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
				return
			}

			// Extract token from Bearer schema
			parts := strings.Split(authHeader, " ")
			if len(parts) != 2 || parts[0] != "Bearer" {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Authorization header format must be Bearer {token}"})
				return
			}
			token = parts[1]
		}

		// Validate the token
		claims, err := authService.ValidateToken(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Invalid or expired token"})
			return
		}

		// Store user info in the context for later use
		c.Set("userID", claims.UserID)
		c.Set("email", claims.Email)

		c.Next()
	}
}
