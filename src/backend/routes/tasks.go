package routes

import (
	"errors"
	"net/http"

	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"github.com/thinkstack/services"

	"github.com/gin-gonic/gin"
)

func RegisterTaskRoutes(router *gin.Engine, db *database.Database, taskService services.TaskServiceInterface) {
	group := router.Group("/api/v1/tasks")
	{
		group.POST("/", func(c *gin.Context) { CreateTask(c, db, taskService) })
		group.GET("/:id", func(c *gin.Context) { GetTaskById(c, db, taskService) })
		group.PUT("/:id", func(c *gin.Context) { UpdateTask(c, db, taskService) })
		group.DELETE("/:id", func(c *gin.Context) { DeleteTask(c, db, taskService) })
	}
}

func CreateTask(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	var task models.Task
	if err := c.ShouldBindJSON(&task); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	createdTask, err := taskService.CreateTask(db, task)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, createdTask)
}

func GetTaskById(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	id := c.Param("id")
	task, err := taskService.GetTaskById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, task)
}

func UpdateTask(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	id := c.Param("id")
	var task models.Task
	if err := c.ShouldBindJSON(&task); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updatedTask, err := taskService.UpdateTask(db, id, task)
	if err != nil {
		if errors.Is(err, services.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updatedTask)
}

func DeleteTask(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	id := c.Param("id")
	if err := taskService.DeleteTask(db, id); err != nil {
		if errors.Is(err, services.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusNoContent, gin.H{})
}
