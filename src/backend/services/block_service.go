package services

import (
	"errors"
	"log"
	"time"

	"strconv"

	"github.com/google/uuid"
	"github.com/thinkstack/broker"
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

	block := models.Block{
		ID:      uuid.New(),
		NoteID:  uuid.Must(uuid.Parse(noteIDStr)),
		Type:    models.BlockType(blockType),
		Content: blockData["content"].(string),
		Order:   order,
	}

	if err := tx.Create(&block).Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.Block{}, err
	}

	// Publish event after successful commit using standard EventType
	payload := map[string]any{
		"block_id": block.ID.String(),
		"note_id":  block.NoteID.String(),
		"type":     string(block.Type),
		"order":    block.Order,
	}

	if err := broker.PublishEvent(broker.NoteEventsTopic, broker.BlockCreated, payload); err != nil {
		log.Printf("Failed to publish block created event: %v", err)
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

	// Only add content and type if they exist in blockData
	if content, ok := blockData["content"].(string); ok {
		eventData["content"] = content
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

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return err
	}

	// Publish event after successful commit using standard EventType
	payload := map[string]any{
		"block_id": block.ID.String(),
		"note_id":  block.NoteID.String(),
	}

	if err := broker.PublishEvent(broker.NoteEventsTopic, broker.BlockDeleted, payload); err != nil {
		log.Printf("Failed to publish block deleted event: %v", err)
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
