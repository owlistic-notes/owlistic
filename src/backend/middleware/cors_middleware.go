package middleware

import (
	"strings"

	"github.com/gin-contrib/cors"
	gin "github.com/gin-gonic/gin"
)

// CORSMiddleware adds the required headers to allow cross-origin requests
func CORSMiddleware(AppOrigins string) gin.HandlerFunc {

	// Set up CORS configuration
	corsConfig := cors.DefaultConfig()
	corsConfig.AllowOrigins = strings.Split(AppOrigins, ",")
	corsConfig.AllowWildcard = true
	corsConfig.AllowWebSockets = true
	corsConfig.AllowCredentials = true
	corsConfig.AllowHeaders = append(corsConfig.AllowHeaders, []string{
		"Accept",
		"Authorization",
		"Accept-Encoding",
		"X-CSRF-Token",
		"X-Requested-With",
	}...)

	return cors.New(corsConfig)
}
