package middleware

import (
	"github.com/gin-contrib/cors"
	gin "github.com/gin-gonic/gin"
)

// CORSMiddleware adds the required headers to allow cross-origin requests
func CORSMiddleware() gin.HandlerFunc {

	// Set up CORS configuration
	corsConfig := cors.Config{
		AllowAllOrigins:  true,
		AllowWildcard:    true,
		AllowWebSockets:  true,
		AllowCredentials: true,
		AllowMethods: []string{
			"GET",
			"POST",
			"PUT",
			"PATCH",
			"DELETE",
			"OPTIONS",
		},
		AllowHeaders: []string{
			"Authorization",
			"Accept",
			"Origin",
			"Accept-Encoding",
			"Content-Type",
			"Content-Length",
			"Cache-Control",
			"X-CSRF-Token",
			"X-Requested-With",
		},
		MaxAge: 12 * 3600, // 12 hours
	}

	return cors.New(corsConfig)
}
