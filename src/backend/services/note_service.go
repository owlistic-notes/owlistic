package services

import (
	"errors"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"

	"gorm.io/gorm"
)

type NoteServiceInterface interface {
	CreateNote(db *database.Database, noteData map[string]interface{}) (models.Note, error)
	GetNoteById(db *database.Database, id string, params map[string]interface{}) (models.Note, error)
	UpdateNote(db *database.Database, id string, noteData map[string]interface{}, params map[string]interface{}) (models.Note, error)
	DeleteNote(db *database.Database, id string, params map[string]interface{}) error
	ListNotesByUser(db *database.Database, userID string) ([]models.Note, error)
	GetAllNotes(db *database.Database) ([]models.Note, error)
	GetNotes(db *database.Database, params map[string]interface{}) ([]models.Note, error)
}

type NoteService struct{}

var NoteServiceInstance NoteServiceInterface = &NoteService{}

func (s *NoteService) CreateNote(db *database.Database, noteData map[string]interface{}) (models.Note, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Note{}, tx.Error
	}

	// Extract user_id and validate user exists
	userIDStr, ok := noteData["user_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Note{}, errors.New("user_id must be a string")
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		tx.Rollback()
		return models.Note{}, errors.New("user_id must be a valid UUID")
	}

	var userCount int64
	if err := tx.Model(&models.User{}).Where("id = ?", userID).Count(&userCount).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if userCount == 0 {
		tx.Rollback()
		return models.Note{}, errors.New("user not found")
	}

	// Extract notebook_id and validate notebook exists
	notebookIDStr, ok := noteData["notebook_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Note{}, errors.New("notebook_id must be a string")
	}

	notebookID, err := uuid.Parse(notebookIDStr)
	if err != nil {
		tx.Rollback()
		return models.Note{}, errors.New("notebook_id must be a valid UUID")
	}

	var notebookCount int64
	if err := tx.Model(&models.Notebook{}).Where("id = ?", notebookID).Count(&notebookCount).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if notebookCount == 0 {
		tx.Rollback()
		return models.Note{}, errors.New("notebook not found")
	}

	// Create note
	title, _ := noteData["title"].(string)
	noteID := uuid.New()

	note := models.Note{
		ID:         noteID,
		UserID:     userID,
		NotebookID: notebookID,
		Title:      title,
	}

	if err := tx.Create(&note).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	// Assign owner role to the creator
	role := models.Role{
		ID:           uuid.New(),
		UserID:       userID,
		ResourceID:   note.ID,
		ResourceType: models.NoteResource,
		Role:         models.OwnerRole,
	}

	if err := tx.Create(&role).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	// Create at least one initial empty block for the note
	blockID := uuid.New()
	block := models.Block{
		ID:      blockID,
		NoteID:  noteID,
		UserID:  userID,
		Type:    models.TextBlock,
		Content: models.BlockContent{"text": ""},
		Order:   1,
	}

	if err := tx.Create(&block).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	// Create event for note creation
	event, err := models.NewEvent(
		"note.created",
		"note",
		"create",
		userIDStr,
		map[string]interface{}{
			"note_id":     note.ID.String(),
			"notebook_id": note.NotebookID.String(),
			"title":       note.Title,
			"blocks":      []string{block.ID.String()},
		},
	)

	if err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if err := tx.Commit().Error; err != nil {
		return models.Note{}, err
	}

	// Reload note with its blocks
	var completeNote models.Note
	if err := db.DB.Preload("Blocks").First(&completeNote, "id = ?", note.ID).Error; err != nil {
		return models.Note{}, err
	}

	return completeNote, nil
}

func (s *NoteService) GetNoteById(db *database.Database, id string, params map[string]interface{}) (models.Note, error) {
	// Get user ID from params for permission check
	userID, ok := params["user_id"].(string)
	if !ok {
		return models.Note{}, errors.New("user_id must be provided in parameters")
	}

	// Check if user has viewer access using the new method
	hasAccess, err := RoleServiceInstance.HasNoteAccess(db, userID, id, "viewer")
	if err != nil {
		return models.Note{}, err
	}

	if !hasAccess {
		return models.Note{}, errors.New("not authorized to access this note")
	}

	var note models.Note
	if err := db.DB.Preload("Blocks", func(db *gorm.DB) *gorm.DB {
		return db.Order("\"blocks\".\"order\" ASC")
	}).First(&note, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Note{}, ErrNoteNotFound
		}
		return models.Note{}, err
	}
	return note, nil
}

// UpdateNote handles updating a note with permission checks
func (s *NoteService) UpdateNote(db *database.Database, id string, noteData map[string]interface{}, params map[string]interface{}) (models.Note, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Note{}, tx.Error
	}

	// Get user ID from params for permission check (not from noteData)
	userIDStr, ok := params["user_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Note{}, errors.New("user_id must be provided in parameters")
	}

	// Check if user has editor rights using the new method
	hasAccess, err := RoleServiceInstance.HasNoteAccess(db, userIDStr, id, "editor")
	if err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if !hasAccess {
		tx.Rollback()
		return models.Note{}, errors.New("not authorized to update this note")
	}

	var note models.Note
	if err := tx.First(&note, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return models.Note{}, ErrNoteNotFound
	}

	// Update note fields
	if title, ok := noteData["title"].(string); ok {
		note.Title = title
	}

	if notebookIDStr, ok := noteData["notebook_id"].(string); ok {
		notebookID, err := uuid.Parse(notebookIDStr)
		if err != nil {
			tx.Rollback()
			return models.Note{}, errors.New("notebook_id must be a valid UUID")
		}

		// Verify notebook exists
		var notebookCount int64
		if err := tx.Model(&models.Notebook{}).Where("id = ?", notebookID).Count(&notebookCount).Error; err != nil {
			tx.Rollback()
			return models.Note{}, err
		}

		if notebookCount == 0 {
			tx.Rollback()
			return models.Note{}, errors.New("notebook not found")
		}

		note.NotebookID = notebookID
	}

	note.UpdatedAt = time.Now()

	if err := tx.Save(&note).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	// Create event for note update
	event, err := models.NewEvent(
		"note.updated",
		"note",
		"update",
		userIDStr,
		map[string]interface{}{
			"note_id":     note.ID.String(),
			"notebook_id": note.NotebookID.String(),
			"title":       note.Title,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if err := tx.Commit().Error; err != nil {
		return models.Note{}, err
	}

	// Reload note with its blocks
	var updatedNote models.Note
	if err := db.DB.Preload("Blocks", func(db *gorm.DB) *gorm.DB {
		return db.Order("\"blocks\".\"order\" ASC")
	}).First(&updatedNote, "id = ?", note.ID).Error; err != nil {
		return models.Note{}, err
	}

	return updatedNote, nil
}

func (s *NoteService) DeleteNote(db *database.Database, id string, params map[string]interface{}) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	// Get user ID from params for permission check
	userIDStr, ok := params["user_id"].(string)
	if !ok {
		tx.Rollback()
		return errors.New("user_id must be provided in parameters")
	}

	var note models.Note
	if err := tx.First(&note, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrNoteNotFound
		}
		return err
	}

	// Check if user has owner rights using the new method
	hasAccess, err := RoleServiceInstance.HasNoteAccess(db, userIDStr, id, "owner")
	if err != nil {
		tx.Rollback()
		return err
	}

	if !hasAccess {
		tx.Rollback()
		return errors.New("not authorized to delete this note")
	}

	// Soft delete note (gorm will handle this)
	if err := tx.Delete(&note).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Create event for note deletion
	event, err := models.NewEvent(
		"note.deleted",
		"note",
		"delete",
		userIDStr,
		map[string]interface{}{
			"note_id":     note.ID.String(),
			"notebook_id": note.NotebookID.String(),
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

func (s *NoteService) ListNotesByUser(db *database.Database, userID string) ([]models.Note, error) {
	var notes []models.Note
	if err := db.DB.Where("user_id = ?", userID).Find(&notes).Error; err != nil {
		return nil, err
	}
	return notes, nil
}

func (s *NoteService) GetAllNotes(db *database.Database) ([]models.Note, error) {
	var notes []models.Note
	if err := db.DB.Find(&notes).Error; err != nil {
		return nil, err
	}
	return notes, nil
}

// GetNotes retrieves notes based on query parameters with access control
func (s *NoteService) GetNotes(db *database.Database, params map[string]interface{}) ([]models.Note, error) {
	var notes []models.Note
	query := db.DB

	// Always filter by user_id if provided - this is critical for RBAC
	userID, ok := params["user_id"].(string)
	if !ok || userID == "" {
		return nil, errors.New("user_id is required for security reasons")
	}

	// Log for debugging
	log.Printf("Fetching notes for user: %s", userID)

	// Get all notes owned by the user
	query = query.Where("user_id = ?", userID)

	// Apply other filters
	if notebookID, ok := params["notebook_id"].(string); ok && notebookID != "" {
		query = query.Where("notebook_id = ?", notebookID)
	}

	if title, ok := params["title"].(string); ok && title != "" {
		query = query.Where("title LIKE ?", "%"+title+"%")
	}

	// Include or exclude deleted notes
	if includeDeleted, ok := params["include_deleted"].(bool); ok && includeDeleted {
		query = query.Unscoped().Where("deleted_at IS NOT NULL")
	} else {
		query = query.Where("deleted_at IS NULL")
	}

	// Execute the query
	if err := query.Find(&notes).Error; err != nil {
		log.Printf("Error executing note query: %v", err)
		return nil, err
	}

	log.Printf("Found %d notes directly owned by user %s", len(notes), userID)

	// Find notes where the user has explicit roles (using our new role service methods)
	// var allRoles []models.Role
	// roleParams := map[string]interface{}{
	// 	"user_id":       userID,
	// 	"resource_type": string(models.NoteResource),
	// }
	// sharedNotes, err := RoleServiceInstance.GetRoles(db, roleParams)
	// if err != nil {
	// 	log.Printf("Error finding role-based notes: %v", err)
	// } else {
	// 	for _, role := range sharedNotes {
	// 		// Skip notes that the user already owns
	// 		var isOwned bool
	// 		for _, note := range notes {
	// 			if note.ID == role.ResourceID {
	// 				isOwned = true
	// 				break
	// 			}
	// 		}

	// 		if !isOwned {
	// 			var sharedNote models.Note
	// 			if err := db.DB.Where("id = ? AND deleted_at IS NULL", role.ResourceID).First(&sharedNote).Error; err == nil {
	// 				notes = append(notes, sharedNote)
	// 			}
	// 		}
	// 	}
	// 	log.Printf("Found %d additional notes where user has an explicit role", len(notes)-len(allRoles))
	// }

	// Load blocks for each note
	for i := range notes {
		if err := db.DB.Model(&notes[i]).Association("Blocks").Find(&notes[i].Blocks); err != nil {
			log.Printf("Failed to load blocks for note %s: %v", notes[i].ID, err)
		}

		// Sort the blocks by order field
		db.DB.Model(&models.Block{}).Where("note_id = ?", notes[i].ID).Order("\"order\" ASC").Find(&notes[i].Blocks)
	}

	return notes, nil
}

// NewNoteService creates a new instance of NoteService
func NewNoteService() NoteServiceInterface {
	return &NoteService{}
}
