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

type MockBlockService struct{}

// Add GetBlocks method for query parameter support
func (m *MockBlockService) GetBlocks(db *database.Database, params map[string]interface{}) ([]models.Block, error) {
	noteID, hasNoteID := params["note_id"].(string)
	blockType, hasBlockType := params["type"].(string)

	if hasNoteID && noteID == "90a12345-f12a-98c4-a456-513432930000" {
		blocks := []models.Block{
			{
				ID:      uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
				NoteID:  uuid.Must(uuid.Parse(noteID)),
				Type:    models.TextBlock,
				Content: models.BlockContent{"text": "Test Content"},
				Order:   1,
			},
		}

		// Apply type filter if needed
		if hasBlockType && blockType != "" {
			var filteredBlocks []models.Block
			for _, block := range blocks {
				if string(block.Type) == blockType {
					filteredBlocks = append(filteredBlocks, block)
				}
			}
			return filteredBlocks, nil
		}

		return blocks, nil
	}

	return []models.Block{}, nil
}

func (m *MockBlockService) CreateBlock(db *database.Database, blockData map[string]interface{}) (models.Block, error) {
	content, ok := blockData["content"]
	if !ok {
		return models.Block{}, errors.New("content is required")
	}

	noteIDStr, ok := blockData["note_id"].(string)
	if !ok {
		return models.Block{}, errors.New("note_id must be a string")
	}

	// Handle different content formats while preserving the service interface
	var blockContent models.BlockContent
	switch c := content.(type) {
	case map[string]interface{}:
		blockContent = c
	case string:
		blockContent = models.BlockContent{"text": c}
	default:
		return models.Block{}, errors.New("invalid content format")
	}

	return models.Block{
		ID:      uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
		NoteID:  uuid.Must(uuid.Parse(noteIDStr)),
		Type:    models.TextBlock,
		Content: blockContent,
		Order:   1,
	}, nil
}

func (m *MockBlockService) GetBlockById(db *database.Database, id string) (models.Block, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.Block{
			ID:      uuid.Must(uuid.Parse(id)),
			NoteID:  uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
			Type:    models.TextBlock,
			Content: models.BlockContent{"text": "Test Content"},
			Order:   1,
		}, nil
	}
	return models.Block{}, services.ErrBlockNotFound
}

func (m *MockBlockService) UpdateBlock(db *database.Database, id string, blockData map[string]interface{}) (models.Block, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		// Handle content updates
		var content models.BlockContent
		if c, ok := blockData["content"]; ok {
			switch typedContent := c.(type) {
			case map[string]interface{}:
				content = typedContent
			case string:
				// Maintain backward compatibility with string content
				content = models.BlockContent{"text": typedContent}
			default:
				return models.Block{}, errors.New("invalid content format")
			}
		}

		return models.Block{
			ID:      uuid.Must(uuid.Parse(id)),
			NoteID:  uuid.Must(uuid.Parse("90a12345-f12a-98c4-a456-513432930000")),
			Content: content,
			Type:    models.TextBlock,
			Order:   1,
		}, nil
	}
	return models.Block{}, services.ErrBlockNotFound
}

func (m *MockBlockService) DeleteBlock(db *database.Database, id string) error {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return nil
	}
	return services.ErrBlockNotFound
}

func (m *MockBlockService) ListBlocksByNote(db *database.Database, noteID string) ([]models.Block, error) {
	if noteID == "90a12345-f12a-98c4-a456-513432930000" {
		return []models.Block{
			{
				ID:      uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
				NoteID:  uuid.Must(uuid.Parse(noteID)),
				Type:    models.TextBlock,
				Content: models.BlockContent{"text": "Test Content"},
				Order:   1,
			},
		}, nil
	}
	return []models.Block{}, nil
}

func TestCreateBlock(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockBlockService{}
	RegisterBlockRoutes(router, db, mockService)

	t.Run("Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/blocks/", bytes.NewBuffer([]byte("invalid json")))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("Missing Content", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/blocks/", bytes.NewBuffer([]byte(`{"note_id":"90a12345-f12a-98c4-a456-513432930000"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusInternalServerError, w.Code)
	})

	t.Run("Valid Block with String Content", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/blocks/", bytes.NewBuffer([]byte(`{
			"note_id": "90a12345-f12a-98c4-a456-513432930000",
			"type": "text",
			"content": "Test Content",
			"order": 1
		}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})

	t.Run("Valid Block with Structured Content", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/blocks/", bytes.NewBuffer([]byte(`{
			"note_id": "90a12345-f12a-98c4-a456-513432930000",
			"type": "text",
			"content": {
				"text": "Test Content",
				"format": "markdown"
			},
			"order": 1
		}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})

	// Add a test specifically for backward compatibility with string content
	t.Run("Backward Compatibility with String Content", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/blocks/", bytes.NewBuffer([]byte(`{
			"note_id": "90a12345-f12a-98c4-a456-513432930000",
			"type": "text",
			"content": "Plain old string content",
			"order": 1
		}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
		// Verify that response includes the content in the new format
		assert.Contains(t, w.Body.String(), `{"text":"Plain old string content"}`)
	})
}

func TestGetBlockById(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockBlockService{}
	RegisterBlockRoutes(router, db, mockService)

	t.Run("Block Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/blocks/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Block Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/blocks/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestUpdateBlock(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockBlockService{}
	RegisterBlockRoutes(router, db, mockService)

	t.Run("Block Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/blocks/123e4567-e89b-12d3-a456-426614174001", bytes.NewBuffer([]byte(`{"content":"Updated Content"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Block Updated", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/blocks/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte(`{"content":"Updated Content"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestDeleteBlock(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockBlockService{}
	RegisterBlockRoutes(router, db, mockService)

	t.Run("Block Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/blocks/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("Block Deleted", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/blocks/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNoContent, w.Code)
	})
}

func TestListBlocksByNote(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockBlockService{}
	RegisterBlockRoutes(router, db, mockService)

	t.Run("No Blocks Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/blocks/note/90a12345-f12a-98c4-a456-513432930001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "[]")
	})

	t.Run("Blocks Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/blocks/note/90a12345-f12a-98c4-a456-513432930000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Content")
	})
}

// Add new test for blocks with query parameters
func TestGetBlocks(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockBlockService{}
	RegisterBlockRoutes(router, db, mockService)

	t.Run("Get Blocks With No Filters", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/blocks/", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})

	t.Run("Get Blocks By Note ID", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/blocks/?note_id=90a12345-f12a-98c4-a456-513432930000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Content")
	})

	t.Run("Get Blocks By Type", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/blocks/?type=text&note_id=90a12345-f12a-98c4-a456-513432930000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "Test Content")
	})
}
