package routes

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/thinkstack/database"
	"github.com/thinkstack/services"
)

func RegisterNoteRoutes(router *gin.Engine, db *database.Database, noteService services.NoteServiceInterface) {
	group := router.Group("/api/v1/notes")
	{
		group.POST("/", func(c *gin.Context) { CreateNote(c, db, noteService) })
		group.GET("/:id", func(c *gin.Context) { GetNoteById(c, db, noteService) })
		group.PUT("/:id", func(c *gin.Context) { UpdateNote(c, db, noteService) })
		group.DELETE("/:id", func(c *gin.Context) { DeleteNote(c, db, noteService) })
		group.GET("/user/:user_id", func(c *gin.Context) { ListNotesByUser(c, db, noteService) })
	}
}

func CreateNote(c *gin.Context, db *database.Database, noteService services.NoteServiceInterface) {
	var noteData map[string]interface{}
	if err := c.ShouldBindJSON(&noteData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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
	note, err := noteService.GetNoteById(db, id)
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

	updatedNote, err := noteService.UpdateNote(db, id, noteData)
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
	if err := noteService.DeleteNote(db, id); err != nil {
		if errors.Is(err, services.ErrNoteNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Note not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusNoContent, gin.H{})
}

func ListNotesByUser(c *gin.Context, db *database.Database, noteService services.NoteServiceInterface) {
	userID := c.Param("user_id")
	notes, err := noteService.ListNotesByUser(db, userID)
	if err != nil {
		if errors.Is(err, services.ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "No notes found for the user"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, notes)
}
