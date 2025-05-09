package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/owlistic/services"
	"github.com/owlistic/utils/token"
)

// ExtractAndValidateToken uses the token utility instead
func ExtractAndValidateToken(c *gin.Context, authService services.AuthServiceInterface) (*token.JWTClaims, error) {
	// Extract token from query or header
	tokenString, err := token.ExtractToken(c)
	if err != nil {
		return nil, err
	}

	// Validate the token using the auth service (which now uses the token utility)
	return authService.ValidateToken(tokenString)
}

func AuthMiddleware(authService services.AuthServiceInterface) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip authentication for OPTIONS requests (CORS preflight)
		if c.Request.Method == "OPTIONS" {
			c.Next()
			return
		}

		// Extract and validate token
		claims, err := ExtractAndValidateToken(c, authService)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
			return
		}

		// Store user info in the context for later use
		c.Set("userID", claims.UserID)
		c.Set("email", claims.Email)
		c.Next()
	}
}
