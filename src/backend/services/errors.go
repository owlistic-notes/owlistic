package services

import (
	"errors"
)

// Common errors
var (
	// General errors
	ErrNotFound       = errors.New("resource not found")
	ErrInvalidInput   = errors.New("invalid input")
	ErrInternal       = errors.New("internal server error")
	ErrResourceExists = errors.New("resource already exists")
	ErrValidation     = errors.New("validation error")

	// Authentication/authorization errors
	ErrInvalidCredentials = errors.New("invalid email or password")
	ErrInvalidToken       = errors.New("invalid or expired token")
	ErrUnauthorized       = errors.New("unauthorized")

	// Resource-specific errors
	ErrUserNotFound      = errors.New("user not found")
	ErrNoteNotFound      = errors.New("note not found")
	ErrBlockNotFound     = errors.New("block not found")
	ErrNotebookNotFound  = errors.New("notebook not found")
	ErrTaskNotFound      = errors.New("task not found")
	ErrEventNotFound     = errors.New("event not found")
	ErrUserAlreadyExists = errors.New("user with that email already exists")

	// Type errors
	ErrInvalidBlockType = errors.New("invalid block type")

	// Connection errors
	ErrWebSocketConnection = errors.New("websocket connection error")
)
