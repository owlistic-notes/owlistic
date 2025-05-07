package services

import (
	"encoding/json"
	"errors"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/thinkstack/broker"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

// SyncHandlerService handles bidirectional synchronization between blocks and tasks
type SyncHandlerService struct {
	db           *database.Database
	msgChan      chan broker.KafkaMessage
	stopChan     chan struct{}
	isRunning    bool
	taskService  TaskServiceInterface
	blockService BlockServiceInterface
}

// NewSyncHandlerService creates a new sync handler instance
func NewSyncHandlerService(db *database.Database) *SyncHandlerService {
	return &SyncHandlerService{
		db:           db,
		stopChan:     make(chan struct{}),
		isRunning:    false,
		taskService:  TaskServiceInstance,
		blockService: BlockServiceInstance,
	}
}

// Start begins the sync handler processing
func (s *SyncHandlerService) Start() {
	if s.isRunning {
		return
	}

	// Subscribe to block and task events
	topics := []string{
		broker.BlockEventsTopic,
		broker.TaskEventsTopic,
	}

	var err error
	s.msgChan, err = broker.InitConsumer(topics, "sync-handler-group")
	if err != nil {
		log.Printf("Warning: Failed to initialize sync handler consumer: %v", err)
		return
	}

	s.isRunning = true
	go s.processEvents()
	log.Println("Block-Task Sync Handler started successfully")
}

// Stop halts the sync handler processing
func (s *SyncHandlerService) Stop() {
	if !s.isRunning {
		return
	}

	s.isRunning = false
	s.stopChan <- struct{}{}
	log.Println("Block-Task Sync Handler stopped")
}

// processEvents handles incoming Kafka events
func (s *SyncHandlerService) processEvents() {
	for {
		select {
		case <-s.stopChan:
			return
		case msg := <-s.msgChan:
			// Process the event based on its key
			eventType := msg.Key
			if err := s.handleSyncEvent(eventType, []byte(msg.Value)); err != nil {
				log.Printf("Error handling sync event %s: %v", eventType, err)
			}
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

	// Check if this is a sync event to prevent infinite loops
	if _, isSync := message.Payload["_sync_source"]; isSync {
		// Skip events that were triggered by sync operations
		return nil
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
		return errors.New("missing block_id in event payload")
	}

	// Get block type to ensure it's a task block
	blockType, ok := payload["block_type"].(string)
	if !ok || blockType != string(models.TaskBlock) {
		return nil // Not a task block, nothing to do
	}

	// Get user ID
	userIDStr, ok := payload["user_id"].(string)
	if !ok {
		return errors.New("missing user_id in event payload")
	}

	// Get text content for task title from content field
	contentInterface, hasContent := payload["content"]
	if !hasContent {
		return nil // No content to use for task
	}

	// Extract content as map
	var content map[string]interface{}

	switch c := contentInterface.(type) {
	case map[string]interface{}:
		content = c
	default:
		contentBytes, err := json.Marshal(contentInterface)
		if err != nil {
			return err
		}
		if err := json.Unmarshal(contentBytes, &content); err != nil {
			return err
		}
	}

	// Get text content for task title
	text, ok := content["text"].(string)
	if !ok || text == "" {
		text = "Untitled Task" // Default title if none provided
	}

	// Check if a task already exists for this block
	var existingTask models.Task
	err := s.db.DB.Where("block_id = ?", blockIDStr).First(&existingTask).Error
	if err == nil {
		// Task already exists, nothing to do
		return nil
	}

	// Create new task linked to this block
	taskData := map[string]interface{}{
		"user_id":  userIDStr,
		"block_id": blockIDStr,
		"title":    text,
		"metadata": map[string]interface{}{
			"_sync_source": "block",
		},
	}

	// Extract completed status from metadata if available
	if metadata, ok := content["metadata"].(map[string]interface{}); ok {
		if isCompleted, exists := metadata["is_completed"].(bool); exists {
			taskData["is_completed"] = isCompleted
		}
	} else if metadata, ok := payload["metadata"].(map[string]interface{}); ok {
		if isCompleted, exists := metadata["is_completed"].(bool); exists {
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
		return errors.New("missing block_id in event payload")
	}

	// Get the full block to check current type
	var block models.Block
	if err := s.db.DB.Where("id = ?", blockIDStr).First(&block).Error; err != nil {
		return err
	}

	// Check if the block type has changed
	updatedType, hasType := payload["block_type"].(string)
	typeChanged := hasType && string(block.Type) != updatedType

	// If block type changed from task to another type, delete the associated task
	if typeChanged && string(block.Type) == string(models.TaskBlock) && updatedType != string(models.TaskBlock) {
		log.Printf("Block type changed from TaskBlock to %s, deleting associated task", updatedType)
		// Find any tasks associated with this block and delete them
		var tasks []models.Task
		if err := s.db.DB.Where("block_id = ?", blockIDStr).Find(&tasks).Error; err != nil {
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
		for k, v := range payload {
			newPayload[k] = v
		}

		// Call handleBlockCreated to create the task
		return s.handleBlockCreated(newPayload)
	}

	// Only continue if this is a task block (either unchanged or still a task block after update)
	if !hasType && block.Type != models.TaskBlock || hasType && updatedType != string(models.TaskBlock) {
		return nil // Not a task block, nothing to do
	}

	// Extract content for the update
	contentInterface, hasContent := payload["content"]
	if !hasContent {
		return nil // No content to sync
	}

	// Extract content as map
	var content map[string]interface{}

	switch c := contentInterface.(type) {
	case map[string]interface{}:
		content = c
	default:
		contentBytes, err := json.Marshal(contentInterface)
		if err != nil {
			return err
		}
		if err := json.Unmarshal(contentBytes, &content); err != nil {
			return err
		}
	}

	// Find the task associated with this block
	var task models.Task
	if err := s.db.DB.Where("block_id = ?", blockIDStr).First(&task).Error; err != nil {
		// No task found for this block but it's a task block - create one
		return s.handleBlockCreated(payload)
	}

	// Update task with block data
	updateData := models.Task{}

	// Update title if text content is available
	if text, ok := content["text"].(string); ok {
		updateData.Title = text
	}

	// Initialize metadata if needed
	if task.Metadata == nil {
		task.Metadata = models.TaskMetadata{}
	}

	// Create a copy of metadata
	updateData.Metadata = models.TaskMetadata{}
	for k, v := range task.Metadata {
		updateData.Metadata[k] = v
	}
	updateData.Metadata["_sync_source"] = "block"

	// Check for completion status in metadata
	isCompleted := task.IsCompleted // Default to current value
	metadataFound := false

	// Look for metadata in content
	if metadataInterface, exists := content["metadata"]; exists {
		var metadata map[string]interface{}
		switch m := metadataInterface.(type) {
		case map[string]interface{}:
			metadata = m
			if completed, exists := metadata["is_completed"].(bool); exists {
				isCompleted = completed
				metadataFound = true
			}
		}
	}

	// Also check for separate metadata field in the payload
	if !metadataFound {
		if metadataInterface, exists := payload["metadata"]; exists {
			var metadata map[string]interface{}
			switch m := metadataInterface.(type) {
			case map[string]interface{}:
				metadata = m
				if completed, exists := metadata["is_completed"].(bool); exists {
					isCompleted = completed
				}
			}
		}
	}

	updateData.IsCompleted = isCompleted

	// Only update if there are changes to apply
	if updateData.Title != "" || updateData.IsCompleted != task.IsCompleted || len(updateData.Metadata) > 0 {
		_, err := s.taskService.UpdateTask(s.db, task.ID.String(), updateData)
		if err != nil {
			return err
		}
	}

	return nil
}

// handleBlockDeleted removes associated tasks when a block is deleted
func (s *SyncHandlerService) handleBlockDeleted(payload map[string]interface{}) error {
	blockIDStr, ok := payload["block_id"].(string)
	if !ok {
		return errors.New("missing block_id in event payload")
	}

	// Find all tasks associated with this block
	var tasks []models.Task
	if err := s.db.DB.Where("block_id = ?", blockIDStr).Find(&tasks).Error; err != nil {
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
		return errors.New("missing task_id in event payload")
	}

	// Check if task already has a block_id
	var task models.Task
	if err := s.db.DB.Where("id = ?", taskIDStr).First(&task).Error; err != nil {
		return err
	}

	// If task has no block ID, create a block for it
	if task.BlockID == uuid.Nil {
		return s.createBlockForTask(task)
	}

	// If task has a block ID, check if the block exists and is of type TaskBlock
	var block models.Block
	if err := s.db.DB.Where("id = ?", task.BlockID).First(&block).Error; err != nil {
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
			"metadata": models.BlockContent{
				"is_completed": task.IsCompleted,
				"_sync_source": "task",
			},
		}

		params := map[string]interface{}{
			"user_id": task.UserID.String(),
		}

		_, err := s.blockService.UpdateBlock(s.db, task.BlockID.String(), blockData, params)
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
					ID:        uuid.New(),
					UserID:    task.UserID,
					Title:     "Tasks",
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
		"metadata": models.BlockContent{
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
		BlockID: block.ID,
		Metadata: models.TaskMetadata{
			"_sync_source": "task",
			"note_id":      noteID.String(),
		},
	}

	_, err = s.taskService.UpdateTask(s.db, task.ID.String(), updateData)
	return err
}

// handleTaskUpdated syncs changes from a task to its associated block
func (s *SyncHandlerService) handleTaskUpdated(payload map[string]interface{}) error {
	taskIDStr, ok := payload["task_id"].(string)
	if !ok {
		return errors.New("missing task_id in event payload")
	}

	// Get the complete task
	var task models.Task
	if err := s.db.DB.Where("id = ?", taskIDStr).First(&task).Error; err != nil {
		return err
	}

	// Skip if no block ID is associated
	if task.BlockID == uuid.Nil {
		// Create a block for this task
		return s.createBlockForTask(task)
	}

	// Get the associated block
	var block models.Block
	if err := s.db.DB.Where("id = ?", task.BlockID).First(&block).Error; err != nil {
		// Block doesn't exist anymore - create a new one
		return s.createBlockForTask(task)
	}

	// Check if block type matches - if not, update it to task block
	if block.Type != models.TaskBlock {
		blockData := map[string]interface{}{
			"type": string(models.TaskBlock),
			"content": map[string]interface{}{
				"text": task.Title,
			},
			"metadata": map[string]interface{}{
				"is_completed": task.IsCompleted,
				"_sync_source": "task",
			},
		}

		params := map[string]interface{}{
			"user_id": task.UserID.String(),
		}

		_, err := s.blockService.UpdateBlock(s.db, task.BlockID.String(), blockData, params)
		return err
	}

	// Prepare block update
	needsUpdate := false
	blockData := map[string]interface{}{}

	// Check if title was updated
	title, titleUpdated := payload["title"].(string)
	currentText := ""
	if block.Content != nil {
		if textVal, exists := block.Content["text"]; exists {
			if textStr, ok := textVal.(string); ok {
				currentText = textStr
			}
		}
	}

	if titleUpdated && title != currentText {
		blockData["content"] = map[string]interface{}{
			"text": title,
		}
		needsUpdate = true
	}

	// Check if completion status was updated
	isCompleted, statusUpdated := payload["is_completed"].(bool)

	// If completion status has changed, update metadata
	if statusUpdated {
		// Create metadata map
		metadataMap := map[string]interface{}{
			"is_completed": isCompleted,
			"_sync_source": "task",
		}

		blockData["metadata"] = metadataMap
		needsUpdate = true
	} else if needsUpdate {
		// If we're updating content but not metadata, still add sync marker
		blockData["metadata"] = map[string]interface{}{
			"_sync_source": "task",
		}
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
	_, err := s.blockService.UpdateBlock(s.db, task.BlockID.String(), blockData, params)
	return err
}

// handleTaskDeleted handles cleanup when a task is deleted
func (s *SyncHandlerService) handleTaskDeleted(payload map[string]interface{}) error {
	taskIDStr, ok := payload["task_id"].(string)
	if !ok {
		return errors.New("missing task_id in event payload")
	}

	// We need to find the block_id from the task data
	// Since the task is deleted, we can't query it directly
	// Check if the payload includes the block_id
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
	blockData := map[string]interface{}{
		"metadata": models.BlockContent{
			"task_deleted": true,
			"_sync_source": "task",
			"task_id":      taskIDStr, // Keep reference to deleted task ID
			"deleted_at":   time.Now().Format(time.RFC3339),
		},
	}

	// Keep the original metadata properties
	if block.Metadata != nil {
		for k, v := range block.Metadata {
			if k != "_sync_source" && k != "task_deleted" && k != "deleted_at" {
				blockData["metadata"].(models.BlockContent)[k] = v
			}
		}
	}

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
	_, err := s.blockService.UpdateBlock(s.db, blockIDStr, blockData, params)
	return err
}
