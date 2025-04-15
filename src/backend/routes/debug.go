package routes

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

// SetupDebugRoutes sets up routes for debugging
func SetupDebugRoutes(router *gin.Engine, db *database.Database) {
	debugGroup := router.Group("/api/v1/debug")
	{
		debugGroup.GET("/note-exists/:id", func(c *gin.Context) {
			id := c.Param("id")

			// Check if note exists
			var note models.Note
			result := db.DB.Where("id = ?", id).First(&note)

			if result.Error != nil {
				c.JSON(http.StatusOK, gin.H{
					"exists": false,
					"error":  result.Error.Error(),
					"time":   time.Now(),
				})
				return
			}

			c.JSON(http.StatusOK, gin.H{
				"exists":      true,
				"id":          note.ID,
				"title":       note.Title,
				"notebook_id": note.NotebookID,
				"time":        time.Now(),
			})
		})

		// Add route to check transaction processing queue
		debugGroup.GET("/event-queue", func(c *gin.Context) {
			var events []models.Event
			db.DB.Where("dispatched = ?", false).Find(&events)

			c.JSON(http.StatusOK, gin.H{
				"pending_events": len(events),
				"events":         events,
				"time":           time.Now(),
			})
		})
	}
}
