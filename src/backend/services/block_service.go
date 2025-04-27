package services

import (
	"errors"
	"fmt"
	"log"
	"time"

	"strconv"

	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

type BlockServiceInterface interface {
	CreateBlock(db *database.Database, blockData map[string]interface{}, params map[string]interface{}) (models.Block, error)
	GetBlockById(db *database.Database, id string, params map[string]interface{}) (models.Block, error)
	UpdateBlock(db *database.Database, id string, blockData map[string]interface{}, params map[string]interface{}) (models.Block, error)
	DeleteBlock(db *database.Database, id string, params map[string]interface{}) error
	ListBlocksByNote(db *database.Database, noteID string, params map[string]interface{}) ([]models.Block, error)
	GetBlocks(db *database.Database, params map[string]interface{}) ([]models.Block, error)
	GetBlockWithStyles(db *database.Database, id string, params map[string]interface{}) (models.Block, map[string]interface{}, error)
}

type BlockService struct{}

func (s *BlockService) CreateBlock(db *database.Database, blockData map[string]interface{}, params map[string]interface{}) (models.Block, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Block{}, tx.Error
	}

	blockType, ok := blockData["type"].(string)
	if !ok {
		return models.Block{}, ErrInvalidBlockType
	}

	noteIDStr, ok := blockData["note_id"].(string)
	if !ok {
		return models.Block{}, ErrInvalidInput
	}

	// Extract user_id from params for permission check
	userIDStr, ok := params["user_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Block{}, errors.New("user_id must be provided in parameters")
	}

	// Check if user has editor access to the parent note using the new method
	hasAccess, err := RoleServiceInstance.HasNoteAccess(db, userIDStr, noteIDStr, "editor")
	if err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if !hasAccess {
		tx.Rollback()
		return models.Block{}, errors.New("not authorized to add blocks to this note")
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		tx.Rollback()
		return models.Block{}, ErrInvalidInput
	}

	// Handle order value conversion from float64 to int
	var order int
	switch o := blockData["order"].(type) {
	case float64:
		// JSON numbers come as float64, convert to int
		order = int(o)
	case string:
		// Handle case where order was sent as string
		orderInt, err := strconv.Atoi(o)
		if err != nil {
			return models.Block{}, ErrInvalidInput
		}
		order = orderInt
	case int:
		// Already an int
		order = o
	default:
		return models.Block{}, ErrInvalidInput
	}

	// Process content based on input type
	var content models.BlockContent
	if contentData, ok := blockData["content"].(map[string]interface{}); ok {
		// If we get a structured content object, use it directly
		content = contentData
	} else if contentStr, ok := blockData["content"].(string); ok {
		// If content is provided as a string, maintain backward compatibility
		// by storing it as {"text": content} in the JSONB field
		content = models.BlockContent{"text": contentStr}
	} else {
		tx.Rollback()
		return models.Block{}, ErrInvalidInput
	}

	// Handle metadata if provided
	metadata := models.BlockContent{}
	if metaData, ok := blockData["metadata"].(map[string]interface{}); ok {
		metadata = metaData
	}

	blockID := uuid.New()
	block := models.Block{
		ID:       blockID,
		NoteID:   uuid.Must(uuid.Parse(noteIDStr)),
		UserID:   userID,
		Type:     models.BlockType(blockType),
		Content:  content,
		Metadata: metadata,
		Order:    order,
	}

	if err := tx.Create(&block).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	actorID, _ := blockData["user_id"].(string)
	event, err := models.NewEvent(
		"block.created", // Standardized event type
		"block",
		"create",
		actorID,
		map[string]interface{}{
			"block_id": block.ID.String(),
			"note_id":  block.NoteID.String(),
			"user_id":  block.UserID.String(),
			"type":     string(block.Type),
			"order":    block.Order,
			"content":  block.Content,
			"metadata": block.Metadata,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	return block, nil
}

func (s *BlockService) GetBlockById(db *database.Database, id string, params map[string]interface{}) (models.Block, error) {
	// Get user ID from params for permission check
	userIDStr, ok := params["user_id"].(string)
	if !ok {
		return models.Block{}, errors.New("user_id must be provided in parameters")
	}

	// Check if user has viewer access using the new method
	hasAccess, err := RoleServiceInstance.HasBlockAccess(db, userIDStr, id, "viewer")
	if err != nil {
		return models.Block{}, err
	}

	if !hasAccess {
		return models.Block{}, errors.New("not authorized to access this block")
	}

	var block models.Block
	if err := db.DB.First(&block, "id = ?", id).Error; err != nil {
		return models.Block{}, ErrBlockNotFound
	}
	return block, nil
}

func (s *BlockService) UpdateBlock(db *database.Database, id string, blockData map[string]interface{}, params map[string]interface{}) (models.Block, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Block{}, tx.Error
	}

	// Get user ID from params for permission check
	userIDStr, ok := params["user_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Block{}, errors.New("user_id must be provided in parameters")
	}

	// Get block to determine the note ID
	var block models.Block
	if err := tx.First(&block, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return models.Block{}, ErrBlockNotFound
	}

	// Check if user has editor access to the parent note using the new method
	hasAccess, err := RoleServiceInstance.HasBlockAccess(db, userIDStr, id, "editor")
	if err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if !hasAccess {
		tx.Rollback()
		return models.Block{}, errors.New("not authorized to update this block")
	}

	eventData := map[string]interface{}{
		"id":         block.ID,
		"note_id":    block.NoteID,
		"user_id":    block.UserID,
		"updated_at": time.Now().UTC(),
	}

	// Handle content updates
	if contentInterface, exists := blockData["content"]; exists {
		var updatedContent models.BlockContent

		switch content := contentInterface.(type) {
		case map[string]interface{}:
			// If we get a structured content object, use it directly
			updatedContent = models.BlockContent(content)
		case string:
			// If content is provided as a string, convert to proper format
			updatedContent = models.BlockContent{"text": content}
		default:
			tx.Rollback()
			return models.Block{}, ErrInvalidInput
		}

		// Set the processed content to both blockData and eventData
		eventData["content"] = updatedContent
		blockData["content"] = updatedContent
	}

	if blockType, ok := blockData["type"].(string); ok {
		eventData["type"] = blockType
	}

	// Create the event
	event, err := models.NewEvent(
		"block.updated",
		"block",
		"update",
		userIDStr,
		eventData,
	)

	if err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	// Update the block with the modified data
	if err := tx.Model(&block).Updates(blockData).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	// Fetch the updated block to return
	if err := tx.First(&block, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	return block, nil
}

func (s *BlockService) DeleteBlock(db *database.Database, id string, params map[string]interface{}) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	// Get user ID from params for permission check
	userIDStr, ok := params["user_id"].(string)
	if !ok {
		tx.Rollback()
		return errors.New("user_id must be provided in parameters")
	}

	var block models.Block
	if err := tx.First(&block, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Check if user has editor access to the parent note using the new method
	hasAccess, err := RoleServiceInstance.HasBlockAccess(db, userIDStr, id, "editor")
	if err != nil {
		tx.Rollback()
		log.Printf("Permission check error: %v when checking user %s access to block %s",
			err, userIDStr, id)
		return err
	}

	if !hasAccess {
		tx.Rollback()
		return errors.New("not authorized to delete this block")
	}

	// With proper ON DELETE CASCADE constraints, deleting the block
	// will automatically delete its tasks
	if err := tx.Delete(&block).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Create an event entry instead of directly publishing
	event, err := models.NewEvent(
		"block.deleted", // Standardized event type
		"block",
		"delete",
		block.UserID.String(), // Use the block's owner as the actor
		map[string]interface{}{
			"block_id": block.ID.String(),
			"note_id":  block.NoteID.String(),
			"user_id":  block.UserID.String(),
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

func (s *BlockService) ListBlocksByNote(db *database.Database, noteID string, params map[string]interface{}) ([]models.Block, error) {
	// Get user ID from params for permission check
	userIDStr, ok := params["user_id"].(string)
	if !ok {
		return nil, errors.New("user_id must be provided in parameters")
	}

	// Check if user has viewer access to the note
	hasAccess, err := RoleServiceInstance.HasNoteAccess(db, userIDStr, noteID, "viewer")
	if err != nil {
		return nil, err
	}

	if !hasAccess {
		return nil, errors.New("not authorized to access blocks in this note")
	}

	var blocks []models.Block
	if err := db.DB.Where("note_id = ?", noteID).Order("\"order\" asc").Find(&blocks).Error; err != nil {
		return nil, err
	}
	return blocks, nil
}

func (s *BlockService) GetBlocks(db *database.Database, params map[string]interface{}) ([]models.Block, error) {
	var blocks []models.Block
	query := db.DB

	// Debug received params with more details
	log.Printf("GetBlocks received params: %+v with types:", params)
	for k, v := range params {
		log.Printf("  param %s: %v (type: %T)", k, v, v)
	}

	// Check if user_id is in query string parameters
	userIDStr := ""
	userIDValue, userIDExists := params["user_id"]

	if !userIDExists {
		log.Printf("WARNING: user_id not found in params map. This might be an API handler issue.")
		return nil, errors.New("user_id parameter is required but missing")
	}

	// Handle various types of user_id
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

	log.Printf("Using user_id: %s", userIDStr)

	// Apply user filter
	query = query.Where("user_id = ?", userIDStr)

	// Apply additional filters
	if noteID, ok := params["note_id"].(string); ok && noteID != "" {
		// Check if user has access to this note
		hasAccess, err := RoleServiceInstance.HasNoteAccess(db, userIDStr, noteID, "viewer")
		if err != nil {
			return nil, err
		}

		if !hasAccess {
			return nil, errors.New("not authorized to access blocks from this note")
		}

		query = query.Where("note_id = ?", noteID)
		log.Printf("Filtering by note_id: %s", noteID)
	}

	if blockType, ok := params["type"].(string); ok && blockType != "" {
		query = query.Where("type = ?", blockType)
	}

	// Pagination support
	var page, pageSize int

	// Get page number (default to 1 if not provided)
	if pageVal, ok := params["page"]; ok {
		switch v := pageVal.(type) {
		case int:
			page = v
		case float64:
			page = int(v)
		case string:
			if p, err := strconv.Atoi(v); err == nil {
				page = p
			}
		}
	}
	if page <= 0 {
		page = 1
	}

	// Get page size (default to 100 if not provided)
	if sizeVal, ok := params["page_size"]; ok {
		switch v := sizeVal.(type) {
		case int:
			pageSize = v
		case float64:
			pageSize = int(v)
		case string:
			if p, err := strconv.Atoi(v); err == nil {
				pageSize = p
			}
		}
	}
	if pageSize <= 0 {
		pageSize = 100 // Default page size
	} else if pageSize > 500 {
		pageSize = 500 // Maximum page size
	}

	// Get total count for pagination metadata
	var totalCount int64
	if countRequested, ok := params["count_total"].(bool); ok && countRequested {
		if err := query.Model(&models.Block{}).Count(&totalCount).Error; err != nil {
			log.Printf("Error counting blocks: %v", err)
			// Non-fatal, continue with query
		}
	}

	// Apply pagination if requested
	if page > 0 && pageSize > 0 {
		offset := (page - 1) * pageSize
		query = query.Offset(offset).Limit(pageSize)
		log.Printf("Applying pagination: page %d, size %d, offset %d", page, pageSize, offset)
	}

	if err := query.Order("\"order\" asc").Find(&blocks).Error; err != nil {
		log.Printf("Database error in GetBlocks: %v", err)
		return nil, err
	}

	log.Printf("Found %d blocks (total count: %d)", len(blocks), totalCount)
	return blocks, nil
}

// NewBlockService creates a new instance of BlockService
func NewBlockService() BlockServiceInterface {
	return &BlockService{}
}

// Don't initialize here, will be set properly in main.go
var BlockServiceInstance BlockServiceInterface

// GetBlockWithStyles returns a block with its style information separately
func (s *BlockService) GetBlockWithStyles(db *database.Database, id string, params map[string]interface{}) (models.Block, map[string]interface{}, error) {
	// First get the block
	block, err := s.GetBlockById(db, id, params)
	if err != nil {
		return models.Block{}, nil, err
	}

	// Extract style information
	styleInfo := map[string]interface{}{
		"styles": block.GetInlineStyles(),
	}

	return block, styleInfo, nil
}
