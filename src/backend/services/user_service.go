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
	GetUsers(db *database.Database, params map[string]interface{}) ([]models.User, error)
}

type UserService struct{}

func (s *UserService) CreateUser(db *database.Database, user models.User) (models.User, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.User{}, tx.Error
	}

	if err := tx.Create(&user).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	event, err := models.NewEvent(
		"user.created",
		"user",
		"create",
		user.ID.String(),
		map[string]interface{}{
			"user_id": user.ID.String(),
			"email":   user.Email,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
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
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.User{}, tx.Error
	}

	var user models.User
	if err := tx.First(&user, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.User{}, ErrUserNotFound
		}
		return models.User{}, err
	}

	if err := tx.Model(&user).Updates(updatedData).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	event, err := models.NewEvent(
		"user.updated",
		"user",
		"update",
		user.ID.String(),
		map[string]interface{}{
			"user_id": user.ID.String(),
			"email":   user.Email,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	return user, nil
}

func (s *UserService) DeleteUser(db *database.Database, id string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	var user models.User
	if err := tx.First(&user, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return err
	}

	// With proper ON DELETE CASCADE constraints, deleting the user
	// will automatically delete all related notebooks, notes, blocks, and tasks
	if err := tx.Delete(&user).Error; err != nil {
		tx.Rollback()
		return err
	}

	event, err := models.NewEvent(
		"user.deleted",
		"user",
		"delete",
		user.ID.String(),
		map[string]interface{}{
			"user_id": user.ID.String(),
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

	return tx.Commit().Error
}

func (s *UserService) GetAllUsers(db *database.Database) ([]models.User, error) {
	var users []models.User
	result := db.DB.Find(&users)
	if result.Error != nil {
		return nil, result.Error
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

	result := query.Find(&users)
	if result.Error != nil {
		return nil, result.Error
	}
	return users, nil
}

var UserServiceInstance UserServiceInterface = &UserService{}
