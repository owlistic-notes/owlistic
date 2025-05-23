package services

import (
	"encoding/json"
	"errors"
	"log"
	"time"

	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/config"
	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"

	"github.com/google/uuid"
	"github.com/nats-io/nats.go"
)

// SyncHandlerService handles bidirectional synchronization between blocks and tasks
type SyncHandlerService struct {
	db           *database.Database
	taskService  TaskServiceInterface
	blockService BlockServiceInterface
}

// NewSyncHandlerService creates a new sync handler instance
func NewSyncHandlerService(db *database.Database) *SyncHandlerService {
	return &SyncHandlerService{
		db:           db,
		taskService:  TaskServiceInstance,
		blockService: BlockServiceInstance,
	}
}

// Start begins the sync handler processing
func (s *SyncHandlerService) Start(cfg config.Config) {
	// Subscribe to block and task events
	topics := []string{
		broker.BlockSubject,
		broker.TaskSubject,
	}

	consumer, err := broker.InitConsumer(cfg, topics, "sync-handler-group")
	if err != nil {
		log.Printf("Warning: Failed to initialize sync handler consumer: %v", err)
		return
	}

	messageChan := consumer.GetMessageChannel()

	go s.processEvents(messageChan)
	log.Println("Block-Task Sync Handler started successfully")
}

// Stop halts the sync handler processing
func (s *SyncHandlerService) Stop() {
	log.Println("Block-Task Sync Handler stopped")
}

// processEvents handles incoming events
func (s *SyncHandlerService) processEvents(messageChan chan *nats.Msg) {
	for {
		select {
		case msg := <-messageChan:
			// Parse the message
			if err := s.handleSyncEvent(msg.Subject, msg.Data); err != nil {
				log.Printf("Error handling sync event %s: %v", msg.Subject, err)
			}
			// Broadcast the event to all connected clients
		case <-time.After(1 * time.Second):
		}
	}
}

// handleSyncEvent processes a block or task event
func (s *SyncHandlerService) handleSyncEvent(eventType string, data []byte) error {
	// Parse the message using StandardMessage format
	var message models.StandardMessage
	if err := json.Unmarshal(data, &message); err != nil {
		return err
	}

	// Skip if no payload
	if message.Payload == nil {
		return errors.New("empty payload in event message")
	}

	switch eventType {
	case string(broker.BlockCreated):
		return s.handleBlockCreated(message.Payload)
	case string(broker.BlockUpdated):
		return s.handleBlockUpdated(message.Payload)
	case string(broker.BlockDeleted):
		return s.handleBlockDeleted(message.Payload)
	case string(broker.TaskCreated):
		return s.handleTaskCreated(message.Payload)
	case string(broker.TaskUpdated):
		return s.handleTaskUpdated(message.Payload)
	case string(broker.TaskDeleted):
		return s.handleTaskDeleted(message.Payload)
	default:
		return nil // Ignore other events
	}
}

// handleBlockCreated creates a task when a task block is created
func (s *SyncHandlerService) handleBlockCreated(payload map[string]interface{}) error {
	blockIDStr, ok := payload["block_id"].(string)
	if !ok {
		return errors.New("missing block_id in block event payload")
	}

	// Get block type to ensure it's a task block
	blockType, ok := payload["block_type"].(string)
	if !ok || blockType != string(models.TaskBlock) {
		return nil // Not a task block, nothing to do
	}

	// Get user ID and note ID
	userIDStr, ok := payload["user_id"].(string)
	if !ok {
		return errors.New("missing user_id in event payload")
	}

	noteIDStr, ok := payload["note_id"].(string)
	if !ok {
		return errors.New("missing note_id in event payload")
	}

	// Get the full block
	var block models.Block
	if err := s.db.DB.Where("id = ?", blockIDStr).First(&block).Error; err != nil {
		return err
	}

	// Get text content for task title
	var textContent string
	if text, exists := block.Content["text"]; exists {
		if textStr, ok := text.(string); ok {
			textContent = textStr
		}
	}
	if textContent == "" {
		textContent = "Untitled Task" // Default title if none provided
	}

	// Check if a task already exists for this block using metadata
	var existingTasks []models.Task
	blockIDQuery := `metadata->>'block_id' = ?`
	err := s.db.DB.Where(blockIDQuery, blockIDStr).Find(&existingTasks).Error
	if err == nil && len(existingTasks) > 0 {
		// Task already exists, nothing to do
		return nil
	}

	// Check if this update originated from a task sync
	if lastSyncStr, exists := block.Metadata["last_synced"].(string); exists {
		lastSync, err := time.Parse(time.RFC3339, lastSyncStr)
		if err == nil {
			// Compare actual timestamps instead of using arbitrary time window
			if block.UpdatedAt.Compare(lastSync) < 0 {
				log.Printf("Block %s was already synced (UpdatedAt=%v, lastSync=%v), skipping update",
					blockIDStr, block.UpdatedAt.Format(time.RFC3339), lastSync.Format(time.RFC3339))
				return nil
			}
		}
	}

	taskData := map[string]interface{}{
		"user_id": userIDStr,
		"note_id": noteIDStr,
		"title":   textContent,
		"metadata": models.TaskMetadata{
			"block_id":    blockIDStr,
			"last_synced": time.Now().UTC(),
		},
	}

	// Log key creation events
	log.Printf("Creating task from block %s with sync marker", blockIDStr)

	// Extract completed status from metadata
	if block.Metadata != nil {
		if isCompleted, exists := block.Metadata["is_completed"].(bool); exists {
			taskData["is_completed"] = isCompleted
		}
	}

	// Create the task
	_, err = s.taskService.CreateTask(s.db, taskData)
	if err != nil {
		return err
	}

	return nil
}

// handleBlockUpdated syncs changes from a block to its associated task
func (s *SyncHandlerService) handleBlockUpdated(payload map[string]interface{}) error {
	blockIDStr, ok := payload["block_id"].(string)
	if !ok {
		return errors.New("missing block_id in block event payload")
	}

	// Get the full block to check current type
	var block models.Block
	if err := s.db.DB.Where("id = ?", blockIDStr).First(&block).Error; err != nil {
		return err
	}

	// Check if the block type has changed
	updatedType, hasType := payload["block_type"].(string)
	if !hasType {
		return errors.New("missing block_type in block event payload")
	}

	typeChanged := string(block.Type) != updatedType

	// If block type changed from task to another type, delete the associated task
	if typeChanged {
		if updatedType != string(models.TaskBlock) {
			log.Printf("Block type changed from TaskBlock to %s, deleting associated task", updatedType)
			// Find any tasks associated with this block and delete them
			var task models.Task
			if err := s.db.DB.Where("metadata->>'block_id' = ?", blockIDStr).Find(&task).Error; err != nil {
				return nil // No tasks found or error, nothing to delete
			}

			// Delete task associated with this block since it's no longer a task block
			if err := s.taskService.DeleteTask(s.db, task.ID.String()); err != nil {
				return err
			}
		} else {
			log.Printf("Block type changed to TaskBlock, creating a new task")
			return s.handleBlockCreated(payload)
		}
	}

	// Find the task associated with this block
	var task models.Task
	if err := s.db.DB.Where("metadata->>'block_id' = ?", blockIDStr).Find(&task).Error; err != nil {
		return s.handleBlockCreated(payload)
	}

	// Check if this update originated from a task sync
	if lastSyncStr, exists := block.Metadata["last_synced"].(string); exists {
		lastSync, err := time.Parse(time.RFC3339, lastSyncStr)
		if err == nil {
			// Compare actual timestamps instead of using arbitrary time window
			if block.UpdatedAt.Compare(lastSync) < 0 {
				log.Printf("Block %s was already synced (UpdatedAt=%v, lastSync=%v), skipping update",
					blockIDStr, block.UpdatedAt.Format(time.RFC3339), lastSync.Format(time.RFC3339))
				return nil
			}
		}
	}

	// Update task with block data
	updateData := models.Task{}

	// Get text content from block
	var textContent string
	if text, exists := block.Content["text"]; exists {
		if textStr, ok := text.(string); ok {
			textContent = textStr
		}
	}

	// Update title if block content has changed
	if task.Title != textContent && textContent != "" {
		updateData.Title = textContent
	}

	// Initialize metadata if needed
	if task.Metadata == nil {
		task.Metadata = models.TaskMetadata{}
	}

	// Create a copy of metadata
	updateData.Metadata = models.TaskMetadata(task.Metadata)

	// Get completed status from block metadata
	if block.Metadata != nil {
		if completed, exists := block.Metadata["is_completed"].(bool); exists {
			updateData.IsCompleted = completed
		}
	}

	// Always include the sync timestamp
	updateData.Metadata["last_synced"] = time.Now().UTC()

	// Only update if there are changes to apply
	_, err := s.taskService.UpdateTask(s.db, task.ID.String(), updateData)
	if err != nil {
		return err
	}

	return nil
}

// handleBlockDeleted removes associated tasks when a block is deleted
func (s *SyncHandlerService) handleBlockDeleted(payload map[string]interface{}) error {
	blockIDStr, ok := payload["block_id"].(string)
	if !ok {
		return errors.New("missing block_id in block event payload")
	}

	// Find all tasks associated with this block
	var task models.Task
	if err := s.db.DB.Where("metadata->>'block_id' = ?", blockIDStr).Find(&task).Error; err != nil {
		return nil // No tasks found or error, nothing to delete
	}

	// Delete task
	if err := s.taskService.DeleteTask(s.db, task.ID.String()); err != nil {
		return err
	}

	return nil
}

// handleTaskCreated links a task to a block if possible
func (s *SyncHandlerService) handleTaskCreated(payload map[string]interface{}) error {
	taskIDStr, ok := payload["task_id"].(string)
	if !ok {
		return errors.New("missing task_id in task event payload")
	}

	// Check if task already has a block_id
	var task models.Task
	if err := s.db.DB.Where("id = ?", taskIDStr).First(&task).Error; err != nil {
		return err
	}

	// Skip if this task was just updated by block sync
	if lastSyncStr, exists := task.Metadata["last_synced"].(string); exists {
		lastSync, err := time.Parse(time.RFC3339, lastSyncStr)
		if err == nil {
			// Compare actual timestamps instead of using arbitrary time window
			if task.UpdatedAt.Compare(lastSync) < 0 {
				log.Printf("Task %s was already synced (UpdatedAt=%v, lastSync=%v), skipping update",
					taskIDStr, task.UpdatedAt.Format(time.RFC3339), lastSync.Format(time.RFC3339))
				return nil
			}
		}
	}

	// Check if block_id exists in metadata and is valid
	blockIDStr, hasBlockID := task.Metadata["block_id"].(string)
	if !hasBlockID || blockIDStr == "" {
		// No valid block ID, create a block for this task
		return s.createBlockForTask(task)
	}

	// If task has a block ID, check if the block exists and is of type TaskBlock
	var block models.Block
	blockID, err := uuid.Parse(blockIDStr)
	if err != nil {
		// Invalid block ID format, create a new block
		return s.createBlockForTask(task)
	}

	if err := s.db.DB.Where("id = ?", blockID).First(&block).Error; err != nil {
		// Block doesn't exist - create a new one
		return s.createBlockForTask(task)
	}

	// If block exists but is not a task block, update it
	if block.Type != models.TaskBlock {
		// Update block type to task block
		blockData := map[string]interface{}{
			"type": string(models.TaskBlock),
			"content": models.BlockContent{
				"text": task.Title,
			},
			"metadata": models.BlockMetadata{
				"task_id":      task.ID.String(),
				"is_completed": task.IsCompleted,
			},
		}

		params := map[string]interface{}{
			"user_id": task.UserID.String(),
		}

		_, err := s.blockService.UpdateBlock(s.db, blockIDStr, blockData, params)
		if err != nil {
			return err
		}
	}

	return nil
}

// createBlockForTask creates a new block for a task that doesn't have one
func (s *SyncHandlerService) createBlockForTask(task models.Task) error {
	var noteID uuid.UUID

	// Check if the task has noteId in metadata
	if task.Metadata != nil {
		if noteIDStr, ok := task.Metadata["note_id"].(string); ok && noteIDStr != "" {
			if id, err := uuid.Parse(noteIDStr); err == nil {
				noteID = id
				// Verify the note exists
				var note models.Note
				if err := s.db.DB.First(&note, "id = ?", id).Error; err == nil {
					noteID = note.ID
				}
			}
		}
	}

	// Create a block for this task
	blockData := map[string]interface{}{
		"note_id": noteID.String(),
		"type":    string(models.TaskBlock),
		"content": models.BlockContent{
			"text": task.Title,
		},
		"metadata": models.BlockMetadata{
			"task_id":      task.ID.String(),
			"is_completed": task.IsCompleted,
		},
		"user_id": task.UserID.String(),
	}

	// Permission check parameters
	params := map[string]interface{}{
		"user_id": task.UserID.String(),
	}

	_, err := s.blockService.CreateBlock(s.db, blockData, params)
	if err != nil {
		return err
	}
	return err
}

// handleTaskUpdated syncs changes from a task to its associated block
func (s *SyncHandlerService) handleTaskUpdated(payload map[string]interface{}) error {
	taskIDStr, ok := payload["task_id"].(string)
	if !ok {
		return errors.New("missing task_id in task event payload")
	}

	// Get the complete task
	var task models.Task
	if err := s.db.DB.Where("id = ?", taskIDStr).First(&task).Error; err != nil {
		return err
	}

	// Skip if no block ID is associated
	blockIDStr, hasBlockID := task.Metadata["block_id"].(string)
	if !hasBlockID || blockIDStr == "" {
		// Create a block for this task
		return s.createBlockForTask(task)
	}

	// Get the associated block
	var block models.Block
	if err := s.db.DB.Where("id = ?", blockIDStr).First(&block).Error; err != nil {
		// Block doesn't exist anymore - create a new one
		return s.createBlockForTask(task)
	}

	// Skip if this task was just updated by block sync
	if lastSyncStr, exists := task.Metadata["last_synced"].(string); exists {
		lastSync, err := time.Parse(time.RFC3339, lastSyncStr)
		if err == nil {
			// Compare actual timestamps instead of using arbitrary time window
			if task.UpdatedAt.Compare(lastSync) < 0 {
				log.Printf("Task %s was already synced (UpdatedAt=%v, lastSync=%v), skipping update",
					taskIDStr, task.UpdatedAt.Format(time.RFC3339), lastSync.Format(time.RFC3339))
				return nil
			}
		}
	}

	// Update task with block data
	updateData := map[string]interface{}{
		"note_id": block.NoteID.String(),
		"type":    string(models.TaskBlock),
		"content": models.BlockContent{
			"text": task.Title,
		},
		"metadata": models.BlockMetadata{
			"task_id":      task.ID.String(),
			"last_synced":  time.Now().Format(time.RFC3339),
			"is_completed": task.IsCompleted,
			"emmmnnagiaa": true,
		},
		"user_id": task.UserID.String(),
	}

	params := map[string]interface{}{
		"user_id": task.UserID,
	}

	_, err := s.blockService.UpdateBlock(s.db, blockIDStr, updateData, params)
	if err != nil {
		return err
	}

	return nil
}

// handleTaskDeleted handles cleanup when a task is deleted
func (s *SyncHandlerService) handleTaskDeleted(payload map[string]interface{}) error {
	taskIDStr, ok := payload["task_id"].(string)
	if !ok {
		return errors.New("missing task_id in task event payload")
	}

	// We need to find the block_id from the task data
	// Since the task is deleted, we can't query it directly
	blockIDStr, ok := payload["block_id"].(string)

	// If block_id wasn't in the payload, we can't update the block
	if !ok || blockIDStr == "" {
		return nil
	}

	// Get the associated block
	var block models.Block
	if err := s.db.DB.Where("id = ?", blockIDStr).First(&block).Error; err != nil {
		return nil // Block not found or already deleted
	}

	// Check if this is a task block
	if block.Type != models.TaskBlock {
		return nil // Not a task block
	}

	// Update block metadata to reflect task deletion
	metadataMap := models.BlockMetadata(block.Metadata)

	// Add task deletion markers
	metadataMap["task_id"] = taskIDStr
	metadataMap["deleted_at"] = time.Now().UTC()

	// Get user_id from payload or from block
	userIDStr := ""
	if userID, ok := payload["user_id"].(string); ok {
		userIDStr = userID
	} else {
		userIDStr = block.UserID.String()
	}

	// Params for permission check
	params := map[string]interface{}{
		"user_id": userIDStr,
	}

	// Update the block to reflect task deletion
	err := s.blockService.DeleteBlock(s.db, blockIDStr, params)
	return err
}
