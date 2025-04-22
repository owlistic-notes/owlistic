package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"github.com/thinkstack/services"
)

// AccessControlMiddleware ensures users can only access resources they have permission for
func AccessControlMiddleware(db *database.Database) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Skip access control for certain endpoints
		if isExemptFromAccessControl(c.FullPath(), c.Request.Method) {
			c.Next()
			return
		}

		// Get user ID from context (set by AuthMiddleware)
		userIDInterface, exists := c.Get("userID")
		if !exists {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "User ID not found in context"})
			return
		}

		userID, ok := userIDInterface.(uuid.UUID)
		if !ok {
			c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
			return
		}

		// Extract resource information from the path
		resourceType, resourceID := getResourceInfoFromPath(c.FullPath())

		// For collection endpoints (GET /api/v1/notes/), let the service handle filtering
		if resourceID == "" {
			// For list endpoints, add user_id to query params for filtering if not present
			query := c.Request.URL.Query()
			if query.Get("user_id") == "" {
				query.Set("user_id", userID.String())
				c.Request.URL.RawQuery = query.Encode()
			}

			c.Next()
			return
		}

		// For resource-specific endpoints (GET /notes/123), check permissions
		resourceUUID, err := uuid.Parse(resourceID)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "Invalid resource ID"})
			return
		}

		// Determine minimum required role based on HTTP method
		var requiredRole models.RoleType
		switch c.Request.Method {
		case http.MethodGet:
			requiredRole = models.ViewerRole
		case http.MethodPut, http.MethodPatch:
			requiredRole = models.EditorRole
		case http.MethodDelete:
			requiredRole = models.OwnerRole
		case http.MethodPost:
			requiredRole = models.EditorRole
		default:
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Unsupported method"})
			return
		}

		// Check if the user has the required role
		hasAccess, err := services.RoleServiceInstance.HasAccess(db, userID, resourceUUID, resourceType, requiredRole)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusInternalServerError,
				gin.H{"error": "Error checking permissions: " + err.Error()})
			return
		}

		if !hasAccess {
			c.AbortWithStatusJSON(http.StatusForbidden,
				gin.H{"error": "Insufficient permissions for this resource"})
			return
		}

		// Store resource type and ID in context for route handlers
		c.Set("resourceType", resourceType)
		c.Set("resourceID", resourceUUID)

		c.Next()
	}
}

// Helper functions for the middleware
func isExemptFromAccessControl(path, method string) bool {
	// Exempt authentication endpoints
	if strings.Contains(path, "/api/v1/auth") {
		return true
	}

	// Exempt registration endpoint
	if path == "/api/v1/register" && method == http.MethodPost {
		return true
	}

	// Exempt health/debug endpoints
	if strings.Contains(path, "/api/v1/health") ||
		strings.Contains(path, "/health") {
		return true
	}

	// Websocket endpoint
	if strings.Contains(path, "/ws") {
		return true
	}

	return false
}

// getResourceInfoFromPath extracts resource type and ID from the path
func getResourceInfoFromPath(path string) (models.ResourceType, string) {
	segments := strings.Split(path, "/")
	if len(segments) < 4 {
		return "", ""
	}

	resourceTypeStr := segments[3] // e.g., "notes"
	var resourceType models.ResourceType

	// Map plural form in URL to resource type
	switch resourceTypeStr {
	case "notes":
		resourceType = models.NoteResource
	case "notebooks":
		resourceType = models.NotebookResource
	case "blocks":
		resourceType = models.BlockResource
	case "tasks":
		resourceType = models.TaskResource
	case "users":
		resourceType = models.UserResource
	default:
		return "", ""
	}

	// Extract ID if present (for resource-specific operations)
	if len(segments) > 4 && segments[4] != "" {
		return resourceType, segments[4]
	}

	return resourceType, ""
}
