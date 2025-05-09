package routes

import (
	"net/http"

	"daviderutigliano/owlistic/database"
	"daviderutigliano/owlistic/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// RegisterTrashRoutes registers all routes related to trash functionality
func RegisterTrashRoutes(group *gin.RouterGroup, db *database.Database, trashService services.TrashServiceInterface) {
	// Get all trashed items
	group.GET("/trash", func(c *gin.Context) { GetTrashedItems(c, db, trashService) })

	// Restore a trashed item
	group.POST("/trash/restore/:type/:id", func(c *gin.Context) { RestoreItem(c, db, trashService) })

	// Permanently delete a trashed item
	group.DELETE("/trash/:type/:id", func(c *gin.Context) { PermanentlyDeleteItem(c, db, trashService) })

	// Empty trash (delete all trashed items permanently)
	group.DELETE("/trash", func(c *gin.Context) { EmptyTrash(c, db, trashService) })
}

// GetTrashedItems retrieves all soft-deleted notes and notebooks
func GetTrashedItems(c *gin.Context, db *database.Database, trashService services.TrashServiceInterface) {
	// Get user ID from context instead of query parameter
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uuid.UUID).String()

	result, err := trashService.GetTrashedItems(db, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve trashed items"})
		return
	}

	c.JSON(http.StatusOK, result)
}

// RestoreItem restores a soft-deleted item
func RestoreItem(c *gin.Context, db *database.Database, trashService services.TrashServiceInterface) {
	itemType := c.Param("type")
	itemID := c.Param("id")

	// Get user ID from context instead of query parameter
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uuid.UUID).String()

	if err := trashService.RestoreItem(db, itemType, itemID, userID); err != nil {
		if err == services.ErrInvalidInput {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported item type. Must be 'note' or 'notebook'"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to restore item: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Item restored successfully",
		"type":    itemType,
		"id":      itemID,
	})
}

// PermanentlyDeleteItem permanently deletes a trashed item
func PermanentlyDeleteItem(c *gin.Context, db *database.Database, trashService services.TrashServiceInterface) {
	itemType := c.Param("type")
	itemID := c.Param("id")

	// Get user ID from context instead of query parameter
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uuid.UUID).String()

	if err := trashService.PermanentlyDeleteItem(db, itemType, itemID, userID); err != nil {
		if err == services.ErrInvalidInput {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported item type. Must be 'note' or 'notebook'"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to permanently delete item: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Item permanently deleted", "type": itemType, "id": itemID})
}

// EmptyTrash permanently deletes all trashed items for a user
func EmptyTrash(c *gin.Context, db *database.Database, trashService services.TrashServiceInterface) {
	// Get user ID from context instead of query parameter
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uuid.UUID).String()

	if err := trashService.EmptyTrash(db, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to empty trash: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Trash emptied successfully"})
}
