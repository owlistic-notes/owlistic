package services

import (
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

type TrashServiceInterface interface {
	GetTrashedItems(db *database.Database, userID string) (map[string]interface{}, error)
	RestoreItem(db *database.Database, itemType string, itemID string, userID string) error
	PermanentlyDeleteItem(db *database.Database, itemType string, itemID string, userID string) error
	EmptyTrash(db *database.Database, userID string) error
}

type TrashService struct{}

func (s *TrashService) GetTrashedItems(db *database.Database, userID string) (map[string]interface{}, error) {
	result := make(map[string]interface{})

	// Get trashed notes
	var trashedNotes []models.Note
	if err := db.DB.Unscoped().Where("user_id = ? AND deleted_at IS NOT NULL", userID).Find(&trashedNotes).Error; err != nil {
		return nil, err
	}

	// Get trashed notebooks
	var trashedNotebooks []models.Notebook
	if err := db.DB.Unscoped().Where("user_id = ? AND deleted_at IS NOT NULL", userID).Find(&trashedNotebooks).Error; err != nil {
		return nil, err
	}

	result["notes"] = trashedNotes
	result["notebooks"] = trashedNotebooks

	return result, nil
}

func (s *TrashService) RestoreItem(db *database.Database, itemType string, itemID string, userID string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	var eventData map[string]interface{}
	var err error

	switch itemType {
	case "note":
		// Update the note to remove the deleted_at timestamp
		if err = tx.Exec("UPDATE notes SET deleted_at = NULL WHERE id = ? AND user_id = ?", itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Also restore any blocks that were associated with this note
		if err = tx.Exec("UPDATE blocks SET deleted_at = NULL WHERE note_id = ?", itemID).Error; err != nil {
			tx.Rollback()
			return err
		}

		eventData = map[string]interface{}{
			"note_id": itemID,
			"user_id": userID,
		}
	case "notebook":
		// Update the notebook to remove the deleted_at timestamp
		if err = tx.Exec("UPDATE notebooks SET deleted_at = NULL WHERE id = ? AND user_id = ?", itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Also restore all associated notes
		if err = tx.Exec("UPDATE notes SET deleted_at = NULL WHERE notebook_id = ? AND user_id = ?", itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// And restore blocks associated with those notes
		if err = tx.Exec(`UPDATE blocks SET deleted_at = NULL WHERE note_id IN 
			(SELECT id FROM notes WHERE notebook_id = ? AND user_id = ?)`, itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		eventData = map[string]interface{}{
			"notebook_id": itemID,
			"user_id":     userID,
		}
	default:
		tx.Rollback()
		return ErrInvalidInput
	}

	// Create event for the restoration
	event, err := models.NewEvent(
		itemType+".restored",
		itemType,
		"restore",
		userID,
		eventData,
	)
	if err != nil {
		tx.Rollback()
		return err
	}

	if err = tx.Create(event).Error; err != nil {
		tx.Rollback()
		return err
	}

	return tx.Commit().Error
}

func (s *TrashService) PermanentlyDeleteItem(db *database.Database, itemType string, itemID string, userID string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	var err error
	var eventData map[string]interface{}

	switch itemType {
	case "note":
		// Get tasks related to blocks in this note (correct relationship)
		if err = tx.Unscoped().Exec(`DELETE FROM tasks WHERE block_id IN 
			(SELECT id FROM blocks WHERE note_id = ?)`, itemID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Hard delete the blocks
		if err = tx.Unscoped().Exec("DELETE FROM blocks WHERE note_id = ?", itemID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Hard delete the note
		if err = tx.Unscoped().Exec("DELETE FROM notes WHERE id = ? AND user_id = ?", itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		eventData = map[string]interface{}{
			"note_id": itemID,
			"user_id": userID,
		}
	case "notebook":
		// Delete tasks related to blocks in notes in this notebook (correct relationship)
		if err = tx.Unscoped().Exec(`DELETE FROM tasks WHERE block_id IN
			(SELECT blocks.id FROM blocks 
			JOIN notes ON blocks.note_id = notes.id 
			WHERE notes.notebook_id = ? AND notes.user_id = ?)`, itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Hard delete the blocks
		if err = tx.Unscoped().Exec(`DELETE FROM blocks WHERE note_id IN 
			(SELECT id FROM notes WHERE notebook_id = ? AND user_id = ?)`, itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Hard delete the notes
		if err = tx.Unscoped().Exec("DELETE FROM notes WHERE notebook_id = ? AND user_id = ?", itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		// Hard delete the notebook
		if err = tx.Unscoped().Exec("DELETE FROM notebooks WHERE id = ? AND user_id = ?", itemID, userID).Error; err != nil {
			tx.Rollback()
			return err
		}

		eventData = map[string]interface{}{
			"notebook_id": itemID,
			"user_id":     userID,
		}
	default:
		tx.Rollback()
		return ErrInvalidInput
	}

	// Create event for permanent deletion (matching pattern in NoteService)
	event, err := models.NewEvent(
		itemType+".permanent_deleted",
		itemType,
		"permanent_delete",
		userID,
		eventData,
	)
	if err != nil {
		tx.Rollback()
		return err
	}

	if err = tx.Create(event).Error; err != nil {
		tx.Rollback()
		return err
	}

	return tx.Commit().Error
}

func (s *TrashService) EmptyTrash(db *database.Database, userID string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	// Delete tasks first (maintaining correct relationship)
	if err := tx.Unscoped().Exec(`DELETE FROM tasks WHERE block_id IN 
		(SELECT blocks.id FROM blocks 
		JOIN notes ON blocks.note_id = notes.id 
		WHERE notes.user_id = ? AND notes.deleted_at IS NOT NULL)`, userID).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Hard delete blocks in trashed notes
	if err := tx.Unscoped().Exec(`DELETE FROM blocks WHERE note_id IN 
		(SELECT id FROM notes WHERE user_id = ? AND deleted_at IS NOT NULL)`, userID).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Hard delete all trashed notes
	if err := tx.Unscoped().Exec("DELETE FROM notes WHERE user_id = ? AND deleted_at IS NOT NULL", userID).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Hard delete all trashed notebooks
	if err := tx.Unscoped().Exec("DELETE FROM notebooks WHERE user_id = ? AND deleted_at IS NOT NULL", userID).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Create event for emptying trash
	event, err := models.NewEvent(
		"trash.emptied",
		"trash",
		"empty",
		userID,
		map[string]interface{}{
			"user_id": userID,
		},
	)
	if err != nil {
		tx.Rollback()
		return err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return err
	}

	return tx.Commit().Error
}

// NewTrashService creates a new instance of TrashService
func NewTrashService() TrashServiceInterface {
	return &TrashService{}
}

// Don't initialize here, will be set properly in main.go
var TrashServiceInstance TrashServiceInterface
