package models

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

type Notebook struct {
	ID          uuid.UUID `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID      uuid.UUID `gorm:"type:uuid;not null" json:"user_id"`
	Name        string    `gorm:"not null" json:"name"`
	Description string    `json:"description"`
	Notes       []Note    `gorm:"foreignKey:NotebookID" json:"notes"`
	IsDeleted   bool      `gorm:"default:false" json:"is_deleted"`
	CreatedAt   time.Time `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt   time.Time `gorm:"not null;default:now()" json:"updated_at"`
}

func (nb *Notebook) FromJSON(data []byte) error {
	return json.Unmarshal(data, nb)
}

func (nb *Notebook) ToJSON() ([]byte, error) {
	return json.Marshal(nb)
}
