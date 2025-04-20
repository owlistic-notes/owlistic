package routes

import (
	"bytes"
	"errors"
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

type MockNotebookService struct{}

// Update GetNotebooks mock to properly handle the empty case
func (m *MockNotebookService) GetNotebooks(db *database.Database, params map[string]interface{}) ([]models.Notebook, error) {
	userID, hasUserID := params["user_id"].(string)
	name, hasName := params["name"].(string)

	// Empty case - user with no notebooks
	if hasUserID && userID == "90a12345-f12a-98c4-a456-513432930001" {
		return []models.Notebook{}, nil
	}

	// User with notebooks
	if hasUserID && userID == "90a12345-f12a-98c4-a456-513432930000" {
		notebooks := []models.Notebook{
			{
				ID:     uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
				Name:   "Test Notebook",
				UserID: uuid.Must(uuid.Parse(userID)),
			},
		}

		// Apply name filter if needed
		if hasName && name != "" {
			var filteredNotebooks []models.Notebook
			for _, notebook := range notebooks {
				if notebook.Name == name {
					filteredNotebooks = append(filteredNotebooks, notebook)
				}
			}
			return filteredNotebooks, nil
		}

		return notebooks, nil
	}

	// Default case - all notebooks
	notebooks := []models.Notebook{
		{
			ID:     uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
			Name:   "Test Notebook",
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
		{
			ID:     uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")),
			Name:   "Test Notebook 2",
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
	}

	// Apply name filter if needed
	if hasName && name != "" {
		var filteredNotebooks []models.Notebook
		for _, notebook := range notebooks {
			if notebook.Name == name {
				filteredNotebooks = append(filteredNotebooks, notebook)
			}
		}
		return filteredNotebooks, nil
	}

	return notebooks, nil
}

func (m *MockNotebookService) CreateNotebook(db *database.Database, notebookData map[string]interface{}) (models.Notebook, error) {
	name, ok := notebookData["name"].(string)
	if !ok || name == "" {
		return models.Notebook{}, errors.New("name is required")
	}

	userIDStr, ok := notebookData["user_id"].(string)
	if !ok {
		return models.Notebook{}, errors.New("user_id must be a string")
	}

	return models.Notebook{
		ID:     uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
		Name:   name,
		UserID: uuid.Must(uuid.Parse(userIDStr)),
	}, nil
}

func (m *MockNotebookService) GetNotebookById(db *database.Database, id string) (models.Notebook, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Notebook{
			ID:     uuid.Must(uuid.Parse(id)),
			Name:   "Test Notebook",
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		}, nil
	}
	return models.Notebook{}, services.ErrNotebookNotFound
}

func (m *MockNotebookService) UpdateNotebook(db *database.Database, id string, updatedData map[string]interface{}) (models.Notebook, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Notebook{
			ID:     uuid.Must(uuid.Parse(id)),
			Name:   updatedData["name"].(string),
			UserID: uuid.Must(uuid.Parse(updatedData["user_id"].(string))),
		}, nil
	}
	return models.Notebook{}, services.ErrNotebookNotFound
}

func (m *MockNotebookService) DeleteNotebook(db *database.Database, id string) error {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return nil
	}
	return services.ErrNotebookNotFound
}

func (m *MockNotebookService) ListNotebooksByUser(db *database.Database, userID string) ([]models.Notebook, error) {
	if userID == "90a12345-f12a-98c4-a456-513432930000" {
		return []models.Notebook{
			{ID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")), Name: "Test Notebook", UserID: uuid.Must(uuid.Parse(userID))},
		}, nil
	}
	return []models.Notebook{}, nil
}

func (m *MockNotebookService) GetAllNotebooks(db *database.Database) ([]models.Notebook, error) {
	return []models.Notebook{
		{
			ID:     uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
			Name:   "Test Notebook",
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
		{
			ID:     uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")),
			Name:   "Test Notebook 2",
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
	}, nil
}

func TestCreateNotebook(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNotebookService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterNotebookRoutes(apiGroup, db, mockService)

	t.Run("Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notebooks", bytes.NewBuffer([]byte("invalid json")))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("Missing Name", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notebooks/", bytes.NewBuffer([]byte(`{"user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("Valid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notebooks/", bytes.NewBuffer([]byte(`{"name":"Test Notebook", "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})
}

func TestGetNotebookById(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNotebookService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterNotebookRoutes(apiGroup, db, mockService)

	t.Run("Notebook Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notebooks/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Notebook Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notebooks/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestUpdateNotebook(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNotebookService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterNotebookRoutes(apiGroup, db, mockService)

	t.Run("Notebook Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/notebooks/123e4567-e89b-12d3-a456-426614174001", bytes.NewBuffer([]byte(`{"name":"Updated Notebook", "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Notebook Updated", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/notebooks/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte(`{"name":"Updated Notebook", "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestDeleteNotebook(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNotebookService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterNotebookRoutes(apiGroup, db, mockService)

	t.Run("Notebook Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/notebooks/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Notebook Deleted", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/notebooks/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNoContent, w.Code)
	})
}

func TestGetAllNotebooks(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNotebookService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterNotebookRoutes(apiGroup, db, mockService)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/notebooks/", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Test Notebook")
	assert.Contains(t, w.Body.String(), "Test Notebook 2")
}

// Add new test for notebooks with query parameters
func TestGetNotebooks(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNotebookService{}

	// Create a router group for api routes
	apiGroup := router.Group("/api/v1")
	RegisterNotebookRoutes(apiGroup, db, mockService)

	t.Run("Get Notebooks With No Filters", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notebooks/", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Notebook")
		assert.Contains(t, w.Body.String(), "Test Notebook 2")
	})

	t.Run("Get Notebooks By User ID - Notebooks Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notebooks/?user_id=90a12345-f12a-98c4-a456-513432930000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Notebook")
	})

	t.Run("Get Notebooks By User ID - No Notebooks Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notebooks/?user_id=90a12345-f12a-98c4-a456-513432930001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "[]")
	})

	t.Run("Get Notebooks By Name", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notebooks/?name=Test Notebook", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Notebook")
	})
}
