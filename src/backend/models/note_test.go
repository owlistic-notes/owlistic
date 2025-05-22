package models

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestNoteToJSON(t *testing.T) {
	note := Note{
		ID:         uuid.New(),
		UserID:     uuid.New(),
		NotebookID: uuid.New(),
		Title:      "Test Title",
		Blocks: []Block{
			{
				ID:      uuid.New(),
				Type:    TextBlock,
				Content: BlockContent{"text": "Test Content"},
				Order:   1,
			},
		},
	}

	data, err := note.ToJSON()
	assert.NoError(t, err)

	var result Note
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, note.ID, result.ID)
	assert.Equal(t, note.Title, result.Title)
	assert.Equal(t, len(note.Blocks), len(result.Blocks))
	assert.Equal(t, "Test Content", result.Blocks[0].Content["text"])
}

func TestNoteFromJSON(t *testing.T) {
	blockID := uuid.New()
	data := `{
		"id": "550e8400-e29b-41d4-a716-446655440000",
		"user_id": "550e8400-e29b-41d4-a716-446655440001",
		"notebook_id": "550e8400-e29b-41d4-a716-446655440002",
		"title": "Test Title",
		"blocks": [{
			"id": "` + blockID.String() + `",
			"type": "text",
			"content": {"text": "Test Content"},
			"order": 1
		}],
	}`

	var note Note
	err := note.FromJSON([]byte(data))
	assert.NoError(t, err)
	assert.Equal(t, "Test Title", note.Title)
	assert.Equal(t, 1, len(note.Blocks))
	assert.Equal(t, "Test Content", note.Blocks[0].Content["text"])
}
