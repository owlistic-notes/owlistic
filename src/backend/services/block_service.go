package services

import (
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
}

type BlockService struct{}

var BlockServiceInstance BlockServiceInterface = &BlockService{}

func (s *BlockService) CreateBlock(db *database.Database, blockData map[string]interface{}) (models.Block, error) {
	blockType, ok := blockData["type"].(string)
	if !ok {
		return models.Block{}, ErrInvalidBlockType
	}

	noteIDStr, ok := blockData["note_id"].(string)
	if !ok {
		return models.Block{}, ErrInvalidInput
	}

	block := models.Block{
		ID:      uuid.New(),
		NoteID:  uuid.Must(uuid.Parse(noteIDStr)),
		Type:    models.BlockType(blockType),
		Content: blockData["content"].(string),
		Order:   blockData["order"].(int),
	}

	if err := db.DB.Create(&block).Error; err != nil {
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
	var block models.Block
	if err := db.DB.First(&block, "id = ?", id).Error; err != nil {
		return models.Block{}, ErrBlockNotFound
	}

	if err := db.DB.Model(&block).Updates(blockData).Error; err != nil {
		return models.Block{}, err
	}
	return block, nil
}

func (s *BlockService) DeleteBlock(db *database.Database, id string) error {
	if err := db.DB.Delete(&models.Block{}, "id = ?", id).Error; err != nil {
		return err
	}
	return nil
}

func (s *BlockService) ListBlocksByNote(db *database.Database, noteID string) ([]models.Block, error) {
	var blocks []models.Block
	if err := db.DB.Where("note_id = ?", noteID).Order("order asc").Find(&blocks).Error; err != nil {
		return nil, err
	}
	return blocks, nil
}
