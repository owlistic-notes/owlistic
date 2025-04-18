package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
)

type BlockType string

const (
	TextBlock      BlockType = "text"
	HeadingBlock   BlockType = "heading"
	ChecklistBlock BlockType = "checklist"
	CodeBlock      BlockType = "code"
	ImageBlock     BlockType = "image"
	TaskBlock      BlockType = "task"
)

// BlockContent stores the structured content of a block
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

// Block represents a content block within a note
type Block struct {
	ID        uuid.UUID    `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	NoteID    uuid.UUID    `gorm:"type:uuid;not null;constraint:OnDelete:CASCADE;" json:"note_id"`
	Type      BlockType    `gorm:"type:varchar(20);not null" json:"type"`
	Content   BlockContent `gorm:"type:jsonb;not null;default:'{}'::jsonb" json:"content"`
	Metadata  BlockContent `gorm:"type:jsonb;default:'{}'::jsonb" json:"metadata,omitempty"`
	Tasks     []Task       `gorm:"foreignKey:BlockID" json:"tasks,omitempty"`
	Order     int          `gorm:"not null" json:"order"`
	CreatedAt time.Time    `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt time.Time    `gorm:"not null;default:now()" json:"updated_at"`
}
