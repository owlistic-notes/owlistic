package services

import (
	"errors"

	"github.com/google/uuid"
	"github.com/thinkstack/broker"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"

	"gorm.io/gorm"
)

type NoteServiceInterface interface {
	CreateNote(db *database.Database, noteData map[string]interface{}) (models.Note, error)
	GetNoteById(db *database.Database, id string) (models.Note, error)
	UpdateNote(db *database.Database, id string, updatedData map[string]interface{}) (models.Note, error)
	DeleteNote(db *database.Database, id string) error
	ListNotesByUser(db *database.Database, userID string) ([]models.Note, error)
	GetAllNotes(db *database.Database) ([]models.Note, error)
	GetNotes(db *database.Database, params map[string]interface{}) ([]models.Note, error)
}

type NoteService struct{}

func (s *NoteService) CreateNote(db *database.Database, noteData map[string]interface{}) (models.Note, error) {
	// Start transaction
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Note{}, tx.Error
	}

	title, ok := noteData["title"].(string)
	if !ok || title == "" {
		return models.Note{}, errors.New("title is required")
	}

	userIDStr, ok := noteData["user_id"].(string)
	if !ok {
		return models.Note{}, errors.New("user_id must be a string")
	}

	// Validate that the user exists before creating the note
	var userCount int64
	if err := tx.Model(&models.User{}).Where("id = ?", userIDStr).Count(&userCount).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if userCount == 0 {
		tx.Rollback()
		return models.Note{}, errors.New("user not found")
	}

	note := models.Note{
		ID:        uuid.New(),
		UserID:    uuid.Must(uuid.Parse(userIDStr)),
		Title:     title,
		IsDeleted: false,
	}

	if notebookID, ok := noteData["notebook_id"].(string); ok {
		// Validate that the notebook exists
		var notebookCount int64
		if err := tx.Model(&models.Notebook{}).Where("id = ?", notebookID).Count(&notebookCount).Error; err != nil {
			tx.Rollback()
			return models.Note{}, err
		}

		if notebookCount == 0 {
			tx.Rollback()
			return models.Note{}, errors.New("notebook not found")
		}

		note.NotebookID = uuid.Must(uuid.Parse(notebookID))
	} else {
		note.NotebookID = uuid.New()
	}

	// Handle blocks
	if blocksData, ok := noteData["blocks"].([]interface{}); ok {
		for i, blockData := range blocksData {
			blockMap := blockData.(map[string]interface{})

			// Process content based on input format
			var content models.BlockContent

			// Handle different content formats while preserving the interface
			switch c := blockMap["content"].(type) {
			case map[string]interface{}:
				// If we get a structured content object, use it directly
				content = c
			case string:
				// If content is provided as a string, convert to BlockContent
				content = models.BlockContent{"text": c}
			default:
				// Default empty content
				content = models.BlockContent{"text": ""}
			}

			block := models.Block{
				ID:      uuid.New(),
				Type:    models.BlockType(blockMap["type"].(string)),
				Content: content,
				Order:   i + 1,
			}
			note.Blocks = append(note.Blocks, block)
		}
	} else {
		// Create default text block if no blocks provided
		note.Blocks = []models.Block{{
			ID:      uuid.New(),
			Type:    models.TextBlock,
			Content: models.BlockContent{"text": ""},
			Order:   1,
		}}
	}

	if err := tx.Create(&note).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	// Replace broker publish with event creation using standard event type
	actorID, _ := noteData["user_id"].(string)
	event, err := models.NewEvent(
		string(broker.NoteCreated), // Use standard event type
		"note",
		"create",
		actorID,
		map[string]interface{}{
			"note_id":     note.ID.String(),
			"user_id":     note.UserID.String(),
			"notebook_id": note.NotebookID.String(),
			"title":       note.Title,
			"created_at":  note.CreatedAt,
		},
	)

	if err != nil {
		return note, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	return note, nil
}

func (s *NoteService) UpdateNote(db *database.Database, id string, updatedData map[string]interface{}) (models.Note, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Note{}, tx.Error
	}

	var note models.Note
	if err := tx.Preload("Blocks").First(&note, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Note{}, ErrNoteNotFound
		}
		return models.Note{}, err
	}

	// Update basic fields
	if title, ok := updatedData["title"].(string); ok {
		note.Title = title
	}

	// Handle blocks update
	if blocksData, ok := updatedData["blocks"].([]interface{}); ok {
		// Delete existing blocks
		if err := tx.Where("note_id = ?", note.ID).Delete(&models.Block{}).Error; err != nil {
			tx.Rollback()
			return models.Note{}, err
		}

		// Create new blocks
		var newBlocks []models.Block
		for i, blockData := range blocksData {
			blockMap := blockData.(map[string]interface{})

			// Process content based on input format
			var content models.BlockContent

			// Handle different content formats while preserving the interface
			switch c := blockMap["content"].(type) {
			case map[string]interface{}:
				// If we get a structured content object, use it directly
				content = c
			case string:
				// If content is provided as a string, convert to BlockContent
				content = models.BlockContent{"text": c}
			default:
				// Default empty content
				content = models.BlockContent{"text": ""}
			}

			block := models.Block{
				ID:      uuid.New(),
				NoteID:  note.ID,
				Type:    models.BlockType(blockMap["type"].(string)),
				Content: content,
				Order:   i + 1,
			}
			newBlocks = append(newBlocks, block)
		}
		note.Blocks = newBlocks
	}

	if err := tx.Model(&note).Updates(updatedData).Error; err != nil {
		tx.Rollback()
		return models.Note{}, err
	}

	actorID, _ := updatedData["user_id"].(string)
	event, err := models.NewEvent(
		string(broker.NoteUpdated), // Use standard event type
		"note",
		"update",
		actorID,
		map[string]interface{}{
			"note_id":     note.ID.String(),
			"user_id":     note.UserID.String(),
			"notebook_id": note.NotebookID.String(),
			"title":       note.Title,
			"updated_at":  note.UpdatedAt,
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
		tx.Rollback()
		return models.Note{}, err
	}

	return note, nil
}

func (s *NoteService) GetNoteById(db *database.Database, id string) (models.Note, error) {
	var note models.Note
	if err := db.DB.First(&note, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Note{}, ErrNoteNotFound
		}
		return models.Note{}, err
	}
	return note, nil
}

func (s *NoteService) DeleteNote(db *database.Database, id string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	var note models.Note
	if err := tx.First(&note, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrNoteNotFound
		}
		return err
	}

	// With proper ON DELETE CASCADE constraints, deleting the note
	// will automatically delete its blocks and tasks
	if err := tx.Delete(&note).Error; err != nil {
		tx.Rollback()
		return err
	}

	event, err := models.NewEvent(
		string(broker.NoteDeleted), // Use standard event type
		"note",
		"delete",
		note.UserID.String(),
		map[string]interface{}{
			"note_id": note.ID.String(),
			"user_id": note.UserID.String(),
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

func (s *NoteService) ListNotesByUser(db *database.Database, userID string) ([]models.Note, error) {
	var notes []models.Note
	if err := db.DB.Where("user_id = ?", userID).Find(&notes).Error; err != nil {
		return nil, err
	}
	return notes, nil
}

func (s *NoteService) GetAllNotes(db *database.Database) ([]models.Note, error) {
	var notes []models.Note
	result := db.DB.Find(&notes)
	if result.Error != nil {
		return nil, result.Error
	}
	return notes, nil
}

func (s *NoteService) GetNotes(db *database.Database, params map[string]interface{}) ([]models.Note, error) {
	var notes []models.Note
	query := db.DB.Preload("Blocks")

	// Apply filters based on params
	if userID, ok := params["user_id"].(string); ok && userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	if notebookID, ok := params["notebook_id"].(string); ok && notebookID != "" {
		query = query.Where("notebook_id = ?", notebookID)
	}

	if title, ok := params["title"].(string); ok && title != "" {
		query = query.Where("title LIKE ?", "%"+title+"%")
	}

	if err := query.Find(&notes).Error; err != nil {
		return nil, err
	}
	return notes, nil
}

// NewNoteService creates a new instance of NoteService
func NewNoteService() NoteServiceInterface {
	return &NoteService{}
}

// Don't initialize here, will be set properly in main.go
var NoteServiceInstance NoteServiceInterface
