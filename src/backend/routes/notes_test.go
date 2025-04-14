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

type MockNoteService struct{}

func (m *MockNoteService) CreateNote(db *database.Database, noteData map[string]interface{}) (models.Note, error) {
	title, ok := noteData["title"].(string)
	if !ok || title == "" {
		return models.Note{}, errors.New("title is required")
	}

	content, ok := noteData["content"].(string)
	if !ok {
		return models.Note{}, errors.New("content must be a string")
	}

	userIDStr, ok := noteData["user_id"].(string)
	if !ok {
		return models.Note{}, errors.New("user_id must be a string")
	}

	return models.Note{
		ID:      uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
		Title:   title,
		Content: content,
		UserID:  uuid.Must(uuid.Parse(userIDStr)),
	}, nil
}

func (m *MockNoteService) GetNoteById(db *database.Database, id string) (models.Note, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Note{
			ID:      uuid.Must(uuid.Parse(id)),
			Title:   "Test Note",
			Content: "This is a test note.",
			UserID:  uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		}, nil
	}
	return models.Note{}, services.ErrNoteNotFound
}

func (m *MockNoteService) UpdateNote(db *database.Database, id string, updatedData map[string]interface{}) (models.Note, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Note{
			ID:      uuid.Must(uuid.Parse(id)),
			Title:   updatedData["title"].(string),
			Content: updatedData["content"].(string),
			UserID:  uuid.Must(uuid.Parse(updatedData["user_id"].(string))),
		}, nil
	}
	return models.Note{}, services.ErrNoteNotFound
}

func (m *MockNoteService) DeleteNote(db *database.Database, id string) error {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return nil
	}
	return services.ErrNoteNotFound
}

func (m *MockNoteService) ListNotesByUser(db *database.Database, userID string) ([]models.Note, error) {
	if userID == "90a12345-f12a-98c4-a456-513432930000" {
		return []models.Note{
			{ID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")), Title: "Test Note", Content: "This is a test note.", UserID: uuid.Must(uuid.Parse(userID))},
		}, nil
	}
	return []models.Note{}, nil
}

func TestCreateNote(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNoteService{}
	RegisterNoteRoutes(router, db, mockService)

	t.Run("Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notes/", bytes.NewBuffer([]byte("invalid json")))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("Missing Title", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notes/", bytes.NewBuffer([]byte(`{"content":"Test Content", "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		services.NoteServiceInstance = mockService
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("Valid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notes/", bytes.NewBuffer([]byte(`{"title":"Test Note", "content":"Test Content", "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		services.NoteServiceInstance = mockService
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})
}

func TestGetNoteById(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNoteService{}
	RegisterNoteRoutes(router, db, mockService)

	t.Run("Note Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Note Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestUpdateNote(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNoteService{}
	RegisterNoteRoutes(router, db, mockService)

	t.Run("Note Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174001", bytes.NewBuffer([]byte(`{"title":"Updated Note", "content":"Updated Content", "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Note Updated", func(t *testing.T) {

		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte(`{"title":"Updated Note", "content":"Updated Content", "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestDeleteNote(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNoteService{}
	RegisterNoteRoutes(router, db, mockService)

	t.Run("Note Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Note Deleted", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNoContent, w.Code)
	})
}

func TestListNotesByUser(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNoteService{}
	RegisterNoteRoutes(router, db, mockService)

	t.Run("No Notes Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notes/user/90a12345-f12a-98c4-a456-513432930001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "[]")
	})

	t.Run("Notes Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notes/user/90a12345-f12a-98c4-a456-513432930000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Note")
	})
}
