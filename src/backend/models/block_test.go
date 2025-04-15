package models

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
)

func TestBlockJSON(t *testing.T) {
	block := Block{
		ID:       uuid.New(),
		NoteID:   uuid.New(),
		Type:     TextBlock,
		Content:  "Test Content",
		Metadata: `{"key": "value"}`,
		Order:    1,
		Tasks:    []Task{},
	}

	data, err := json.Marshal(block)
	assert.NoError(t, err)

	var result Block
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, block.ID, result.ID)
	assert.Equal(t, block.Type, result.Type)
	assert.Equal(t, block.Content, result.Content)
	assert.Equal(t, block.Metadata, result.Metadata)
	assert.Equal(t, block.Order, result.Order)
}

func TestBlockWithTasks(t *testing.T) {
	task := Task{
		ID:          uuid.New(),
		UserID:      uuid.New(),
		BlockID:     uuid.New(),
		Title:       "Test Task",
		Description: "Test Description",
	}

	block := Block{
		ID:      uuid.New(),
		NoteID:  uuid.New(),
		Type:    TaskBlock,
		Content: "Task Block",
		Tasks:   []Task{task},
		Order:   1,
	}

	data, err := json.Marshal(block)
	assert.NoError(t, err)

	var result Block
	err = json.Unmarshal(data, &result)
	assert.NoError(t, err)
	assert.Equal(t, 1, len(result.Tasks))
	assert.Equal(t, task.Title, result.Tasks[0].Title)
}
