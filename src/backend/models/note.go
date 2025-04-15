package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type Note struct {
	ID         uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID     uuid.UUID `gorm:"type:uuid;not null" json:"user_id"`
	NotebookID uuid.UUID `gorm:"type:uuid;not null" json:"notebook_id"`
	Title      string    `gorm:"not null" json:"title"`
	Blocks     []Block   `gorm:"foreignKey:NoteID" json:"blocks"`
	Tags       []string  `gorm:"type:text[]" json:"tags"`
	IsDeleted  bool      `gorm:"default:false" json:"is_deleted"`
	CreatedAt  time.Time `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt  time.Time `gorm:"not null;default:now()" json:"updated_at"`
}

func (n *Note) FromJSON(data []byte) error {
	return json.Unmarshal(data, n)
}

func (n *Note) ToJSON() ([]byte, error) {
	return json.Marshal(n)
}
