package routes

import (
	"errors"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/services"
)

func RegisterBlockRoutes(group *gin.RouterGroup, db *database.Database, blockService services.BlockServiceInterface) {
	// Collection endpoints with query parameters
	group.GET("/blocks", func(c *gin.Context) { GetBlocks(c, db, blockService) })
	group.POST("/blocks", func(c *gin.Context) { CreateBlock(c, db, blockService) })

	// Resource-specific endpoints
	group.GET("/blocks/:id", func(c *gin.Context) { GetBlockById(c, db, blockService) })
	group.PUT("/blocks/:id", func(c *gin.Context) { UpdateBlock(c, db, blockService) })
	group.DELETE("/blocks/:id", func(c *gin.Context) { DeleteBlock(c, db, blockService) })
}

func GetBlocks(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	// Extract query parameters
	params := make(map[string]interface{})

	// Get user ID from context (added by AuthMiddleware)
	userIDInterface, exists := c.Get("userID")
	if exists {
		// Convert user ID to string and add to params
		params["user_id"] = userIDInterface.(uuid.UUID).String()
		log.Printf("Using userID from context: %s", params["user_id"])
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	// Extract other query parameters
	if noteID := c.Query("note_id"); noteID != "" {
		params["note_id"] = noteID
	}

	if blockType := c.Query("type"); blockType != "" {
		params["type"] = blockType
	}

	blocks, err := blockService.GetBlocks(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, blocks)
}

func CreateBlock(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	var blockData map[string]interface{}
	if err := c.ShouldBindJSON(&blockData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Add user ID from context to blockData
	userIDInterface, exists := c.Get("userID")
	if exists {
		blockData["user_id"] = userIDInterface.(uuid.UUID).String()
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	block, err := blockService.CreateBlock(db, blockData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, block)
}

func GetBlockById(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	id := c.Param("id")
	block, err := blockService.GetBlockById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrBlockNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Block not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, block)
}

func UpdateBlock(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	id := c.Param("id")
	var blockData map[string]interface{}
	if err := c.ShouldBindJSON(&blockData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Add user ID from context to blockData for permission checking
	userIDInterface, exists := c.Get("userID")
	if exists {
		blockData["user_id"] = userIDInterface.(uuid.UUID).String()
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	block, err := blockService.UpdateBlock(db, id, blockData)
	if err != nil {
		if errors.Is(err, services.ErrBlockNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Block not found"})
			return
		} else if errors.Is(err, services.ErrInvalidInput) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid input data"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, block)
}

func DeleteBlock(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	id := c.Param("id")

	// We need to get the block first to check ownership
	block, err := blockService.GetBlockById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrBlockNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Block not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Verify user is authorized to delete this block
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	userID := userIDInterface.(uuid.UUID)
	if block.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized to delete this block"})
		return
	}

	if err := blockService.DeleteBlock(db, id); err != nil {
		if errors.Is(err, services.ErrBlockNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Block not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusNoContent, nil)
}

func GetBlocksByNote(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	noteID := c.Param("note_id")

	// Extract query parameters
	params := make(map[string]interface{})

	// Get user ID from context (added by AuthMiddleware)
	userIDInterface, exists := c.Get("userID")
	if exists {
		// Convert user ID to string and add to params
		params["user_id"] = userIDInterface.(uuid.UUID).String()
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	// Add note ID to params
	params["note_id"] = noteID

	blocks, err := blockService.GetBlocks(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, blocks)
}
