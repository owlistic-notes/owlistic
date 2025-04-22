package routes

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"github.com/thinkstack/services"
)

func RegisterTaskRoutes(group *gin.RouterGroup, db *database.Database, taskService services.TaskServiceInterface) {
	// Use GetTasks instead of GetAllTasks to support query parameters
	group.GET("/tasks", func(c *gin.Context) { GetTasks(c, db, taskService) })
	group.POST("/tasks", func(c *gin.Context) { CreateTask(c, db, taskService) })
	group.GET("/tasks/:id", func(c *gin.Context) { GetTaskById(c, db, taskService) })
	group.PUT("/tasks/:id", func(c *gin.Context) { UpdateTask(c, db, taskService) })
	group.DELETE("/tasks/:id", func(c *gin.Context) { DeleteTask(c, db, taskService) })
}

func CreateTask(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	var taskData map[string]interface{}
	if err := c.ShouldBindJSON(&taskData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get user ID from context and add it to task data
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	taskData["user_id"] = userIDInterface.(uuid.UUID).String()

	createdTask, err := taskService.CreateTask(db, taskData)
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

	// Verify the authenticated user owns this task
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uuid.UUID)

	if task.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized to access this task"})
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

	// Get user ID from context to verify ownership
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uuid.UUID)

	// Verify ownership before update
	existingTask, err := taskService.GetTaskById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if existingTask.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized to update this task"})
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

	// Get user ID from context to verify ownership
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	userID := userIDInterface.(uuid.UUID)

	// Verify ownership before delete
	existingTask, err := taskService.GetTaskById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrTaskNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if existingTask.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "Not authorized to delete this task"})
		return
	}

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

func GetTasks(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	// Extract query parameters
	params := make(map[string]interface{})

	// Get user ID from context instead of query parameter
	userIDInterface, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}
	params["user_id"] = userIDInterface.(uuid.UUID).String()

	// Add other filter parameters
	if blockID := c.Query("block_id"); blockID != "" {
		params["block_id"] = blockID
	}

	if completed := c.Query("completed"); completed != "" {
		params["completed"] = completed
	}

	if title := c.Query("title"); title != "" {
		params["title"] = title
	}

	if dueDate := c.Query("due_date"); dueDate != "" {
		params["due_date"] = dueDate
	}

	tasks, err := taskService.GetTasks(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, tasks)
}
