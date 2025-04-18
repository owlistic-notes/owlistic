package models

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestNotebookToJSON(t *testing.T) {
	notebook := Notebook{
		ID:          uuid.New(),
		UserID:      uuid.New(),
		Name:        "Test Notebook",
		Description: "Test Description",
		IsDeleted:   false,
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
		Notes:       []Note{},
	}

	data, err := notebook.ToJSON()
	assert.NoError(t, err)

	var result Notebook
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, notebook.ID, result.ID)
	assert.Equal(t, notebook.UserID, result.UserID)
	assert.Equal(t, notebook.Name, result.Name)
	assert.Equal(t, notebook.Description, result.Description)
	assert.Equal(t, notebook.IsDeleted, result.IsDeleted)
}

func TestNotebookFromJSON(t *testing.T) {
	data := `{
		"id": "550e8400-e89b-41d4-a716-446655440000",
		"user_id": "550e8400-e89b-41d4-a716-446655440001",
		"name": "Test Notebook",
		"description": "Test Description",
		"is_deleted": false,
		"notes": []
	}`

	var notebook Notebook
	err := notebook.FromJSON([]byte(data))
	assert.NoError(t, err)
	assert.Equal(t, "Test Notebook", notebook.Name)
	assert.Equal(t, "Test Description", notebook.Description)
	assert.Equal(t, false, notebook.IsDeleted)
	assert.Equal(t, "550e8400-e89b-41d4-a716-446655440000", notebook.ID.String())
	assert.Equal(t, "550e8400-e89b-41d4-a716-446655440001", notebook.UserID.String())
}

func TestNotebookWithNotes(t *testing.T) {
	block := Block{
		ID:      uuid.New(),
		Type:    TextBlock,
		Content: BlockContent{"text": "Test Content"},
		Order:   1,
	}

	note := Note{
		ID:         uuid.New(),
		UserID:     uuid.New(),
		NotebookID: uuid.New(),
		Title:      "Test Note",
		Blocks:     []Block{block},
		IsDeleted:  false,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}

	notebook := Notebook{
		ID:          uuid.New(),
		UserID:      uuid.New(),
		Name:        "Test Notebook",
		Description: "Test Description",
		Notes:       []Note{note},
		IsDeleted:   false,
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}

	data, err := notebook.ToJSON()
	assert.NoError(t, err)

	var result Notebook
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, 1, len(result.Notes))
	assert.Equal(t, note.Title, result.Notes[0].Title)
	assert.Equal(t, 1, len(result.Notes[0].Blocks))
	assert.Equal(t, "Test Content", result.Notes[0].Blocks[0].Content["text"])
}
