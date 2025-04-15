package services

import (
	"errors"

	"github.com/google/uuid"
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
	GetNotebooks(db *database.Database, params map[string]interface{}) ([]models.Notebook, error)
}

type NotebookService struct{}

func (s *NotebookService) CreateNotebook(db *database.Database, notebookData map[string]interface{}) (models.Notebook, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Notebook{}, tx.Error
	}

	name, ok := notebookData["name"].(string)
	if !ok || name == "" {
		tx.Rollback()
		return models.Notebook{}, errors.New("name is required")
	}

	userIDStr, ok := notebookData["user_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Notebook{}, errors.New("user_id must be a string")
	}

	// Validate that the user exists before creating the notebook
	var userCount int64
	if err := tx.Model(&models.User{}).Where("id = ?", userIDStr).Count(&userCount).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	if userCount == 0 {
		tx.Rollback()
		return models.Notebook{}, errors.New("user not found")
	}

	// Properly handle the description field with a default empty string
	description := ""
	if desc, ok := notebookData["description"].(string); ok {
		description = desc
	}

	notebook := models.Notebook{
		ID:          uuid.New(),
		UserID:      uuid.Must(uuid.Parse(userIDStr)),
		Name:        name,
		Description: description,
		IsDeleted:   false,
	}

	if err := tx.Create(&notebook).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	event, err := models.NewEvent(
		"notebook.created",
		"notebook",
		"create",
		userIDStr,
		map[string]interface{}{
			"notebook_id": notebook.ID.String(),
			"user_id":     notebook.UserID.String(),
			"name":        notebook.Name,
			"created_at":  notebook.CreatedAt,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

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
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Notebook{}, tx.Error
	}

	var notebook models.Notebook
	if err := tx.First(&notebook, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Notebook{}, ErrNotebookNotFound
		}
		return models.Notebook{}, err
	}

	if err := tx.Model(&notebook).Updates(updatedData).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	event, err := models.NewEvent(
		"notebook.updated",
		"notebook",
		"update",
		notebook.UserID.String(),
		map[string]interface{}{
			"notebook_id": notebook.ID.String(),
			"user_id":     notebook.UserID.String(),
			"name":        notebook.Name,
			"updated_at":  notebook.UpdatedAt,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	return notebook, nil
}

func (s *NotebookService) DeleteNotebook(db *database.Database, id string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	var notebook models.Notebook
	if err := tx.First(&notebook, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrNotebookNotFound
		}
		return err
	}

	// Mark notebook as deleted
	// If we wanted to physically delete it, the CASCADE constraints would
	// automatically handle the deletion of notes, blocks, and tasks
	if err := tx.Model(&notebook).Update("is_deleted", true).Error; err != nil {
		tx.Rollback()
		return err
	}

	event, err := models.NewEvent(
		"notebook.deleted",
		"notebook",
		"delete",
		notebook.UserID.String(),
		map[string]interface{}{
			"notebook_id": notebook.ID.String(),
			"user_id":     notebook.UserID.String(),
			"deleted_at":  notebook.UpdatedAt,
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

func (s *NotebookService) GetNotebooks(db *database.Database, params map[string]interface{}) ([]models.Notebook, error) {
	var notebooks []models.Notebook
	query := db.DB.Preload("Notes")

	// Apply filters based on params
	if userID, ok := params["user_id"].(string); ok && userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	if name, ok := params["name"].(string); ok && name != "" {
		query = query.Where("name LIKE ?", "%"+name+"%")
	}

	if err := query.Find(&notebooks).Error; err != nil {
		return nil, err
	}
	return notebooks, nil
}

var NotebookServiceInstance NotebookServiceInterface = &NotebookService{}
