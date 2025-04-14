package models

import (
	"github.com/google/uuid"
)

type Task struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	UserID      uuid.UUID `gorm:"type:uuid;not null"`
	NoteID      *uuid.UUID
	Title       string `gorm:"not null"`
	Description string `gorm:"not null"`
	IsCompleted bool   `gorm:"default:false"`
	DueDate     string
	CreatedAt   string `gorm:"autoCreateTime"`
	UpdatedAt   string `gorm:"autoUpdateTime"`
	UpdateDate  string `gorm:"not null;default:CURRENT_TIMESTAMP"`
}
