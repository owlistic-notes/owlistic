package routes

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/thinkstack/database"
	"github.com/thinkstack/services"
)

func RegisterBlockRoutes(router *gin.Engine, db *database.Database, blockService services.BlockServiceInterface) {
	group := router.Group("/api/v1/blocks")
	{
		group.POST("/", func(c *gin.Context) { CreateBlock(c, db, blockService) })
		group.GET("/:id", func(c *gin.Context) { GetBlockById(c, db, blockService) })
		group.PUT("/:id", func(c *gin.Context) { UpdateBlock(c, db, blockService) })
		group.DELETE("/:id", func(c *gin.Context) { DeleteBlock(c, db, blockService) })
		group.GET("/note/:note_id", func(c *gin.Context) { ListBlocksByNote(c, db, blockService) })
	}
}

func CreateBlock(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	var blockData map[string]interface{}
	if err := c.ShouldBindJSON(&blockData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
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

	block, err := blockService.UpdateBlock(db, id, blockData)
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

func DeleteBlock(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	id := c.Param("id")
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

func ListBlocksByNote(c *gin.Context, db *database.Database, blockService services.BlockServiceInterface) {
	noteID := c.Param("note_id")
	blocks, err := blockService.ListBlocksByNote(db, noteID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, blocks)
}
