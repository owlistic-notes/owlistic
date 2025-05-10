package routes

import (
	"errors"
	"net/http"

	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func RegisterNoteRoutes(group *gin.RouterGroup, db *database.Database, noteService services.NoteServiceInterface) {
	// Collection endpoints with query parameters
	group.GET("/notes", func(c *gin.Context) { GetNotes(c, db, noteService) })
	group.POST("/notes", func(c *gin.Context) { CreateNote(c, db, noteService) })

	// Resource-specific endpoints
	group.GET("/notes/:id", func(c *gin.Context) { GetNoteById(c, db, noteService) })
	group.PUT("/notes/:id", func(c *gin.Context) { UpdateNote(c, db, noteService) })
	group.DELETE("/notes/:id", func(c *gin.Context) { DeleteNote(c, db, noteService) })
}

func CreateNote(c *gin.Context, db *database.Database, noteService services.NoteServiceInterface) {
	var noteData map[string]interface{}
	if err := c.ShouldBindJSON(&noteData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get user ID from context and add to note data
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Not authenticated"})
		return
	}
	noteData["user_id"] = userIDInterface.(uuid.UUID).String()

	createdNote, err := noteService.CreateNote(db, noteData)
	if err != nil {
		if errors.Is(err, services.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Resource not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, createdNote)
}

func GetNoteById(c *gin.Context, db *database.Database, noteService services.NoteServiceInterface) {
	id := c.Param("id")

	// Create params map for permissions check
	params := make(map[string]interface{})

	// Add user ID from context to params
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Not authenticated"})
		return
	}
	params["user_id"] = userIDInterface.(uuid.UUID).String()

	note, err := noteService.GetNoteById(db, id, params)
	if err != nil {
		if errors.Is(err, services.ErrNoteNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Note not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, note)
}

func UpdateNote(c *gin.Context, db *database.Database, noteService services.NoteServiceInterface) {
	id := c.Param("id")
	var noteData map[string]interface{}
	if err := c.ShouldBindJSON(&noteData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create params map for permissions check
	params := make(map[string]interface{})

	// Get user ID from context and add to params
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Not authenticated"})
		return
	}
	params["user_id"] = userIDInterface.(uuid.UUID).String()

	updatedNote, err := noteService.UpdateNote(db, id, noteData, params)
	if err != nil {
		if errors.Is(err, services.ErrNoteNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Note not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updatedNote)
}

func DeleteNote(c *gin.Context, db *database.Database, noteService services.NoteServiceInterface) {
	id := c.Param("id")

	// Create params map for permissions check
	params := make(map[string]interface{})

	// Add user ID from context to params
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Not authenticated"})
		return
	}
	params["user_id"] = userIDInterface.(uuid.UUID).String()

	if err := noteService.DeleteNote(db, id, params); err != nil {
		if errors.Is(err, services.ErrNoteNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Note not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusNoContent, gin.H{})
}

func GetNotes(c *gin.Context, db *database.Database, noteService services.NoteServiceInterface) {
	// Extract query parameters
	params := make(map[string]interface{})

	// Get user ID from context (set by AuthMiddleware)
	userIDInterface, exists := c.Get("userID")
	if exists {
		// Convert user ID to string and add to params
		params["user_id"] = userIDInterface.(uuid.UUID).String()
	}

	// Add other query parameters
	if notebookID := c.Query("notebook_id"); notebookID != "" {
		params["notebook_id"] = notebookID
	}

	if title := c.Query("title"); title != "" {
		params["title"] = title
	}

	// Add parameter to exclude deleted notes by default
	params["include_deleted"] = false
	if includeDeleted := c.Query("include_deleted"); includeDeleted == "true" {
		params["include_deleted"] = true
	}

	notes, err := noteService.GetNotes(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Log how many notes were found
	c.JSON(http.StatusOK, notes)
}
