package routes

import (
	"net/http"

	"daviderutigliano/owlistic/database"
	"daviderutigliano/owlistic/models"
	"daviderutigliano/owlistic/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// RegisterRoleRoutes registers routes for role management
func RegisterRoleRoutes(group *gin.RouterGroup, db *database.Database, roleService services.RoleServiceInterface) {
	group.GET("/roles", func(c *gin.Context) { GetRoles(c, db, roleService) })
	group.POST("/roles", func(c *gin.Context) { AssignRole(c, db, roleService) })
	group.DELETE("/roles/:id", func(c *gin.Context) { RemoveRole(c, db, roleService) })
}

// GetRoles returns roles based on query parameters
func GetRoles(c *gin.Context, db *database.Database, roleService services.RoleServiceInterface) {
	// Extract query parameters
	params := make(map[string]interface{})

	if userID := c.Query("user_id"); userID != "" {
		params["user_id"] = userID
	}

	if resourceID := c.Query("resource_id"); resourceID != "" {
		params["resource_id"] = resourceID
	}

	if resourceType := c.Query("resource_type"); resourceType != "" {
		params["resource_type"] = resourceType
	}

	if roleType := c.Query("role"); roleType != "" {
		params["role"] = roleType
	}

	roles, err := roleService.GetRoles(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, roles)
}

type roleAssignmentRequest struct {
	UserID       string              `json:"user_id" binding:"required"`
	ResourceID   string              `json:"resource_id" binding:"required"`
	ResourceType models.ResourceType `json:"resource_type" binding:"required"`
	Role         models.RoleType     `json:"role" binding:"required"`
}

// AssignRole assigns a new role to a user for a specific resource
func AssignRole(c *gin.Context, db *database.Database, roleService services.RoleServiceInterface) {
	var req roleAssignmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID, err := uuid.Parse(req.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	resourceID, err := uuid.Parse(req.ResourceID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid resource ID"})
		return
	}

	// Check if the current user has owner access to the resource
	currentUserIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication required"})
		return
	}

	currentUserID, ok := currentUserIDInterface.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
		return
	}

	hasOwnerAccess, err := roleService.HasAccess(db, currentUserID, resourceID, req.ResourceType, models.OwnerRole)
	if err != nil || !hasOwnerAccess {
		c.JSON(http.StatusForbidden, gin.H{"error": "You must be the owner of this resource to assign roles"})
		return
	}

	err = roleService.AssignRole(db, userID, resourceID, req.ResourceType, req.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "Role assigned successfully",
		"user_id":       req.UserID,
		"resource_id":   req.ResourceID,
		"resource_type": req.ResourceType,
		"role":          req.Role,
	})
}

// RemoveRole removes a role assignment
func RemoveRole(c *gin.Context, db *database.Database, roleService services.RoleServiceInterface) {
	roleID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid role ID"})
		return
	}

	// TODO: Add authorization check to ensure current user has permission to remove this role

	err = roleService.RemoveRole(db, roleID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Role removed successfully",
	})
}
