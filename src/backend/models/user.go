package models

import (
	"github.com/google/uuid"
)

type User struct {
	ID           uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	Email        string    `gorm:"unique;not null"`
	PasswordHash string
	CreatedAt    string `gorm:"autoCreateTime"`
	UpdatedAt    string `gorm:"autoUpdateTime"`
	UpdateDate   string `gorm:"not null;default:CURRENT_TIMESTAMP"`
}
