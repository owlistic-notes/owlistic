package models

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestNoteToJSON(t *testing.T) {
	note := Note{
		ID:        uuid.New(),
		UserID:    uuid.New(),
		Title:     "Test Title",
		Content:   "Test Content",
		Tags:      []string{"tag1", "tag2"},
		IsDeleted: false,
	}

	data, err := note.ToJSON()
	assert.NoError(t, err)

	var result Note
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, note, result)
}

func TestNoteFromJSON(t *testing.T) {
	data := `{
		"id": "550e8400-e29b-41d4-a716-446655440000",
		"user_id": "550e8400-e29b-41d4-a716-446655440001",
		"title": "Test Title",
		"content": "Test Content",
		"tags": ["tag1", "tag2"],
		"is_deleted": false
	}`

	var note Note
	err := note.FromJSON([]byte(data))
	assert.NoError(t, err)
	assert.Equal(t, "Test Title", note.Title)
	assert.Equal(t, "Test Content", note.Content)
	assert.Equal(t, []string{"tag1", "tag2"}, note.Tags)
}
