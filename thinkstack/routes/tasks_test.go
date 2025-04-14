package routes

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"github.com/thinkstack/services"
)

type MockTaskService struct{}

func (m *MockTaskService) CreateTask(db *database.Database, task models.Task) (models.Task, error) {
	return task, nil
}

func (m *MockTaskService) GetTaskById(db *database.Database, id string) (models.Task, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Task{ID: uuid.Must(uuid.Parse(id)), Title: "Test Task"}, nil
	}
	return models.Task{}, services.ErrTaskNotFound
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
	RegisterTaskRoutes(router, db, mockService)

	t.Run("Valid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/tasks/", bytes.NewBuffer([]byte(`{"title":"Test Task"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})
}

func TestGetTaskById(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}
	RegisterTaskRoutes(router, db, mockService)

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

func TestUpdateTask(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockTaskService{}
	RegisterTaskRoutes(router, db, mockService)

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
	RegisterTaskRoutes(router, db, mockService)

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
		assert.Equal(t, http.StatusOK, w.Code)
	})
}
