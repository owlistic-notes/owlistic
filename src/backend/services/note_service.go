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
}

type NoteService struct{}

func (s *NoteService) CreateNote(db *database.Database, noteData map[string]interface{}) (models.Note, error) {
	title, ok := noteData["title"].(string)
	if !ok || title == "" {
		return models.Note{}, errors.New("title is required")
	}

	content, ok := noteData["content"].(string)
	if !ok {
		return models.Note{}, errors.New("content must be a string")
	}

	userIDStr, ok := noteData["user_id"].(string)
	if !ok {
		return models.Note{}, errors.New("user_id must be a string")
	}

	note := models.Note{
		ID:        uuid.New(),
		UserID:    uuid.Must(uuid.Parse(userIDStr)),
		Title:     title,
		Content:   content,
		IsDeleted: false,
	}

	if err := db.DB.Create(&note).Error; err != nil {
		return models.Note{}, err
	}

	eventJSON, _ := note.ToJSON()
	broker.PublishMessage(broker.NoteEventsTopic, note.ID.String(), string(eventJSON))

	return note, nil
}

func (s *NoteService) UpdateNote(db *database.Database, id string, updatedData map[string]interface{}) (models.Note, error) {
	var note models.Note
	if err := db.DB.First(&note, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Note{}, ErrNoteNotFound
		}
		return models.Note{}, err
	}

	if err := db.DB.Model(&note).Updates(updatedData).Error; err != nil {
		return models.Note{}, err
	}

	eventJSON, _ := note.ToJSON()
	broker.PublishMessage(broker.NoteEventsTopic, note.ID.String(), string(eventJSON))

	syncEvent := models.SyncEvent{
		DeviceID:    "all",
		LastEventID: note.ID.String(),
		Timestamp:   "",
	}
	syncEventJSON, _ := syncEvent.ToJSON()
	broker.PublishMessage(broker.SyncEventsTopic, note.ID.String(), string(syncEventJSON))

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
	var note models.Note
	if err := db.DB.First(&note, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrNoteNotFound
		}
		return err
	}

	if err := db.DB.Delete(&note).Error; err != nil {
		return err
	}

	eventJSON, _ := note.ToJSON()
	broker.PublishMessage(broker.NoteEventsTopic, id, string(eventJSON))

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
	result := db.DB.Find(&notes)
	if result.Error != nil {
		return nil, result.Error
	}
	return notes, nil
}

var NoteServiceInstance NoteServiceInterface = &NoteService{}
