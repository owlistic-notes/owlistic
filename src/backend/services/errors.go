package services

import "errors"

var ErrNotFound = errors.New("resource not found")

var ErrUserNotFound = errors.New("user not found")
var ErrTaskNotFound = errors.New("task not found")
var ErrNoteNotFound = errors.New("note not found")
var ErrNotebookNotFound = errors.New("notebook not found")

var ErrInvalidInput = errors.New("invalid input")

var ErrBlockNotFound = errors.New("block not found")
var ErrInvalidBlockType = errors.New("invalid block type")
var ErrInvalidBlockOrder = errors.New("invalid block order")
var ErrInvalidUUID = errors.New("invalid UUID")
