package models

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// TaskMetadata stores additional information about a task
type TaskMetadata map[string]interface{}

// Value implements the driver.Valuer interface for JSONB storage
func (tm TaskMetadata) Value() (driver.Value, error) {
	if tm == nil {
		return nil, nil
	}
	return json.Marshal(tm)
}

// Scan implements the sql.Scanner interface for JSONB retrieval
func (tm *TaskMetadata) Scan(value interface{}) error {
	if value == nil {
		*tm = make(TaskMetadata)
		return nil
	}

	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("type assertion to []byte failed")
	}

	return json.Unmarshal(bytes, tm)
}

type Task struct {
	ID          uuid.UUID      `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	UserID      uuid.UUID      `gorm:"type:uuid;not null;constraint:OnDelete:CASCADE;" json:"user_id"`
	BlockID     uuid.UUID      `gorm:"type:uuid;constraint:OnDelete:CASCADE;" json:"block_id"`
	Title       string         `gorm:"not null" json:"title"`
	Description string         `json:"description"`
	IsCompleted bool           `gorm:"default:false" json:"is_completed"`
	DueDate     string         `json:"due_date"`
	Metadata    TaskMetadata   `gorm:"type:jsonb;default:'{}'::jsonb" json:"metadata,omitempty"`
	CreatedAt   time.Time      `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt   time.Time      `gorm:"not null;default:now()" json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
}
