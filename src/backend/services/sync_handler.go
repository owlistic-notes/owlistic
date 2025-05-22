package services

import (
	"encoding/json"
	"errors"
	"log"
	"maps"
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


	// Check if sync source exists - this is a key issue that's causing loops
	if syncSource, exists := block.Metadata["_sync_source"]; exists {
		if syncSource == "task" {
			log.Printf("Block %s was created by task sync, skipping task creation", blockIDStr)
			return nil // Skip creating a taks since this block was created from a task
		}
	}

	taskData := map[string]interface{}{
		"user_id": userIDStr,
		"note_id": noteIDStr,
		"title":   textContent,
		"metadata": models.TaskMetadata{
			"_sync_source": "block",
			"block_id":     blockIDStr,
			"last_synced":  time.Now().Format(time.RFC3339),
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
		log.Printf("Payload: %v", payload)
		return errors.New("missing block_id in block event payload")
	}

	// Get the full block to check current type
	var block models.Block
	if err := s.db.DB.Where("id = ?", blockIDStr).First(&block).Error; err != nil {
		return err
	}

	// Check if the block type has changed
	updatedType, hasType := payload["block_type"].(string)
	typeChanged := hasType && string(block.Type) != updatedType


	// Only continue if this is a task block (either unchanged or still a task block after update)
	if block.Type != models.TaskBlock || hasType && updatedType != string(models.TaskBlock) {
		return nil // Not a task block, nothing to do
	}

	// If block type changed from task to another type, delete the associated task
	if typeChanged && updatedType != string(models.TaskBlock) {
		log.Printf("Block type changed from TaskBlock to %s, deleting associated task", updatedType)
		// Find any tasks associated with this block and delete them
		var tasks []models.Task
		if err := s.db.DB.Where("metadata->>'block_id' = ?", blockIDStr).Find(&tasks).Error; err != nil {
			return nil // No tasks found or error, nothing to delete
		}

		// Delete each task associated with this block since it's no longer a task block
		for _, task := range tasks {
			if err := s.taskService.DeleteTask(s.db, task.ID.String()); err != nil {
				return err
			}
		}

		return nil // No need to process content updates since it's not a task block anymore
	}

	// If block type changed to task block, create a new task for it
	if typeChanged && updatedType == string(models.TaskBlock) {
		log.Printf("Block type changed to TaskBlock, creating a new task")
		// Create a new payload with the updated type
		newPayload := make(map[string]interface{})
		maps.Copy(newPayload, payload)

		// Call handleBlockCreated to create the task
		return s.handleBlockCreated(newPayload)
	}

	// Find the task associated with this block
	var task models.Task
	if err := s.db.DB.Where("metadata->>'block_id' = ?", blockIDStr).First(&task).Error; err != nil {
		// No task found for this block but it's a task block - create one
		return s.handleBlockCreated(payload)
	}

	// Check if this update originated from a task sync
	if syncSource, exists := block.Metadata["_sync_source"]; exists && syncSource == "task" {
		// Get last sync timestamp
		if lastSyncStr, exists := block.Metadata["last_synced"].(string); exists {
			lastSync, err := time.Parse(time.RFC3339, lastSyncStr)
			if err == nil {
				// Compare actual timestamps instead of using arbitrary time window
				if block.UpdatedAt.Compare(lastSync) <= 0 {
					log.Printf("Block %s was already synced (UpdatedAt=%v, lastSync=%v), skipping update",
						blockIDStr, block.UpdatedAt.Format(time.RFC3339), lastSync.Format(time.RFC3339))
					return nil
				}
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
	updateData.Metadata = models.TaskMetadata{}
	maps.Copy(updateData.Metadata, task.Metadata)

	// Get completed status from block metadata
	if block.Metadata != nil {
		if completed, exists := block.Metadata["is_completed"].(bool); exists {
			updateData.IsCompleted = completed
		}
	}

	// Always include the sync timestamp
	updateData.Metadata["_sync_source"] = "block"
	updateData.Metadata["last_synced"] = time.Now().Format(time.RFC3339)

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
	var tasks []models.Task
	if err := s.db.DB.Where("metadata->>'block_id' = ?", blockIDStr).Find(&tasks).Error; err != nil {
		return nil // No tasks found or error, nothing to delete
	}

	// Delete each task
	for _, task := range tasks {
		if err := s.taskService.DeleteTask(s.db, task.ID.String()); err != nil {
			return err
		}
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

	// Check if sync source exists - this is a key issue that's causing loops
	if syncSource, exists := task.Metadata["_sync_source"]; exists {
		if syncSource == "block" {
			log.Printf("Task %s was created by block sync, skipping block creation", taskIDStr)
			return nil // Skip creating a block since this task was created from a block
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
				"is_completed": task.IsCompleted,
				"task_id":      task.ID.String(),
				"_sync_source": "task",
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
					// Note found, we can use it
				} else {
					// Note not found, reset noteID to find another note
					noteID = uuid.Nil
				}
			}
		}
	}

	// If no valid noteId in metadata, find a suitable note
	if noteID == uuid.Nil {
		// Find the user's primary note, or any note
		var notes []models.Note
		if err := s.db.DB.Where("user_id = ? AND is_primary = ?", task.UserID, true).Limit(1).Find(&notes).Error; err != nil {
			return err
		}

		if len(notes) > 0 {
			noteID = notes[0].ID
		} else {
			// No primary note found, try to find any note
			if err := s.db.DB.Where("user_id = ?", task.UserID).Limit(1).Find(&notes).Error; err != nil {
				return err
			}
			if len(notes) == 0 {
				// No notes found, create a new one
				newNote := models.Note{
					ID:     uuid.New(),
					UserID: task.UserID,
					Title:  "Tasks",
				}
				if err := s.db.DB.Create(&newNote).Error; err != nil {
					return err
				}
				noteID = newNote.ID
			} else {
				noteID = notes[0].ID
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
			"is_completed": task.IsCompleted,
			"task_id":      task.ID.String(), // Add task ID reference
			"_sync_source": "task",
		},
		"user_id": task.UserID.String(),
	}

	// Permission check parameters
	params := map[string]interface{}{
		"user_id": task.UserID.String(),
	}

	block, err := s.blockService.CreateBlock(s.db, blockData, params)
	if err != nil {
		return err
	}

	// Update task with block_id and store note_id in metadata
	updateData := models.Task{
		NoteID: noteID,
		Metadata: models.TaskMetadata{
			"_sync_source": "task",
			"block_id":     block.ID.String(),
		},
	}

	_, err = s.taskService.UpdateTask(s.db, task.ID.String(), updateData)
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
	if syncSource, exists := task.Metadata["_sync_source"]; exists && syncSource == "block" {
		// Get last sync timestamp
		if lastSyncStr, exists := task.Metadata["last_synced"].(string); exists {
			lastSync, err := time.Parse(time.RFC3339, lastSyncStr)
			if err == nil {
				// Compare actual timestamps instead of using arbitrary time window
				if block.UpdatedAt.Compare(lastSync) <= 0 {
					log.Printf("Block %s was already synced (UpdatedAt=%v, lastSync=%v), skipping update",
						blockIDStr, block.UpdatedAt.Format(time.RFC3339), lastSync.Format(time.RFC3339))
					return nil
				}
			}
		}
	}

	// Prepare block update
	needsUpdate := false
	blockData := map[string]interface{}{}

	// Check if title was updated
	title, titleUpdated := payload["title"].(string)
	var currentText string
	if textVal, exists := block.Content["text"]; exists {
		if textStr, ok := textVal.(string); ok {
			currentText = textStr
		}
	}

	if titleUpdated && title != currentText {
		blockData["content"] = models.BlockContent{
			"text": title,
		}
		needsUpdate = true
	}

	// Check if completion status was updated
	isCompleted, statusUpdated := payload["is_completed"].(bool)

	// If completion status has changed, update metadata
	if statusUpdated {
		// Start with existing metadata
		metadataMap := models.BlockMetadata{}

		// Copy existing metadata
		if block.Metadata != nil {
			maps.Copy(metadataMap, block.Metadata)
		}

		metadataMap["is_completed"] = isCompleted
		metadataMap["_sync_source"] = "task"

		blockData["metadata"] = metadataMap
		needsUpdate = true
	} else if needsUpdate {
		// If we're updating content but not metadata, still add sync marker
		metadataMap := models.BlockMetadata{}

		// Copy existing metadata
		if block.Metadata != nil {
			maps.Copy(metadataMap, block.Metadata)
		}

		metadataMap["_sync_source"] = "task"
		metadataMap["last_synced"] = time.Now().Format(time.RFC3339)
		blockData["metadata"] = metadataMap
	}

	// Only update if something changed
	if !needsUpdate {
		return nil
	}

	// Get user_id for permissions check
	params := map[string]interface{}{
		"user_id": task.UserID.String(),
	}

	// Update block with task data
	_, err := s.blockService.UpdateBlock(s.db, blockIDStr, blockData, params)
	return err
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
	metadataMap := models.BlockMetadata{}

	// Copy existing metadata
	if block.Metadata != nil {
		for k, v := range block.Metadata {
			if k != "_sync_source" && k != "task_deleted" && k != "deleted_at" {
				metadataMap[k] = v
			}
		}
	}

	// Add task deletion markers
	metadataMap["task_deleted"] = true
	metadataMap["_sync_source"] = "task"
	metadataMap["task_id"] = taskIDStr
	metadataMap["deleted_at"] = time.Now().Format(time.RFC3339)

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
