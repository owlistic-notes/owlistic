package routes

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"
	"owlistic-notes/owlistic/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

type MockTaskService struct{}

// Add GetTasks method for query parameter support
func (m *MockTaskService) GetTasks(db *database.Database, params map[string]interface{}) ([]models.Task, error) {
	userID, hasUserID := params["user_id"].(string)
	completed, hasCompleted := params["completed"].(string)

	tasks := []models.Task{
		{
			ID:          uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
			Title:       "Test Task",
			UserID:      uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
			IsCompleted: false,
		},
		{
			ID:          uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")),
			Title:       "Test Task 2",
			UserID:      uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
			IsCompleted: true,
		},
	}

	// Apply user filter
	if hasUserID && userID != "" {
		var filteredTasks []models.Task
		for _, task := range tasks {
			if task.UserID.String() == userID {
				filteredTasks = append(filteredTasks, task)
			}
		}
		tasks = filteredTasks
	}

	// Apply completed filter
	if hasCompleted && completed != "" {
		isCompleted := completed == "true"
		var filteredTasks []models.Task
		for _, task := range tasks {
			if task.IsCompleted == isCompleted {
				filteredTasks = append(filteredTasks, task)
			}
		}
		tasks = filteredTasks
	}

	return tasks, nil
}

func (m *MockTaskService) CreateTask(db *database.Database, taskData map[string]interface{}) (models.Task, error) {
	title, _ := taskData["title"].(string)
	userIDStr, _ := taskData["user_id"].(string)

	var userID uuid.UUID
	if userIDStr != "" {
		userID = uuid.Must(uuid.Parse(userIDStr))
	}

	blockID := uuid.New()
	noteIDStr, noteIDExists := taskData["note_id"].(string)
	if noteIDExists && noteIDStr != "" {
		// Simulate finding or creating a block for the note
		blockID = uuid.New()
	}

	return models.Task{
		ID:      uuid.New(),
		UserID:  userID,
		BlockID: blockID,
		Title:   title,
	}, nil
}

func (m *MockTaskService) GetTaskById(db *database.Database, id string) (models.Task, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Task{ID: uuid.Must(uuid.Parse(id)), Title: "Test Task"}, nil
	}
	return models.Task{}, services.ErrTaskNotFound
}

func (m *MockTaskService) GetAllTasks(db *database.Database) ([]models.Task, error) {
	return []models.Task{
		{ID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")), Title: "Test Task"},
		{ID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")), Title: "Test Task 2"},
	}, nil
}

func (m *MockTaskService) UpdateTask(db *database.Database, id string, updatedData models.Task) (models.Task, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Task{ID: uuid.Must(uuid.Parse(id)), Title: updatedData.Title}, nil
	}
	return models.Task{}, services.ErrTaskNotFound
}

func (m *MockTaskService) DeleteTask(db *database.Database, id string) error {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return nil
	}
	return services.ErrTaskNotFound
}

func TestCreateTask(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterTaskRoutes(apiGroup, db, mockService)

	t.Run("Valid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/tasks", bytes.NewBuffer([]byte(`{"title":"Test Task"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})
}

func TestGetTaskById(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterTaskRoutes(apiGroup, db, mockService)

	t.Run("Task Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/tasks/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Task Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/tasks/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestGetAllTasks(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterTaskRoutes(apiGroup, db, mockService)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/tasks", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Test Task")
	assert.Contains(t, w.Body.String(), "Test Task 2")
}

func TestUpdateTask(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterTaskRoutes(apiGroup, db, mockService)

	t.Run("Task Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/tasks/123e4567-e89b-12d3-a456-426614174001", bytes.NewBuffer([]byte(`{"title":"Updated Task"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Task Updated", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/tasks/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte(`{"title":"Updated Task"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestDeleteTask(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterTaskRoutes(apiGroup, db, mockService)

	t.Run("Task Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/tasks/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Task Deleted", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/tasks/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNoContent, w.Code)
	})
}

// Add new test for tasks with query parameters
func TestGetTasks(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterTaskRoutes(apiGroup, db, mockService)

	t.Run("Get Tasks With No Filters", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/tasks/", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Task")
		assert.Contains(t, w.Body.String(), "Test Task 2")
	})

	t.Run("Get Tasks By User ID", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/tasks/?user_id=90a12345-f12a-98c4-a456-513432930000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Task")
	})

	t.Run("Get Tasks By Completion Status", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/tasks/?completed=true", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Task 2")
	})
}
