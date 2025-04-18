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

// Add GetNotes method for query parameter support
func (m *MockNoteService) GetNotes(db *database.Database, params map[string]interface{}) ([]models.Note, error) {
	userID, hasUserID := params["user_id"].(string)
	notebookID, hasNotebookID := params["notebook_id"].(string)
	title, hasTitle := params["title"].(string)

	notes := []models.Note{
		{
			ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
			Title: "Test Note",
			Blocks: []models.Block{{
				ID:      uuid.New(),
				Type:    models.TextBlock,
				Content: models.BlockContent{"text": "This is a test note"},
				Order:   1,
			}},
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
		{
			ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")),
			Title: "Test Note 2",
			Blocks: []models.Block{{
				ID:      uuid.New(),
				Type:    models.TextBlock,
				Content: models.BlockContent{"text": "This is another test note"},
				Order:   1,
			}},
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
	}

	// Apply user filter
	if hasUserID && userID != "" {
		var filteredNotes []models.Note
		for _, note := range notes {
			if note.UserID.String() == userID {
				filteredNotes = append(filteredNotes, note)
			}
		}
		notes = filteredNotes
	}

	// Apply notebook filter
	if hasNotebookID && notebookID != "" {
		var filteredNotes []models.Note
		for _, note := range notes {
			if note.NotebookID.String() == notebookID {
				filteredNotes = append(filteredNotes, note)
			}
		}
		notes = filteredNotes
	}

	// Apply title filter
	if hasTitle && title != "" {
		var filteredNotes []models.Note
		for _, note := range notes {
			if note.Title == title {
				filteredNotes = append(filteredNotes, note)
			}
		}
		notes = filteredNotes
	}

	return notes, nil
}

func (m *MockNoteService) CreateNote(db *database.Database, noteData map[string]interface{}) (models.Note, error) {
	title, ok := noteData["title"].(string)
	if !ok || title == "" {
		return models.Note{}, errors.New("title is required")
	}

	blocks, ok := noteData["blocks"].([]interface{})
	if (!ok) {
		return models.Note{}, errors.New("blocks must be an array")
	}

	userIDStr, ok := noteData["user_id"].(string)
	if !ok {
		return models.Note{}, errors.New("user_id must be a string")
	}
	
	// Get content data from the first block
	blockData := blocks[0].(map[string]interface{})
	var blockContent models.BlockContent
	
	// Handle different content formats
	switch c := blockData["content"].(type) {
	case map[string]interface{}:
		blockContent = c
	case string:
		blockContent = models.BlockContent{"text": c}
	default:
		blockContent = models.BlockContent{"text": "Default content"}
	}

	return models.Note{
		ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
		Title: title,
		Blocks: []models.Block{{
			ID:      uuid.New(),
			Type:    models.TextBlock,
			Content: blockContent,
			Order:   1,
		}},
		UserID: uuid.Must(uuid.Parse(userIDStr)),
	}, nil
}

func (m *MockNoteService) GetNoteById(db *database.Database, id string) (models.Note, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Note{
			ID:    uuid.Must(uuid.Parse(id)),
			Title: "Test Note",
			Blocks: []models.Block{{
				ID:      uuid.New(),
				Type:    models.TextBlock,
				Content: models.BlockContent{"text": "This is a test note."},
				Order:   1,
			}},
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		}, nil
	}
	return models.Note{}, services.ErrNoteNotFound
}

func (m *MockNoteService) UpdateNote(db *database.Database, id string, updatedData map[string]interface{}) (models.Note, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		blocks := updatedData["blocks"].([]interface{})
		blockData := blocks[0].(map[string]interface{})
		
		// Handle different content formats
		var blockContent models.BlockContent
		switch c := blockData["content"].(type) {
		case map[string]interface{}:
			blockContent = c
		case string:
			blockContent = models.BlockContent{"text": c}
		default:
			blockContent = models.BlockContent{"text": "Default content"}
		}
		
		return models.Note{
			ID:    uuid.Must(uuid.Parse(id)),
			Title: updatedData["title"].(string),
			Blocks: []models.Block{{
				ID:      uuid.New(),
				Type:    models.TextBlock,
				Content: blockContent,
				Order:   1,
			}},
			UserID: uuid.Must(uuid.Parse(updatedData["user_id"].(string))),
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
			{
				ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
				Title: "Test Note",
				Blocks: []models.Block{{
					ID:      uuid.New(),
					Type:    models.TextBlock,
					Content: models.BlockContent{"text": "This is a test note."},
					Order:   1,
				}},
				UserID: uuid.Must(uuid.Parse(userID)),
			},
		}, nil
	}
	return []models.Note{}, nil
}

func (m *MockNoteService) GetAllNotes(db *database.Database) ([]models.Note, error) {
	return []models.Note{
		{
			ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
			Title: "Test Note",
			Blocks: []models.Block{{
				ID:      uuid.New(),
				Type:    models.TextBlock,
				Content: models.BlockContent{"text": "This is a test note"},
				Order:   1,
			}},
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
		{
			ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")),
			Title: "Test Note 2",
			Blocks: []models.Block{{
				ID:      uuid.New(),
				Type:    models.TextBlock,
				Content: models.BlockContent{"text": "This is another test note"},
				Order:   1,
			}},
			UserID: uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
		},
	}, nil
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
		req, _ := http.NewRequest("POST", "/api/v1/notes/", bytes.NewBuffer([]byte(`{"blocks":[{"type":"text","content":"Test Content","order":1}], "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		services.NoteServiceInstance = mockService
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("Valid JSON with String Content", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notes/", bytes.NewBuffer([]byte(`{
			"title":"Test Note",
			"blocks":[{"type":"text","content":"Test Content","order":1}],
			"user_id":"90a12345-f12a-98c4-a456-513432930000"
		}`)))
		services.NoteServiceInstance = mockService
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})
	
	t.Run("Valid JSON with Structured Content", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/notes/", bytes.NewBuffer([]byte(`{
			"title":"Test Note",
			"blocks":[{
				"type":"text",
				"content":{"text":"Test Content", "format":"markdown"},
				"order":1
			}],
			"user_id":"90a12345-f12a-98c4-a456-513432930000"
		}`)))
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
		req, _ := http.NewRequest("PUT", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174001", bytes.NewBuffer([]byte(`{"title":"Updated Note", "blocks":[{"type":"text","content":"Updated Content","order":1}], "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Note Updated", func(t *testing.T) {

		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/notes/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte(`{"title":"Updated Note", "blocks":[{"type":"text","content":"Updated Content","order":1}], "user_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
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

func TestGetAllNotes(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNoteService{}
	RegisterNoteRoutes(router, db, mockService)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/notes/", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "Test Note")
	assert.Contains(t, w.Body.String(), "Test Note 2")
}

// Add new test for notes with query parameters
func TestGetNotes(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockNoteService{}
	RegisterNoteRoutes(router, db, mockService)

	t.Run("Get Notes With No Filters", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notes/", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Note")
		assert.Contains(t, w.Body.String(), "Test Note 2")
	})

	t.Run("Get Notes By User ID", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notes/?user_id=90a12345-f12a-98c4-a456-513432930000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Note")
	})

	t.Run("Get Notes By Title", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/notes/?title=Test Note", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Note")
	})
}
