package services

import "errors"

var ErrNotFound = errors.New("resource not found")

var ErrUserNotFound = errors.New("user not found")
var ErrTaskNotFound = errors.New("task not found")
var ErrNoteNotFound = errors.New("note not found")

var ErrInvalidInput = errors.New("invalid input")
