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
		// Use GetTasks instead of GetAllTasks to support query parameters
		group.GET("/", func(c *gin.Context) { GetTasks(c, db, taskService) })
		group.POST("/", func(c *gin.Context) { CreateTask(c, db, taskService) })
		group.GET("/:id", func(c *gin.Context) { GetTaskById(c, db, taskService) })
		group.PUT("/:id", func(c *gin.Context) { UpdateTask(c, db, taskService) })
		group.DELETE("/:id", func(c *gin.Context) { DeleteTask(c, db, taskService) })
	}
}

func CreateTask(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	var taskData map[string]interface{}
	if err := c.ShouldBindJSON(&taskData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

func GetTasks(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	// Extract query parameters
	params := make(map[string]interface{})

	if userID := c.Query("user_id"); userID != "" {
		params["user_id"] = userID
	}

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

func GetAllTasks(c *gin.Context, db *database.Database, taskService services.TaskServiceInterface) {
	tasks, err := taskService.GetAllTasks(db)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, tasks)
}
