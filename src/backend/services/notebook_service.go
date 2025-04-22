package services

import (
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

type NotebookServiceInterface interface {
	CreateNotebook(db *database.Database, notebookData map[string]interface{}) (models.Notebook, error)
	GetNotebookById(db *database.Database, id string) (models.Notebook, error)
	UpdateNotebook(db *database.Database, id string, notebookData map[string]interface{}) (models.Notebook, error)
	DeleteNotebook(db *database.Database, id string) error
	ListNotebooksByUser(db *database.Database, userID string) ([]models.Notebook, error)
	GetAllNotebooks(db *database.Database) ([]models.Notebook, error)
	GetNotebooks(db *database.Database, params map[string]interface{}) ([]models.Notebook, error)
}

type NotebookService struct{}

var NotebookServiceInstance NotebookServiceInterface = &NotebookService{}

func (s *NotebookService) CreateNotebook(db *database.Database, notebookData map[string]interface{}) (models.Notebook, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Notebook{}, tx.Error
	}

	// Extract user_id and validate user exists
	userIDStr, ok := notebookData["user_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Notebook{}, ErrInvalidInput
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		tx.Rollback()
		return models.Notebook{}, ErrInvalidInput
	}

	var userCount int64
	if err := tx.Model(&models.User{}).Where("id = ?", userID).Count(&userCount).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	if userCount == 0 {
		tx.Rollback()
		return models.Notebook{}, ErrUserNotFound
	}

	// Create notebook
	name, _ := notebookData["name"].(string)
	description, _ := notebookData["description"].(string)
	notebookID := uuid.New()

	notebook := models.Notebook{
		ID:          notebookID,
		UserID:      userID,
		Name:        name,
		Description: description,
	}

	if err := tx.Create(&notebook).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	// Assign owner role to the creator
	role := models.Role{
		ID:           uuid.New(),
		UserID:       userID,
		ResourceID:   notebook.ID,
		ResourceType: models.NotebookResource,
		Role:         models.OwnerRole,
	}

	if err := tx.Create(&role).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	// Create event for notebook creation
	event, err := models.NewEvent(
		"notebook.created",
		"notebook",
		"create",
		userIDStr,
		map[string]interface{}{
			"notebook_id": notebook.ID.String(),
			"name":        notebook.Name,
			"description": notebook.Description,
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
		return models.Notebook{}, err
	}

	return notebook, nil
}

func (s *NotebookService) GetNotebookById(db *database.Database, id string) (models.Notebook, error) {
	var notebook models.Notebook
	if err := db.DB.First(&notebook, "id = ?", id).Error; err != nil {
		return models.Notebook{}, ErrNotebookNotFound
	}
	return notebook, nil
}

func (s *NotebookService) UpdateNotebook(db *database.Database, id string, notebookData map[string]interface{}) (models.Notebook, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Notebook{}, tx.Error
	}

	var notebook models.Notebook
	if err := tx.First(&notebook, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, ErrNotebookNotFound
	}

	// Update notebook fields
	if name, ok := notebookData["name"].(string); ok {
		notebook.Name = name
	}

	if description, ok := notebookData["description"].(string); ok {
		notebook.Description = description
	}

	notebook.UpdatedAt = time.Now()

	if err := tx.Save(&notebook).Error; err != nil {
		tx.Rollback()
		return models.Notebook{}, err
	}

	// Create event for notebook update
	userIDStr := notebookData["user_id"].(string)
	event, err := models.NewEvent(
		"notebook.updated",
		"notebook",
		"update",
		userIDStr,
		map[string]interface{}{
			"notebook_id": notebook.ID.String(),
			"name":        notebook.Name,
			"description": notebook.Description,
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
		return ErrNotebookNotFound
	}

	// Soft delete notebook (gorm will handle this)
	if err := tx.Delete(&notebook).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Create event for notebook deletion
	event, err := models.NewEvent(
		"notebook.deleted",
		"notebook",
		"delete",
		notebook.UserID.String(),
		map[string]interface{}{
			"notebook_id": notebook.ID.String(),
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

func (s *NotebookService) ListNotebooksByUser(db *database.Database, userID string) ([]models.Notebook, error) {
	var notebooks []models.Notebook
	if err := db.DB.Where("user_id = ?", userID).Find(&notebooks).Error; err != nil {
		return nil, err
	}
	return notebooks, nil
}

func (s *NotebookService) GetAllNotebooks(db *database.Database) ([]models.Notebook, error) {
	var notebooks []models.Notebook
	if err := db.DB.Find(&notebooks).Error; err != nil {
		return nil, err
	}
	return notebooks, nil
}

func (s *NotebookService) GetNotebooks(db *database.Database, params map[string]interface{}) ([]models.Notebook, error) {
	var notebooks []models.Notebook
	query := db.DB

	// Debug received params
	log.Printf("GetNotebooks received params: %+v", params)

	// More robust handling of user_id parameter
	userIDValue, userIDExists := params["user_id"]
	if !userIDExists {
		return nil, errors.New("user_id parameter is missing")
	}

	var userIDStr string
	switch v := userIDValue.(type) {
	case string:
		userIDStr = v
	case int:
		userIDStr = fmt.Sprintf("%d", v)
	case float64:
		userIDStr = fmt.Sprintf("%d", int(v))
	case uuid.UUID:
		userIDStr = v.String()
	default:
		return nil, fmt.Errorf("user_id has invalid type: %T", userIDValue)
	}

	if userIDStr == "" {
		return nil, errors.New("user_id cannot be empty")
	}

	// Apply user filter - only do this once
	query = query.Where("user_id = ?", userIDStr)

	// Apply other filters
	if name, ok := params["name"].(string); ok && name != "" {
		query = query.Where("name LIKE ?", "%"+name+"%")
	}

	// Include or exclude deleted notebooks
	if includeDeleted, ok := params["include_deleted"].(bool); ok && includeDeleted {
		query = query.Unscoped().Where("deleted_at IS NOT NULL")
	} else {
		query = query.Where("deleted_at IS NULL")
	}

	if err := query.Find(&notebooks).Error; err != nil {
		return nil, err
	}

	return notebooks, nil
}

// NewNotebookService creates a new instance of NotebookService
func NewNotebookService() NotebookServiceInterface {
	return &NotebookService{}
}
