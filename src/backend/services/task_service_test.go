package services

import (
	"errors"
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/models"
	"github.com/thinkstack/testutils"
)

func TestCreateTask_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("INSERT INTO `tasks`").WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	taskService := &TaskService{}
	uuidValue, _ := uuid.Parse("task-id")
	task := models.Task{ID: uuidValue, Title: "Test Task"}
	createdTask, err := taskService.CreateTask(db, task)
	assert.NoError(t, err)
	assert.Equal(t, createdTask.Title, "Test Task")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetTaskById_NotFound(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT * FROM `tasks` WHERE `id` = ?").WithArgs("non-existent-id").WillReturnError(errors.New("task not found"))

	taskService := &TaskService{}
	_, err := taskService.GetTaskById(db, "non-existent-id")
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "task not found")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateTask_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE `tasks` SET `title` = ? WHERE `id` = ?").WithArgs("Updated Task", "existing-id").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	taskService := &TaskService{}
	updatedData := models.Task{Title: "Updated Task"}
	task, err := taskService.UpdateTask(db, "existing-id", updatedData)
	assert.NoError(t, err)
	assert.Equal(t, task.Title, "Updated Task")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteTask_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("DELETE FROM `tasks` WHERE `id` = ?").WithArgs("existing-id").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	taskService := &TaskService{}
	err := taskService.DeleteTask(db, "existing-id")
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
