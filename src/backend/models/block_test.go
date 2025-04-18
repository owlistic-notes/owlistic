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
		Content:  BlockContent{"text": "Test Content"},
		Metadata: BlockContent{"format": "markdown"},
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
	assert.Equal(t, "Test Content", result.Content["text"])
	assert.Equal(t, "markdown", result.Metadata["format"])
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
		Content: BlockContent{"text": "Task Block"},
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

func TestBlockContentSerialization(t *testing.T) {
	// Test empty BlockContent
	empty := BlockContent{}
	emptyVal, err := empty.Value()
	assert.NoError(t, err)
	assert.Equal(t, "{}", string(emptyVal.([]byte)))

	// Test complex BlockContent
	content := BlockContent{
		"text":   "Sample text",
		"format": "markdown",
		"nested": map[string]interface{}{
			"key":  "value",
			"list": []string{"item1", "item2"},
		},
	}

	val, err := content.Value()
	assert.NoError(t, err)

	var scanned BlockContent
	err = scanned.Scan(val)
	assert.NoError(t, err)

	assert.Equal(t, "Sample text", scanned["text"])
	assert.Equal(t, "markdown", scanned["format"])

	nested := scanned["nested"].(map[string]interface{})
	assert.Equal(t, "value", nested["key"])
}
