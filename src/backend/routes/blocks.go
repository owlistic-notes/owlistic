package routes

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"

	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
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

// swagger:operation GET /blocks Blocks GetBlocks
// Get Blocks
// 
// --- 
// responses: 
// 
//  500: InternalServerError
//  401: Unauthorized
//  200: Success
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

	// Pagination parameters
	if page := c.Query("page"); page != "" {
		if pageNum, err := strconv.Atoi(page); err == nil {
			params["page"] = pageNum
		}
	}

	if pageSize := c.Query("page_size"); pageSize != "" {
		if size, err := strconv.Atoi(pageSize); err == nil {
			params["page_size"] = size
		}
	}

	// Check if client wants total count
	if countTotal := c.Query("count_total"); countTotal == "true" {
		params["count_total"] = true
	}

	blocks, err := blockService.GetBlocks(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// If total count was requested, return it in headers
	if countTotal, ok := params["count_total"].(bool); ok && countTotal {
		// We would need to modify our service to return this count
		// For now, just returning the blocks
		c.Header("X-Total-Count", fmt.Sprintf("%d", len(blocks)))
	}

	c.JSON(http.StatusOK, blocks)
}

func CreateBlock(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	var blockData map[string]interface{}
	if err := c.ShouldBindJSON(&blockData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create params map for permissions check
	params := make(map[string]interface{})

	// Add user ID from context to params
	userIDInterface, exists := c.Get("userID")
	if exists {
		params["user_id"] = userIDInterface.(uuid.UUID).String()
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	block, err := blockService.CreateBlock(db, blockData, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, block)
}

func GetBlockById(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	id := c.Param("id")

	// Create params map for permissions check
	params := make(map[string]interface{})

	// Add user ID from context to params
	userIDInterface, exists := c.Get("userID")
	if exists {
		params["user_id"] = userIDInterface.(uuid.UUID).String()
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	block, err := blockService.GetBlockById(db, id, params)
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

	// Create params map for permissions check
	params := make(map[string]interface{})

	// Add user ID from context to params (not to blockData)
	userIDInterface, exists := c.Get("userID")
	if exists {
		params["user_id"] = userIDInterface.(uuid.UUID).String()
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	// Note: blockData may contain metadata field with styling information
	// which will be properly handled by the UpdateBlock service method

	block, err := blockService.UpdateBlock(db, id, blockData, params)
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

	// Create params map for permissions check
	params := make(map[string]interface{})

	// Add user ID from context to params
	userIDInterface, exists := c.Get("userID")
	if exists {
		params["user_id"] = userIDInterface.(uuid.UUID).String()
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	if err := blockService.DeleteBlock(db, id, params); err != nil {
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

	blocks, err := blockService.ListBlocksByNote(db, noteID, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, blocks)
}
