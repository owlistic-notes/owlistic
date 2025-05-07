package services

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/thinkstack/broker"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"

	"gorm.io/gorm"
)

type TaskServiceInterface interface {
	CreateTask(db *database.Database, taskData map[string]interface{}) (models.Task, error)
	GetTaskById(db *database.Database, id string) (models.Task, error)
	UpdateTask(db *database.Database, id string, updatedData models.Task) (models.Task, error)
	DeleteTask(db *database.Database, id string) error
	GetAllTasks(db *database.Database) ([]models.Task, error)
	GetTasks(db *database.Database, params map[string]interface{}) ([]models.Task, error)
}

type TaskService struct{}

func (s *TaskService) CreateTask(db *database.Database, taskData map[string]interface{}) (models.Task, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Task{}, tx.Error
	}

	// Extract user_id
	userIDStr, ok := taskData["user_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Task{}, errors.New("user_id must be a string")
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		tx.Rollback()
		return models.Task{}, errors.New("user_id must be a valid UUID")
	}

	// Create task
	title, _ := taskData["title"].(string)
	taskID := uuid.New()

	task := models.Task{
		ID:     taskID,
		UserID: userID,
		Title:  title,
	}

	// Optional fields
	if descStr, ok := taskData["description"].(string); ok {
		task.Description = descStr
	}

	if completedBool, ok := taskData["is_completed"].(bool); ok {
		task.IsCompleted = completedBool
	}

	if dueDateStr, ok := taskData["due_date"].(string); ok {
		dueDate, err := time.Parse(time.RFC3339, dueDateStr)
		if err == nil {
			task.DueDate = dueDate.String()
		}
	}

	// Handle block association
	if blockIDStr, ok := taskData["block_id"].(string); ok && blockIDStr != "" {
		blockID, err := uuid.Parse(blockIDStr)
		if err == nil {
			var block models.Block
			if err := tx.First(&block, "id = ?", blockID).Error; err == nil {
				task.BlockID = blockID
			}
		}
	}

	if err := tx.Create(&task).Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	// Create owner role for the task
	role := models.Role{
		ID:           uuid.New(),
		UserID:       userID,
		ResourceID:   task.ID,
		ResourceType: models.TaskResource,
		Role:         models.OwnerRole,
	}

	if err := tx.Create(&role).Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	// Create event for task creation
	event, err := models.NewEvent(
		string(broker.TaskCreated),
		"task",
		"create",
		userID.String(),
		map[string]interface{}{
			"task_id":      task.ID.String(),
			"title":        task.Title,
			"is_completed": task.IsCompleted,
			"block_id":     task.BlockID.String(), // Add the block_id to the event payload
		},
	)

	if err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	if err := tx.Commit().Error; err != nil {
		return models.Task{}, err
	}

	return task, nil
}

func (s *TaskService) GetTaskById(db *database.Database, id string) (models.Task, error) {
	var task models.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Task{}, ErrTaskNotFound
		}
		return models.Task{}, err
	}
	return task, nil
}

func (s *TaskService) UpdateTask(db *database.Database, id string, updatedData models.Task) (models.Task, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Task{}, tx.Error
	}

	var task models.Task
	if err := tx.First(&task, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Task{}, ErrTaskNotFound
		}
		return models.Task{}, err
	}

	if err := tx.Model(&task).Updates(updatedData).Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	// Create the event payload for publishing
	eventPayload := map[string]interface{}{
		"task_id":      task.ID.String(),
		"user_id":      task.UserID.String(),
		"block_id":     task.BlockID.String(),
		"title":        task.Title,
		"is_completed": task.IsCompleted,
	}

	event, err := models.NewEvent(
		string(broker.TaskUpdated),
		"task",
		"update",
		task.UserID.String(),
		eventPayload,
	)

	if err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	return task, nil
}

func (s *TaskService) DeleteTask(db *database.Database, id string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	taskID, err := uuid.Parse(id)
	if err != nil {
		tx.Rollback()
		return errors.New("invalid task id")
	}

	var task models.Task
	if err := tx.First(&task, "id = ?", taskID).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrTaskNotFound
		}
		return err
	}

	// Create event for task deletion before actually deleting
	eventData := map[string]interface{}{
		"task_id":  task.ID.String(),
		"user_id":  task.UserID.String(),
		"block_id": task.BlockID.String(),
	}

	// Delete task
	if err := tx.Delete(&task).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Delete roles for this task
	if err := tx.Model(&models.Role{}).
		Where("resource_id = ? AND resource_type = ?", taskID, models.TaskResource).
		Update("deleted_at", time.Now()).
		Error; err != nil {
		tx.Rollback()
		return err
	}

	event, err := models.NewEvent(
		string(broker.TaskDeleted),
		"task",
		"delete",
		task.UserID.String(),
		eventData,
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

func (s *TaskService) GetAllTasks(db *database.Database) ([]models.Task, error) {
	var tasks []models.Task
	result := db.DB.Find(&tasks)
	if result.Error != nil {
		return nil, result.Error
	}
	return tasks, nil
}

func (s *TaskService) GetTasks(db *database.Database, params map[string]interface{}) ([]models.Task, error) {
	var tasks []models.Task
	query := db.DB

	// Apply filters based on params
	if userID, ok := params["user_id"].(string); ok && userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	if completed, ok := params["completed"].(string); ok && completed != "" {
		query = query.Where("is_completed = ?", completed == "true")
	}

	result := query.Find(&tasks)
	if result.Error != nil {
		return nil, result.Error
	}
	return tasks, nil
}

// NewTaskService creates a new instance of TaskService
func NewTaskService() TaskServiceInterface {
	return &TaskService{}
}

// Don't initialize here, will be set properly in main.go
var TaskServiceInstance TaskServiceInterface
