package services

import (
	"errors"

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

	// Extract basic task data
	title, ok := taskData["title"].(string)
	if !ok || title == "" {
		tx.Rollback()
		return models.Task{}, errors.New("title is required")
	}

	userIDStr, ok := taskData["user_id"].(string)
	if !ok || userIDStr == "" {
		tx.Rollback()
		return models.Task{}, errors.New("user_id is required")
	}

	// Validate that the user exists
	var userCount int64
	if err := tx.Model(&models.User{}).Where("id = ?", userIDStr).Count(&userCount).Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	if userCount == 0 {
		tx.Rollback()
		return models.Task{}, errors.New("user not found")
	}

	description := ""
	if desc, ok := taskData["description"].(string); ok {
		description = desc
	}

	isCompleted := false
	if completed, ok := taskData["is_completed"].(bool); ok {
		isCompleted = completed
	}

	// Create a task model with the basic fields
	task := models.Task{
		ID:          uuid.New(),
		UserID:      uuid.Must(uuid.Parse(userIDStr)),
		Title:       title,
		Description: description,
		IsCompleted: isCompleted,
	}

	// Handle note/block association
	noteIDStr, noteIDExists := taskData["note_id"].(string)
	blockIDStr, blockIDExists := taskData["block_id"].(string)

	if noteIDExists && noteIDStr != "" {
		// If note_id is provided, associate with the last block or create a new one
		noteID := uuid.Must(uuid.Parse(noteIDStr))

		// Check if the note exists
		var note models.Note
		if err := tx.First(&note, "id = ?", noteID).Error; err != nil {
			tx.Rollback()
			return models.Task{}, errors.New("note not found")
		}

		// Find the last block in the note by order
		var lastBlock models.Block
		result := tx.Where("note_id = ?", noteID).Order("`order` DESC").First(&lastBlock)

		if result.Error == nil {
			// Block found, associate the task with it
			task.BlockID = lastBlock.ID
		} else if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			// No blocks found, create a new one
			newBlock := models.Block{
				ID:      uuid.New(),
				NoteID:  noteID,
				Type:    models.TaskBlock,
				Content: "Task",
				Order:   1,
			}

			if err := tx.Create(&newBlock).Error; err != nil {
				tx.Rollback()
				return models.Task{}, err
			}

			task.BlockID = newBlock.ID
		} else {
			// Unexpected error
			tx.Rollback()
			return models.Task{}, result.Error
		}
	} else if blockIDExists && blockIDStr != "" {
		// If block_id is directly provided, use it
		task.BlockID = uuid.Must(uuid.Parse(blockIDStr))

		// Verify the block exists
		var block models.Block
		if err := tx.First(&block, "id = ?", task.BlockID).Error; err != nil {
			tx.Rollback()
			return models.Task{}, errors.New("block not found")
		}
	} else {
		// Neither note_id nor block_id provided
		tx.Rollback()
		return models.Task{}, errors.New("either note_id or block_id is required")
	}

	// Create the task
	if err := tx.Create(&task).Error; err != nil {
		tx.Rollback()
		return models.Task{}, err
	}

	// Create event
	event, err := models.NewEvent(
		string(broker.TaskCreated), // Use standard event type
		"task",
		"create",
		task.UserID.String(),
		map[string]interface{}{
			"task_id":      task.ID.String(),
			"user_id":      task.UserID.String(),
			"block_id":     task.BlockID.String(),
			"title":        task.Title,
			"is_completed": task.IsCompleted,
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
		tx.Rollback()
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

	event, err := models.NewEvent(
		string(broker.TaskUpdated), // Use standard event type
		"task",
		"update",
		task.UserID.String(),
		map[string]interface{}{
			"task_id":      task.ID.String(),
			"user_id":      task.UserID.String(),
			"title":        task.Title,
			"is_completed": task.IsCompleted,
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

	var task models.Task
	if err := tx.First(&task, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrTaskNotFound
		}
		return err
	}

	if err := tx.Delete(&task).Error; err != nil {
		tx.Rollback()
		return err
	}

	event, err := models.NewEvent(
		string(broker.TaskDeleted), // Use standard event type
		"task",
		"delete",
		task.UserID.String(),
		map[string]interface{}{
			"task_id": task.ID.String(),
			"user_id": task.UserID.String(),
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
		tx.Rollback()
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

var TaskServiceInstance TaskServiceInterface = &TaskService{}
