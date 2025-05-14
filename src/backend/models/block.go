package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type BlockType string

const (
	TextBlock    BlockType = "text"
	TaskBlock    BlockType = "task"
	HeadingBlock BlockType = "heading"
)

type BlockContent map[string]interface{}

// Value implements the driver.Valuer interface for JSONB storage
func (bc BlockContent) Value() (driver.Value, error) {
	if bc == nil {
		return nil, nil
	}
	return json.Marshal(bc)
}

// Scan implements the sql.Scanner interface for JSONB retrieval
func (bc *BlockContent) Scan(value interface{}) error {
	if value == nil {
		*bc = make(BlockContent)
		return nil
	}

	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed")
	}

	return json.Unmarshal(bytes, bc)
}

// BlockMetadata stores flexible metadata specific to each block type
type BlockMetadata map[string]interface{}

// Value implements the driver.Valuer interface for JSONB storage
func (bm BlockMetadata) Value() (driver.Value, error) {
	if bm == nil {
		return nil, nil
	}
	return json.Marshal(bm)
}

// Scan implements the sql.Scanner interface for JSONB retrieval
func (bm *BlockMetadata) Scan(value interface{}) error {
	if value == nil {
		*bm = make(BlockMetadata)
		return nil
	}

	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed")
	}

	return json.Unmarshal(bytes, bm)
}

// Block represents a content block within a note
type Block struct {
	ID        uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID    uuid.UUID      `gorm:"type:uuid;not null;constraint:OnDelete:CASCADE;" json:"user_id"`
	NoteID    uuid.UUID      `gorm:"type:uuid;not null;constraint:OnDelete:CASCADE;" json:"note_id"`
	Type      BlockType      `gorm:"type:varchar(20);not null" json:"type"`
	Content   BlockContent   `gorm:"type:jsonb;default:'{}'::jsonb" json:"content"`
	Metadata  BlockMetadata  `gorm:"type:jsonb;default:'{}'::jsonb" json:"metadata"`
	Order     float64        `gorm:"not null" json:"order"`
	CreatedAt time.Time      `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt time.Time      `gorm:"not null;default:now()" json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
}

// GetHeadingLevel returns the heading level (for heading blocks)
func (b *Block) GetHeadingLevel() int {
	if b.Type != HeadingBlock {
		return 0
	}

	if level, ok := b.Metadata["level"].(float64); ok {
		return int(level)
	}
	return 1 // Default heading level
}

// GetSpans returns formatting spans from metadata
func (b *Block) GetSpans() []map[string]interface{} {
	if spans, ok := b.Metadata["spans"].([]interface{}); ok {
		result := make([]map[string]interface{}, 0, len(spans))
		for _, span := range spans {
			if spanMap, ok := span.(map[string]interface{}); ok {
				result = append(result, spanMap)
			}
		}
		return result
	}
	return nil
}

// IsTaskCompleted returns whether a task is completed (for task blocks)
func (b *Block) IsTaskCompleted() bool {
	if b.Type != TaskBlock {
		return false
	}

	if completed, ok := b.Metadata["is_completed"].(bool); ok {
		return completed
	}
	return false
}

// GetTaskID returns the associated task ID (for task blocks)
func (b *Block) GetTaskID() string {
	if b.Type != TaskBlock {
		return ""
	}

	if taskID, ok := b.Metadata["task_id"].(string); ok {
		return taskID
	}
	return ""
}
