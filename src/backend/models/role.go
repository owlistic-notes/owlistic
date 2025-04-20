package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// RoleType represents the type of role (Admin, Owner, Editor, Viewer)
type RoleType string

// Role types
const (
	AdminRole  RoleType = "admin"  // Can access and modify everything
	OwnerRole  RoleType = "owner"  // Full access to a specific resource
	EditorRole RoleType = "editor" // Can edit but not delete
	ViewerRole RoleType = "viewer" // Read-only access
)

// ResourceType represents the type of resource for RBAC
type ResourceType string

// ResourceTypes
const (
	UserResource     ResourceType = "user"
	NoteResource     ResourceType = "note"
	NotebookResource ResourceType = "notebook"
	BlockResource    ResourceType = "block"
	TaskResource     ResourceType = "task"
)

// Role represents a role assignment for a user on a specific resource
type Role struct {
	ID           uuid.UUID      `gorm:"type:uuid;primary_key" json:"id"`
	UserID       uuid.UUID      `gorm:"type:uuid;not null" json:"user_id"`
	User         *User          `gorm:"foreignKey:UserID" json:"-"`
	ResourceID   uuid.UUID      `gorm:"type:uuid;not null" json:"resource_id"`
	ResourceType ResourceType   `gorm:"type:varchar(50);not null" json:"resource_type"`
	Role         RoleType       `gorm:"type:varchar(50);not null" json:"role"`
	CreatedAt    time.Time      `json:"created_at"`
	UpdatedAt    time.Time      `json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"deleted_at,omitempty"`
}

// BeforeCreate is a GORM hook that runs before creating a new role
func (r *Role) BeforeCreate(tx *gorm.DB) (err error) {
	if r.ID == uuid.Nil {
		r.ID = uuid.New()
	}
	return nil
}
