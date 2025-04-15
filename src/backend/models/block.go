package models

import (
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

type Block struct {
	ID        uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	NoteID    uuid.UUID `gorm:"type:uuid;not null;constraint:OnDelete:CASCADE;" json:"note_id"`
	Type      BlockType `gorm:"type:varchar(20);not null" json:"type"`
	Content   string    `gorm:"not null" json:"content"`
	Metadata  string    `gorm:"type:jsonb;default:{}" json:"metadata,omitempty"`
	Tasks     []Task    `gorm:"foreignKey:BlockID" json:"tasks,omitempty"`
	Order     int       `gorm:"not null" json:"order"`
	CreatedAt time.Time `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt time.Time `gorm:"not null;default:now()" json:"updated_at"`
}
