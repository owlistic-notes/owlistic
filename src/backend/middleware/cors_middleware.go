package middleware

import (
	"net/http"
	"strings"

	gin "github.com/gin-gonic/gin"
)

// CORSMiddleware adds the required headers to allow cross-origin requests
func CORSMiddleware(allowOrigins []string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if len(allowOrigins) == 0 {
			allowOrigins = []string{"*"} // Default to allow all origins if none provided
		}

		// Set CORS headers
		c.Writer.Header().Set("Access-Control-Allow-Origin", strings.Join(allowOrigins, ","))
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE, PATCH")
		c.Writer.Header().Set("Access-Control-Max-Age", "3600")

		// Handle preflight requests
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}