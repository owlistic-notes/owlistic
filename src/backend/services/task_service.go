package services

import (
	"errors"
	"time"

	"daviderutigliano/owlistic/broker"
	"daviderutigliano/owlistic/database"
	"daviderutigliano/owlistic/models"

	"github.com/google/uuid"

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

	// Initialize metadata
	task.Metadata = models.TaskMetadata{}

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

	// Store note_id in metadata if provided
	noteIDStr := ""
	if nid, ok := taskData["note_id"].(string); ok && nid != "" {
		noteIDStr = nid
		task.Metadata["note_id"] = noteIDStr
	}

	// Handle block association
	blockIDProvided := false
	if blockIDStr, ok := taskData["block_id"].(string); ok && blockIDStr != "" {
		blockID, err := uuid.Parse(blockIDStr)
		if err == nil && blockID != uuid.Nil {
			// Verify the block exists
			var block models.Block
			if err := tx.First(&block, "id = ?", blockID).Error; err == nil {
				task.BlockID = blockID
				blockIDProvided = true
			} else {
				tx.Rollback()
				return models.Task{}, errors.New("specified block_id does not exist")
			}
		}
	}

	// If block_id wasn't provided but note_id was, create a block for this task
	if !blockIDProvided && noteIDStr != "" {
		noteID, err := uuid.Parse(noteIDStr)
		if err != nil {
			tx.Rollback()
			return models.Task{}, errors.New("invalid note_id format")
		}

		// Verify the note exists and user has access
		var note models.Note
		if err := tx.First(&note, "id = ? AND user_id = ?", noteID, userID).Error; err != nil {
			tx.Rollback()
			return models.Task{}, errors.New("note not found or access denied")
		}

		// Create a block for this task
		block := models.Block{
			ID:     uuid.New(),
			NoteID: noteID,
			UserID: userID,
			Type:   models.TaskBlock,
			Content: models.BlockContent{
				"text": title,
			},
			Metadata: models.BlockContent{
				"is_completed": task.IsCompleted,
				"task_id":      taskID.String(),
				"_sync_source": "task",
			},
		}

		if err := tx.Create(&block).Error; err != nil {
			tx.Rollback()
			return models.Task{}, err
		}

		// Now set the block_id on the task
		task.BlockID = block.ID

		// Create event for block creation
		blockEvent, err := models.NewEvent(
			string(broker.BlockCreated),
			"block",
			"create",
			userID.String(),
			map[string]interface{}{
				"block_id":     block.ID.String(),
				"note_id":      noteID.String(),
				"user_id":      userID.String(),
				"block_type":   string(models.TaskBlock),
				"content":      block.Content,
				"metadata":     block.Metadata,
				"_sync_source": "task",
			},
		)
		if err != nil {
			tx.Rollback()
			return models.Task{}, err
		}
		if err := tx.Create(blockEvent).Error; err != nil {
			tx.Rollback()
			return models.Task{}, err
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

	// Get note_id from metadata or taskData for the event
	if noteIDStr == "" {
		if task.Metadata != nil {
			if nid, ok := task.Metadata["note_id"].(string); ok {
				noteIDStr = nid
			}
		}
	}

	// Create event for task creation
	eventPayload := map[string]interface{}{
		"task_id":      task.ID.String(),
		"title":        task.Title,
		"is_completed": task.IsCompleted,
	}

	// Only include block_id if it's set
	if task.BlockID != uuid.Nil {
		eventPayload["block_id"] = task.BlockID.String()
	}

	// Include note_id in event payload if it exists
	if noteIDStr != "" {
		eventPayload["note_id"] = noteIDStr
	}

	event, err := models.NewEvent(
		string(broker.TaskCreated),
		"task",
		"create",
		userID.String(),
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

	if blockID, ok := params["block_id"].(string); ok && blockID != "" {
		query = query.Where("block_id = ?", blockID)
	}

	if noteID, ok := params["note_id"].(string); ok && noteID != "" {
		// Filter tasks by note ID (from metadata)
		query = query.Where("CAST(metadata->>'note_id' AS TEXT) = ?", noteID)
	}

	// Standardize on include_deleted parameter
	includeDeleted := false
	if includeDeletedParam, ok := params["include_deleted"].(string); ok {
		includeDeleted = includeDeletedParam == "true"
	} else if includeDeletedBool, ok := params["include_deleted"].(bool); ok {
		includeDeleted = includeDeletedBool
	}

	// If include_deleted=true, show only deleted items
	if includeDeleted {
		query = query.Unscoped().Where("deleted_at IS NOT NULL")
	} else {
		// Otherwise show only non-deleted items
		query = query.Where("deleted_at IS NULL")
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
