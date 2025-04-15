package services

import (
	"errors"

	"github.com/google/uuid"
	"github.com/thinkstack/broker"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"gorm.io/gorm"
)

type NotebookServiceInterface interface {
	CreateNotebook(db *database.Database, notebookData map[string]interface{}) (models.Notebook, error)
	GetNotebookById(db *database.Database, id string) (models.Notebook, error)
	UpdateNotebook(db *database.Database, id string, updatedData map[string]interface{}) (models.Notebook, error)
	DeleteNotebook(db *database.Database, id string) error
	ListNotebooksByUser(db *database.Database, userID string) ([]models.Notebook, error)
	GetAllNotebooks(db *database.Database) ([]models.Notebook, error)
}

type NotebookService struct{}

func (s *NotebookService) CreateNotebook(db *database.Database, notebookData map[string]interface{}) (models.Notebook, error) {
	name, ok := notebookData["name"].(string)
	if !ok || name == "" {
		return models.Notebook{}, errors.New("name is required")
	}

	userIDStr, ok := notebookData["user_id"].(string)
	if !ok {
		return models.Notebook{}, errors.New("user_id must be a string")
	}

	notebook := models.Notebook{
		ID:          uuid.New(),
		UserID:      uuid.Must(uuid.Parse(userIDStr)),
		Name:        name,
		Description: notebookData["description"].(string),
		IsDeleted:   false,
	}

	if err := db.DB.Create(&notebook).Error; err != nil {
		return models.Notebook{}, err
	}

	eventJSON, _ := notebook.ToJSON()
	broker.PublishMessage(broker.NotebookEventsTopic, notebook.ID.String(), string(eventJSON))

	// Trigger sync event
	syncEvent := models.SyncEvent{
		DeviceID:    "all",
		LastEventID: notebook.ID.String(),
		// Timestamp:   notebook.CreatedAt.String(),
	}
	syncEventJSON, _ := syncEvent.ToJSON()
	broker.PublishMessage(broker.SyncEventsTopic, notebook.ID.String(), string(syncEventJSON))

	return notebook, nil
}

func (s *NotebookService) GetNotebookById(db *database.Database, id string) (models.Notebook, error) {
	var notebook models.Notebook
	if err := db.DB.Preload("Notes").First(&notebook, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Notebook{}, ErrNotebookNotFound
		}
		return models.Notebook{}, err
	}
	return notebook, nil
}

func (s *NotebookService) UpdateNotebook(db *database.Database, id string, updatedData map[string]interface{}) (models.Notebook, error) {
	var notebook models.Notebook
	if err := db.DB.First(&notebook, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Notebook{}, ErrNotebookNotFound
		}
		return models.Notebook{}, err
	}

	if err := db.DB.Model(&notebook).Updates(updatedData).Error; err != nil {
		return models.Notebook{}, err
	}

	eventJSON, _ := notebook.ToJSON()
	broker.PublishMessage(broker.NotebookEventsTopic, notebook.ID.String(), string(eventJSON))

	// Trigger sync event
	syncEvent := models.SyncEvent{
		DeviceID:    "all",
		LastEventID: notebook.ID.String(),
		Timestamp:   notebook.UpdatedAt.String(),
	}
	syncEventJSON, _ := syncEvent.ToJSON()
	broker.PublishMessage(broker.SyncEventsTopic, notebook.ID.String(), string(syncEventJSON))

	return notebook, nil
}

func (s *NotebookService) DeleteNotebook(db *database.Database, id string) error {
	var notebook models.Notebook
	if err := db.DB.First(&notebook, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrNotebookNotFound
		}
		return err
	}

	if err := db.DB.Model(&notebook).Update("is_deleted", true).Error; err != nil {
		return err
	}

	eventJSON, _ := notebook.ToJSON()
	broker.PublishMessage(broker.NotebookEventsTopic, id, string(eventJSON))

	// Trigger sync event
	syncEvent := models.SyncEvent{
		DeviceID:    "all",
		LastEventID: notebook.ID.String(),
		Timestamp:   notebook.UpdatedAt.String(),
	}
	syncEventJSON, _ := syncEvent.ToJSON()
	broker.PublishMessage(broker.SyncEventsTopic, notebook.ID.String(), string(syncEventJSON))

	return nil
}

func (s *NotebookService) ListNotebooksByUser(db *database.Database, userID string) ([]models.Notebook, error) {
	var notebooks []models.Notebook
	if err := db.DB.Preload("Notes").Where("user_id = ?", userID).Find(&notebooks).Error; err != nil {
		return nil, err
	}
	return notebooks, nil
}

func (s *NotebookService) GetAllNotebooks(db *database.Database) ([]models.Notebook, error) {
	var notebooks []models.Notebook
	if err := db.DB.Preload("Notes").Find(&notebooks).Error; err != nil {
		return nil, err
	}
	return notebooks, nil
}

var NotebookServiceInstance NotebookServiceInterface = &NotebookService{}
