package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// User represents the user entity stored in the database
type User struct {
	ID           uuid.UUID              `gorm:"type:uuid;primaryKey;default:gen_random_uuid()" json:"id"`
	Email        string                 `gorm:"unique;not null" json:"email"`
	PasswordHash string                 `json:"-"` // Password hash is never exposed in JSON
	Username     string                 `gorm:"unique" json:"username"`
	DisplayName  string                 `json:"display_name"`
	ProfilePic   string                 `json:"profile_pic"`
	Preferences  map[string]interface{} `gorm:"type:jsonb" json:"preferences"`
	CreatedAt    time.Time              `gorm:"not null;default:now()" json:"created_at"`
	UpdatedAt    time.Time              `gorm:"not null;default:now()" json:"updated_at"`
	DeletedAt    gorm.DeletedAt         `gorm:"index" json:"deleted_at,omitempty"`
}

// UserRegistrationInput represents data needed for registration
type UserRegistrationInput struct {
	Email       string                 `json:"email" binding:"required,email"`
	Password    string                 `json:"password" binding:"required"`
	Username    string                 `json:"username"`
	DisplayName string                 `json:"display_name"`
	ProfilePic  string                 `json:"profile_pic"`
	Preferences map[string]interface{} `json:"preferences"`
}

// UserLoginInput represents data needed for login
type UserLoginInput struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

// UserUpdateInput represents data for updating user account details
type UserUpdateInput struct {
	Email       string                 `json:"email"`
	Password    string                 `json:"password"`
	Username    string                 `json:"username"`
	DisplayName string                 `json:"display_name"`
	ProfilePic  string                 `json:"profile_pic"`
	Preferences map[string]interface{} `json:"preferences"`
}

// UserPasswordUpdateInput is specifically for password changes
type UserPasswordUpdateInput struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	NewPassword     string `json:"new_password" binding:"required"`
}

// UserProfile represents the subset of User information
// that can be safely updated through the profile endpoints
type UserProfile struct {
	Username    string                 `json:"username"`
	DisplayName string                 `json:"display_name"`
	ProfilePic  string                 `json:"profile_pic"`
	Preferences map[string]interface{} `json:"preferences"`
}
