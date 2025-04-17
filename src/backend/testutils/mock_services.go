package testutils

import (
	"github.com/google/uuid"
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

// MockUserService is a mock implementation of UserServiceInterface
type MockUserService struct{}

func (m *MockUserService) CreateUser(db *database.Database, user models.User) (models.User, error) {
	return user, nil
}

func (m *MockUserService) GetUserById(db *database.Database, id string) (models.User, error) {
	return models.User{
		ID:    uuid.MustParse(id),
		Email: "test@example.com",
	}, nil
}

func (m *MockUserService) UpdateUser(db *database.Database, id string, user models.User) (models.User, error) {
	user.ID = uuid.MustParse(id)
	return user, nil
}

func (m *MockUserService) DeleteUser(db *database.Database, id string) error {
	return nil
}

func (m *MockUserService) GetAllUsers(db *database.Database) ([]models.User, error) {
	return []models.User{
		{ID: uuid.New(), Email: "test1@example.com"},
		{ID: uuid.New(), Email: "test2@example.com"},
	}, nil
}

func (m *MockUserService) GetUsers(db *database.Database, params map[string]interface{}) ([]models.User, error) {
	return []models.User{
		{ID: uuid.New(), Email: "test1@example.com"},
		{ID: uuid.New(), Email: "test2@example.com"},
	}, nil
}
