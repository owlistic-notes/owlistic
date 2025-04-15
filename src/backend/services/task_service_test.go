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

	taskId := uuid.New()

	mock.ExpectBegin()
	mock.ExpectQuery(`INSERT INTO "tasks" \("user_id","note_id","title","description","is_completed","due_date","id"\) VALUES \(\$1,\$2,\$3,\$4,\$5,\$6,\$7\) RETURNING "id"`).
		WithArgs(
			uuid.Nil,    // user_id
			nil,         // note_id
			"Test Task", // title
			"",          // description
			false,       // is_completed
			"",          // due_date
			taskId,      // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(taskId.String()))
	mock.ExpectCommit()

	taskService := &TaskService{}
	task := models.Task{
		ID:    taskId,
		Title: "Test Task",
	}

	createdTask, err := taskService.CreateTask(db, task)
	assert.NoError(t, err)
	assert.Equal(t, task.Title, createdTask.Title)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetTaskById_NotFound(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT (.+) FROM \"tasks\" WHERE id = \\$1 ORDER BY \"tasks\".\"id\" LIMIT \\$2").
		WithArgs("non-existent-id", 1).
		WillReturnError(errors.New("task not found"))

	taskService := &TaskService{}
	_, err := taskService.GetTaskById(db, "non-existent-id")
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "task not found")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateTask_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	existingID := uuid.New()

	// Mock the SELECT query that GORM performs first
	mock.ExpectQuery("SELECT (.+) FROM \"tasks\" WHERE id = \\$1 ORDER BY \"tasks\".\"id\" LIMIT \\$2").
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "note_id", "title", "description", "is_completed", "due_date"}).
			AddRow(existingID.String(), uuid.Nil.String(), nil, "Old Title", "", false, ""))

	// Mock the UPDATE query
	mock.ExpectBegin()
	mock.ExpectExec("UPDATE \"tasks\" SET (.+) WHERE").
		WithArgs("Updated Task", existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	taskService := &TaskService{}
	updatedData := models.Task{Title: "Updated Task"}
	task, err := taskService.UpdateTask(db, existingID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, task.Title, "Updated Task")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteTask_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("DELETE FROM \"tasks\" WHERE id = \\$1").
		WithArgs("existing-id").
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	taskService := &TaskService{}
	err := taskService.DeleteTask(db, "existing-id")
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
