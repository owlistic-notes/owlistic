package services

import "errors"

// Common errors
var (
	ErrNotFound            = errors.New("resource not found")
	ErrUserNotFound        = errors.New("user not found")
	ErrNoteNotFound        = errors.New("note not found")
	ErrBlockNotFound       = errors.New("block not found")
	ErrNotebookNotFound    = errors.New("notebook not found")
	ErrTaskNotFound        = errors.New("task not found")
	ErrInvalidBlockType    = errors.New("invalid block type")
	ErrInvalidInput        = errors.New("invalid input")
	ErrInvalidCredentials  = errors.New("invalid credentials")
	ErrInvalidToken        = errors.New("invalid token")
	ErrUnauthorized        = errors.New("unauthorized")
	ErrInternal            = errors.New("internal server error")
	ErrResourceExists      = errors.New("resource already exists")
	ErrEventNotFound       = errors.New("event not found")
	ErrValidation          = errors.New("validation error")
	ErrWebSocketConnection = errors.New("websocket connection error")
)
