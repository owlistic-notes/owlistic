package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type Note struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()"`
	UserID     uuid.UUID `gorm:"type:uuid;not null"`
	Title      string    `gorm:"not null"`
	Content    string
	Tags       []string  `gorm:"type:text[]"`
	IsDeleted  bool      `gorm:"default:false"`
	CreatedAt  time.Time `gorm:"autoCreateTime"`
	UpdatedAt  time.Time `gorm:"autoUpdateTime"`
	UpdateDate string    `gorm:"not null;default:CURRENT_TIMESTAMP"`
}

func (n *Note) FromJSON(data []byte) error {
	return json.Unmarshal(data, n)
}

func (n *Note) ToJSON() ([]byte, error) {
	return json.Marshal(n)
}
