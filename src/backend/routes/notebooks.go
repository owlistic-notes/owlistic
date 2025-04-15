package routes

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/thinkstack/database"
	"github.com/thinkstack/services"
)

func RegisterNotebookRoutes(router *gin.Engine, db *database.Database, notebookService services.NotebookServiceInterface) {
	group := router.Group("/api/v1/notebooks")
	{
		// Collection endpoints with query parameters
		group.GET("/", func(c *gin.Context) { GetNotebooks(c, db, notebookService) })
		group.POST("/", func(c *gin.Context) { CreateNotebook(c, db, notebookService) })

		// Resource-specific endpoints
		group.GET("/:id", func(c *gin.Context) { GetNotebookById(c, db, notebookService) })
		group.PUT("/:id", func(c *gin.Context) { UpdateNotebook(c, db, notebookService) })
		group.DELETE("/:id", func(c *gin.Context) { DeleteNotebook(c, db, notebookService) })
	}
}

func GetNotebooks(c *gin.Context, db *database.Database, notebookService services.NotebookServiceInterface) {
	// Extract query parameters
	params := make(map[string]interface{})

	if userID := c.Query("user_id"); userID != "" {
		params["user_id"] = userID
	}

	if name := c.Query("name"); name != "" {
		params["name"] = name
	}

	notebooks, err := notebookService.GetNotebooks(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, notebooks)
}

func CreateNotebook(c *gin.Context, db *database.Database, notebookService services.NotebookServiceInterface) {
	var notebookData map[string]interface{}
	if err := c.ShouldBindJSON(&notebookData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	notebook, err := notebookService.CreateNotebook(db, notebookData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, notebook)
}

func GetNotebookById(c *gin.Context, db *database.Database, notebookService services.NotebookServiceInterface) {
	id := c.Param("id")
	notebook, err := notebookService.GetNotebookById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrNotebookNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Notebook not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, notebook)
}

func UpdateNotebook(c *gin.Context, db *database.Database, notebookService services.NotebookServiceInterface) {
	id := c.Param("id")
	var notebookData map[string]interface{}
	if err := c.ShouldBindJSON(&notebookData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	notebook, err := notebookService.UpdateNotebook(db, id, notebookData)
	if err != nil {
		if errors.Is(err, services.ErrNotebookNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Notebook not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, notebook)
}

func DeleteNotebook(c *gin.Context, db *database.Database, notebookService services.NotebookServiceInterface) {
	id := c.Param("id")
	if err := notebookService.DeleteNotebook(db, id); err != nil {
		if errors.Is(err, services.ErrNotebookNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Notebook not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusNoContent, gin.H{})
}

func ListNotebooksByUser(c *gin.Context, db *database.Database, notebookService services.NotebookServiceInterface) {
	userID := c.Param("user_id")
	notebooks, err := notebookService.ListNotebooksByUser(db, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, notebooks)
}
