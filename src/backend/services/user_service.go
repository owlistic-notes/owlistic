package services

import (
	"errors"

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
}

type UserService struct{}

func (s *UserService) CreateUser(db *database.Database, user models.User) (models.User, error) {
	if err := db.DB.Create(&user).Error; err != nil {
		return models.User{}, err
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

	if err := db.DB.Model(&user).Updates(updatedData).Error; err != nil {
		return models.User{}, err
	}

	return user, nil
}

func (s *UserService) DeleteUser(db *database.Database, id string) error {
	if err := db.DB.Delete(&models.User{}, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return err
	}
	return nil
}

func (s *UserService) GetAllUsers(db *database.Database) ([]models.User, error) {
	var users []models.User
	result := db.DB.Find(&users)
	if result.Error != nil {
		return nil, result.Error
	}
	return users, nil
}

var UserServiceInstance UserServiceInterface = &UserService{}
