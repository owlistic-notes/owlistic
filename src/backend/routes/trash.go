package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/thinkstack/database"
	"github.com/thinkstack/services"
)

// RegisterTrashRoutes registers all routes related to trash functionality
func RegisterTrashRoutes(router *gin.Engine, db *database.Database, trashService services.TrashServiceInterface) {
	group := router.Group("/api/v1/trash")
	{
		// Get all trashed items
		group.GET("/", func(c *gin.Context) { GetTrashedItems(c, db, trashService) })

		// Restore a trashed item
		group.POST("/restore/:type/:id", func(c *gin.Context) { RestoreItem(c, db, trashService) })

		// Permanently delete a trashed item
		group.DELETE("/:type/:id", func(c *gin.Context) { PermanentlyDeleteItem(c, db, trashService) })

		// Empty trash (delete all trashed items permanently)
		group.DELETE("/", func(c *gin.Context) { EmptyTrash(c, db, trashService) })
	}
}

// GetTrashedItems retrieves all soft-deleted notes and notebooks
func GetTrashedItems(c *gin.Context, db *database.Database, trashService services.TrashServiceInterface) {
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id parameter is required"})
		return
	}

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
	userID := c.Query("user_id")

	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id parameter is required"})
		return
	}

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
	userID := c.Query("user_id")

	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id parameter is required"})
		return
	}

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
	userID := c.Query("user_id")

	if userID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "user_id parameter is required"})
		return
	}

	if err := trashService.EmptyTrash(db, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to empty trash: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Trash emptied successfully"})
}
