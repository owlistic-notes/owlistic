package services

import (
	"errors"

	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"gorm.io/gorm"
)

type UserServiceInterface interface {
	CreateUser(db *database.Database, user models.User) (models.User, error)
	GetUserById(db *database.Database, id string) (models.User, error)
	UpdateUser(db *database.Database, id string, updatedData models.User) (models.User, error)
	DeleteUser(db *database.Database, id string) error
	GetAllUsers(db *database.Database) ([]models.User, error)
	GetUsers(db *database.Database, params map[string]interface{}) ([]models.User, error)
}

type UserService struct{}

func (s *UserService) CreateUser(db *database.Database, user models.User) (models.User, error) {
	// Assign a UUID if not already set
	if user.ID == uuid.Nil {
		user.ID = uuid.New()
	}

	// Check if email already exists
	var existingUser models.User
	if result := db.DB.Where("email = ?", user.Email).First(&existingUser); result.Error == nil {
		return models.User{}, errors.New("user with that email already exists")
	} else if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
		return models.User{}, result.Error
	}

	// Create the user
	if result := db.DB.Create(&user); result.Error != nil {
		return models.User{}, result.Error
	}

	return user, nil
}

func (s *UserService) GetUserById(db *database.Database, id string) (models.User, error) {
	var user models.User
	if err := db.DB.First(&user, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.User{}, ErrUserNotFound
		}
		return models.User{}, err
	}
	return user, nil
}

func (s *UserService) UpdateUser(db *database.Database, id string, updatedData models.User) (models.User, error) {
	var user models.User
	if err := db.DB.First(&user, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.User{}, ErrUserNotFound
		}
		return models.User{}, err
	}

	// Only update non-zero values
	updates := map[string]interface{}{}
	if updatedData.Email != "" {
		updates["email"] = updatedData.Email
	}
	if updatedData.PasswordHash != "" {
		updates["password_hash"] = updatedData.PasswordHash
	}

	if err := db.DB.Model(&user).Updates(updates).Error; err != nil {
		return models.User{}, err
	}

	// Get updated user
	if err := db.DB.First(&user, "id = ?", id).Error; err != nil {
		return models.User{}, err
	}

	return user, nil
}

func (s *UserService) DeleteUser(db *database.Database, id string) error {
	var user models.User
	if err := db.DB.First(&user, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return err
	}

	return db.DB.Delete(&user).Error
}

func (s *UserService) GetAllUsers(db *database.Database) ([]models.User, error) {
	var users []models.User
	if err := db.DB.Find(&users).Error; err != nil {
		return nil, err
	}
	return users, nil
}

func (s *UserService) GetUsers(db *database.Database, params map[string]interface{}) ([]models.User, error) {
	var users []models.User
	query := db.DB

	// Apply filters based on params
	if email, ok := params["email"].(string); ok && email != "" {
		query = query.Where("email = ?", email)
	}

	if err := query.Find(&users).Error; err != nil {
		return nil, err
	}
	return users, nil
}

var UserServiceInstance UserServiceInterface = &UserService{}
