package services

import (
	"errors"

	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"gorm.io/gorm"
)

type TaskServiceInterface interface {
	CreateTask(db *database.Database, task models.Task) (models.Task, error)
	GetTaskById(db *database.Database, id string) (models.Task, error)
	UpdateTask(db *database.Database, id string, updatedData models.Task) (models.Task, error)
	DeleteTask(db *database.Database, id string) error
	GetAllTasks(db *database.Database) ([]models.Task, error)
}

type TaskService struct{}

func (s *TaskService) CreateTask(db *database.Database, task models.Task) (models.Task, error) {
	if err := db.DB.Create(&task).Error; err != nil {
		return models.Task{}, err
	}
	return task, nil
}

func (s *TaskService) GetTaskById(db *database.Database, id string) (models.Task, error) {
	var task models.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Task{}, ErrTaskNotFound
		}
		return models.Task{}, err
	}
	return task, nil
}

func (s *TaskService) UpdateTask(db *database.Database, id string, updatedData models.Task) (models.Task, error) {
	var task models.Task
	if err := db.DB.First(&task, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Task{}, ErrTaskNotFound
		}
		return models.Task{}, err
	}

	if err := db.DB.Model(&task).Updates(updatedData).Error; err != nil {
		return models.Task{}, err
	}

	return task, nil
}

func (s *TaskService) DeleteTask(db *database.Database, id string) error {
	if err := db.DB.Delete(&models.Task{}, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrTaskNotFound
		}
		return err
	}
	return nil
}

func (s *TaskService) GetAllTasks(db *database.Database) ([]models.Task, error) {
	var tasks []models.Task
	result := db.DB.Find(&tasks)
	if result.Error != nil {
		return nil, result.Error
	}
	return tasks, nil
}

var TaskServiceInstance TaskServiceInterface = &TaskService{}
