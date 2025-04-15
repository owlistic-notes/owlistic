package testutils

import (
	"github.com/stretchr/testify/mock"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
)

// MockBlockService mocks the BlockServiceInterface for testing
type MockBlockService struct {
	mock.Mock
}

// Implement existing methods
func (m *MockBlockService) CreateBlock(db *database.Database, blockData map[string]interface{}) (models.Block, error) {
	args := m.Called(db, blockData)
	return args.Get(0).(models.Block), args.Error(1)
}

func (m *MockBlockService) GetBlockById(db *database.Database, id string) (models.Block, error) {
	args := m.Called(db, id)
	return args.Get(0).(models.Block), args.Error(1)
}

func (m *MockBlockService) UpdateBlock(db *database.Database, id string, blockData map[string]interface{}) (models.Block, error) {
	args := m.Called(db, id, blockData)
	return args.Get(0).(models.Block), args.Error(1)
}

func (m *MockBlockService) DeleteBlock(db *database.Database, id string) error {
	args := m.Called(db, id)
	return args.Error(0)
}

func (m *MockBlockService) ListBlocksByNote(db *database.Database, noteID string) ([]models.Block, error) {
	args := m.Called(db, noteID)
	return args.Get(0).([]models.Block), args.Error(1)
}

// Add the new method to match updated interface
func (m *MockBlockService) GetBlocks(db *database.Database, params map[string]interface{}) ([]models.Block, error) {
	args := m.Called(db, params)
	return args.Get(0).([]models.Block), args.Error(1)
}

// Additional mock implementations for other services can be added as needed
