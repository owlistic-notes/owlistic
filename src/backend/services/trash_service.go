package services

import (
	"errors"
	"fmt"

	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"

	"github.com/google/uuid"
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

// RestoreItem restores a soft-deleted item from trash
func (s *TrashService) RestoreItem(db *database.Database, itemType, itemID, userID string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	parsedItemID, err := uuid.Parse(itemID)
	if err != nil {
		tx.Rollback()
		return errors.New("invalid item ID")
	}

	parsedUserID, err := uuid.Parse(userID)
	if err != nil {
		tx.Rollback()
		return errors.New("invalid user ID")
	}

	var eventType, entityType string

	// Handle different item types
	switch itemType {
	case "note":
		// Restore the note and its blocks
		result := tx.Exec("UPDATE notes SET deleted_at = NULL WHERE id = ? AND user_id = ?", parsedItemID, parsedUserID)
		if result.RowsAffected == 0 {
			tx.Rollback()
			return errors.New("note not found or not authorized")
		}

		// Restore blocks associated with the note
		tx.Exec("UPDATE blocks SET deleted_at = NULL WHERE note_id = ?", itemID)

		// Restore roles associated with the note and blocks
		tx.Exec("UPDATE roles SET deleted_at = NULL WHERE resource_id = ? AND resource_type = ?",
			parsedItemID, models.NoteResource)

		// Get block IDs to restore their roles too
		var blockIDs []uuid.UUID
		tx.Model(&models.Block{}).Where("note_id = ?", parsedItemID).Pluck("id", &blockIDs)

		for _, blockID := range blockIDs {
			tx.Exec("UPDATE roles SET deleted_at = NULL WHERE resource_id = ? AND resource_type = ?",
				blockID, models.BlockResource)
		}

		eventType = "note.restored"
		entityType = "note"

	case "notebook":
		// Restore the notebook and its notes
		result := tx.Exec("UPDATE notebooks SET deleted_at = NULL WHERE id = ? AND user_id = ?", itemID, userID)
		if result.RowsAffected == 0 {
			tx.Rollback()
			return errors.New("notebook not found or not authorized")
		}

		// Restore roles for the notebook
		tx.Exec("UPDATE roles SET deleted_at = NULL WHERE resource_id = ? AND resource_type = ?",
			parsedItemID, models.NotebookResource)

		// Get related note IDs
		var noteIDs []uuid.UUID
		tx.Model(&models.Note{}).Where("notebook_id = ?", parsedItemID).Pluck("id", &noteIDs)

		// Restore notes in the notebook
		tx.Exec("UPDATE notes SET deleted_at = NULL WHERE notebook_id = ?", itemID)

		// Restore roles for those notes
		for _, noteID := range noteIDs {
			tx.Exec("UPDATE roles SET deleted_at = NULL WHERE resource_id = ? AND resource_type = ?",
				noteID, models.NoteResource)

			// Restore blocks in those notes
			tx.Exec("UPDATE blocks SET deleted_at = NULL WHERE note_id = ?", noteID)

			// Get block IDs to restore their roles too
			var blockIDs []uuid.UUID
			tx.Model(&models.Block{}).Where("note_id = ?", noteID).Pluck("id", &blockIDs)

			for _, blockID := range blockIDs {
				tx.Exec("UPDATE roles SET deleted_at = NULL WHERE resource_id = ? AND resource_type = ?",
					blockID, models.BlockResource)
			}
		}

		eventType = "notebook.restored"
		entityType = "notebook"

	default:
		tx.Rollback()
		return ErrInvalidInput
	}

	// Create an event for the restore action
	event, err := models.NewEvent(
		eventType,
		entityType,
		map[string]interface{}{
			fmt.Sprintf("%s_id", entityType): itemID,
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

	if err := tx.Commit().Error; err != nil {
		return err
	}

	return nil
}

// PermanentlyDeleteItem permanently deletes an item from trash
func (s *TrashService) PermanentlyDeleteItem(db *database.Database, itemType, itemID, userID string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	parsedItemID, err := uuid.Parse(itemID)
	if err != nil {
		tx.Rollback()
		return errors.New("invalid item ID")
	}

	// First, check ownership by verifying the role
	var roleCount int64
	if err := tx.Model(&models.Role{}).
		Where("resource_id = ? AND user_id = ? AND role = ?", parsedItemID, userID, models.OwnerRole).
		Count(&roleCount).Error; err != nil {
		tx.Rollback()
		return err
	}

	if roleCount == 0 {
		tx.Rollback()
		return errors.New("not authorized to delete this item permanently")
	}

	var eventType, entityType string

	// Handle different item types
	switch itemType {
	case "note":
		// Delete associated blocks first
		tx.Exec("DELETE FROM tasks WHERE block_id IN (SELECT id FROM blocks WHERE note_id = ? AND user_id = ?)", itemID, userID)
		tx.Exec("DELETE FROM blocks WHERE note_id = ? AND user_id = ?", itemID, userID)

		// Delete associated roles
		tx.Exec("DELETE FROM roles WHERE resource_id = ? AND resource_type = ?", parsedItemID, models.NoteResource)

		// Now delete the note
		result := tx.Exec("DELETE FROM notes WHERE id = ? AND user_id = ?", itemID, userID)
		if result.RowsAffected == 0 {
			tx.Rollback()
			return errors.New("note not found or not authorized")
		}

		eventType = "note.permanent_deleted"
		entityType = "note"

	case "notebook":
		// First handle tasks related to blocks in notes of this notebook
		tx.Exec(`DELETE FROM tasks 
			WHERE block_id IN (
				SELECT b.id FROM blocks b 
				JOIN notes n ON b.note_id = n.id 
				WHERE n.notebook_id = ? AND n.user_id = ?
			)`, itemID, userID)

		// Delete blocks related to notes in this notebook
		tx.Exec(`DELETE FROM blocks 
			WHERE note_id IN (
				SELECT id FROM notes 
				WHERE notebook_id = ? AND user_id = ?
			)`, itemID, userID)

		// Delete roles for those blocks
		var blockIDs []uuid.UUID
		tx.Raw(`SELECT id FROM blocks 
			WHERE note_id IN (
				SELECT id FROM notes 
				WHERE notebook_id = ? AND user_id = ?
			)`, itemID, userID).Scan(&blockIDs)

		for _, blockID := range blockIDs {
			tx.Exec("DELETE FROM roles WHERE resource_id = ? AND resource_type = ?",
				blockID, models.BlockResource)
		}

		// Delete notes in the notebook
		tx.Exec("DELETE FROM notes WHERE notebook_id = ? AND user_id = ?", itemID, userID)

		// Delete roles for those notes
		var noteIDs []uuid.UUID
		tx.Raw("SELECT id FROM notes WHERE notebook_id = ? AND user_id = ?",
			itemID, userID).Scan(&noteIDs)

		for _, noteID := range noteIDs {
			tx.Exec("DELETE FROM roles WHERE resource_id = ? AND resource_type = ?",
				noteID, models.NoteResource)
		}

		// Delete roles for the notebook
		tx.Exec("DELETE FROM roles WHERE resource_id = ? AND resource_type = ?",
			parsedItemID, models.NotebookResource)

		// Now delete the notebook
		result := tx.Exec("DELETE FROM notebooks WHERE id = ? AND user_id = ?", itemID, userID)
		if result.RowsAffected == 0 {
			tx.Rollback()
			return errors.New("notebook not found or not authorized")
		}

		eventType = "notebook.permanent_deleted"
		entityType = "notebook"

	default:
		tx.Rollback()
		return ErrInvalidInput
	}

	// Create an event for the permanent deletion
	event, err := models.NewEvent(
		eventType,
		entityType,
		map[string]interface{}{
			fmt.Sprintf("%s_id", entityType): itemID,
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

	if err := tx.Commit().Error; err != nil {
		return err
	}

	return nil
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
		string(broker.TrashEmptied),
		"trash",
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
