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
	TextBlock      BlockType = "text"
	HeadingBlock   BlockType = "heading"
	ChecklistBlock BlockType = "checklist"
	CodeBlock      BlockType = "code"
	ImageBlock     BlockType = "image"
	TaskBlock      BlockType = "task"
)

// BlockContent stores the structured content of a block
type BlockContent map[string]interface{}

// InlineStyle represents a formatting span within block text
type InlineStyle struct {
	Type  string `json:"type"`
	Start int    `json:"start"`
	End   int    `json:"end"`
	Href  string `json:"href,omitempty"` // For link styles
}

// StyleOptions defines the styling configuration for a block's content
type StyleOptions struct {
	RawMarkdown    string        `json:"raw_markdown,omitempty"`    // Original markdown text
	InlineStyles   []InlineStyle `json:"styles,omitempty"`          // Extracted style information
	PreserveFormat bool          `json:"preserve_format,omitempty"` // Whether to preserve formatting in storage
}

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
	ID        uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID    uuid.UUID      `gorm:"type:uuid;not null;constraint:OnDelete:CASCADE;" json:"user_id"`
	NoteID    uuid.UUID      `gorm:"type:uuid;not null;constraint:OnDelete:CASCADE;" json:"note_id"`
	Type      BlockType      `gorm:"type:varchar(20);not null" json:"type"`
	Content   BlockContent   `gorm:"type:jsonb;not null;default:'{}'::jsonb" json:"content"`
	Metadata  BlockContent   `gorm:"type:jsonb;default:'{}'::jsonb" json:"metadata,omitempty"`
	Tasks     []Task         `gorm:"foreignKey:BlockID" json:"tasks,omitempty"`
	Order     float64        `gorm:"not null" json:"order"` // Changed from int to float64
	CreatedAt time.Time      `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt time.Time      `gorm:"not null;default:now()" json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
}

// GetInlineStyles returns the block's inline style information
func (b *Block) GetInlineStyles() []InlineStyle {
	if b.Content == nil {
		return nil
	}

	// Try getting styles directly from the content map
	if spans, ok := b.Content["spans"].([]interface{}); ok {
		styles := make([]InlineStyle, 0, len(spans))
		for _, span := range spans {
			if spanMap, ok := span.(map[string]interface{}); ok {
				style := InlineStyle{}

				if t, ok := spanMap["type"].(string); ok {
					style.Type = t
				}

				if start, ok := spanMap["start"].(float64); ok {
					style.Start = int(start)
				}

				if end, ok := spanMap["end"].(float64); ok {
					style.End = int(end)
				}

				if href, ok := spanMap["href"].(string); ok {
					style.Href = href
				}

				styles = append(styles, style)
			}
		}
		return styles
	}

	return nil
}
