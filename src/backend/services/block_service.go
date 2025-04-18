package services

import (
	"errors"
	"time"

	"strconv"

	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

type BlockServiceInterface interface {
	CreateBlock(db *database.Database, blockData map[string]interface{}) (models.Block, error)
	GetBlockById(db *database.Database, id string) (models.Block, error)
	UpdateBlock(db *database.Database, id string, blockData map[string]interface{}) (models.Block, error)
	DeleteBlock(db *database.Database, id string) error
	ListBlocksByNote(db *database.Database, noteID string) ([]models.Block, error)
	GetBlocks(db *database.Database, params map[string]interface{}) ([]models.Block, error)
}

type BlockService struct{}

var BlockServiceInstance BlockServiceInterface = &BlockService{}

func (s *BlockService) CreateBlock(db *database.Database, blockData map[string]interface{}) (models.Block, error) {
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

	// Validate that the note exists before creating the block
	var noteCount int64
	if err := tx.Model(&models.Note{}).Where("id = ?", noteIDStr).Count(&noteCount).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if noteCount == 0 {
		tx.Rollback()
		return models.Block{}, errors.New("note not found")
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

	block := models.Block{
		ID:       uuid.New(),
		NoteID:   uuid.Must(uuid.Parse(noteIDStr)),
		Type:     models.BlockType(blockType),
		Content:  content,
		Metadata: metadata,
		Order:    order,
	}

	if err := tx.Create(&block).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	// Create an event entry instead of directly publishing
	actorID, _ := blockData["user_id"].(string)
	if actorID == "" {
		// Fallback to a system user ID if none provided
		actorID = "system"
	}

	event, err := models.NewEvent(
		"block.created", // Standardized event type
		"block",
		"create",
		actorID,
		map[string]interface{}{
			"block_id": block.ID.String(),
			"note_id":  block.NoteID.String(),
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

func (s *BlockService) GetBlockById(db *database.Database, id string) (models.Block, error) {
	var block models.Block
	if err := db.DB.First(&block, "id = ?", id).Error; err != nil {
		return models.Block{}, ErrBlockNotFound
	}
	return block, nil
}

func (s *BlockService) UpdateBlock(db *database.Database, id string, blockData map[string]interface{}) (models.Block, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.Block{}, tx.Error
	}

	var block models.Block
	if err := tx.First(&block, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return models.Block{}, ErrBlockNotFound
	}

	actorID, ok := blockData["actor_id"].(string)
	if !ok {
		tx.Rollback()
		return models.Block{}, ErrInvalidInput
	}

	eventData := map[string]interface{}{
		"id":         block.ID,
		"note_id":    block.NoteID,
		"updated_at": time.Now().UTC(),
	}

	// Handle content updates
	if content, exists := blockData["content"]; exists {
		if contentMap, ok := content.(map[string]interface{}); ok {
			// If we get a structured content object, use it directly
			eventData["content"] = contentMap
		} else if contentStr, ok := content.(string); ok {
			// If content is provided as a string, maintain backward compatibility
			contentObj := models.BlockContent{"text": contentStr}
			eventData["content"] = contentObj
			// Update the content in blockData to use the proper format
			blockData["content"] = contentObj
		} else {
			tx.Rollback()
			return models.Block{}, ErrInvalidInput
		}
	}

	if blockType, ok := blockData["type"].(string); ok {
		eventData["type"] = blockType
	}

	event, err := models.NewEvent(
		"block.updated",
		"block",
		"update",
		actorID,
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

	if err := tx.Model(&block).Updates(blockData).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	return block, nil
}

func (s *BlockService) DeleteBlock(db *database.Database, id string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	var block models.Block
	if err := tx.First(&block, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return err
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
		"system", // Default to system since no actor ID is typically provided for deletion
		map[string]interface{}{
			"block_id": block.ID.String(),
			"note_id":  block.NoteID.String(),
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

func (s *BlockService) ListBlocksByNote(db *database.Database, noteID string) ([]models.Block, error) {
	var blocks []models.Block
	if err := db.DB.Where("note_id = ?", noteID).Order("\"order\" asc").Find(&blocks).Error; err != nil {
		return nil, err
	}
	return blocks, nil
}

func (s *BlockService) GetBlocks(db *database.Database, params map[string]interface{}) ([]models.Block, error) {
	var blocks []models.Block
	query := db.DB

	// Apply filters based on params
	if noteID, ok := params["note_id"].(string); ok && noteID != "" {
		query = query.Where("note_id = ?", noteID)
	}

	if blockType, ok := params["type"].(string); ok && blockType != "" {
		query = query.Where("type = ?", blockType)
	}

	if err := query.Order("\"order\" asc").Find(&blocks).Error; err != nil {
		return nil, err
	}

	return blocks, nil
}
