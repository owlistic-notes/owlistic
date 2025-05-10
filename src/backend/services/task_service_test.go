package services

import (
	"errors"
	"testing"
	"time"

	"owlistic-notes/owlistic/models"
	"owlistic-notes/owlistic/testutils"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"gorm.io/gorm"
)

func TestCreateTask_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	taskID := uuid.New()
	userID := uuid.New()
	noteID := uuid.New()
	blockID := uuid.New()

	// First expect a transaction
	mock.ExpectBegin()

	// Check if user exists - First check users table
	mock.ExpectQuery(`SELECT count\(\*\) FROM "users" WHERE id = \$1`).
		WithArgs(userID.String()).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(1))

	// Expect a query to check if the note exists - use backticks format
	mock.ExpectQuery(`SELECT \* FROM "notes" WHERE id = \$1 ORDER BY "notes"."id" LIMIT \$2`).
		WithArgs(noteID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "title", "content", "created_at", "updated_at"}).
			AddRow(noteID.String(), "Test Note", "Test Content", time.Now(), time.Now()))

	// Expect a query to find the last block by order - FIXED: Added LIMIT parameter
	mock.ExpectQuery(`SELECT \* FROM "blocks" WHERE note_id = \$1 ORDER BY `+"`order`"+` DESC,"blocks"."id" LIMIT \$2`).
		WithArgs(noteID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "note_id", "type", "content", "metadata", "order"}).
			AddRow(blockID.String(),
				noteID.String(),
				"text",
				[]byte(`{"text":"Test Content"}`), // Content as JSONB
				[]byte(`{}`),                      // Metadata as JSONB
				1))

	// Expect task creation - use sqlmock.AnyArg() for the ID (which is the first parameter now)
	mock.ExpectQuery(`INSERT INTO "tasks"`).
		WithArgs(
			userID.String(),    // user_id
			blockID.String(),   // block_id
			"Test Task",        // title
			"Test Description", // description
			false,              // is_completed
			"",                 // due_date
			sqlmock.AnyArg(),   // id - Use AnyArg() to accept any UUID here
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(taskID.String()))

	// Expect event creation
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"task.created",   // event
			1,                // version
			"task",           // entity
			"create",         // operation
			sqlmock.AnyArg(), // timestamp
			userID.String(),  // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	mock.ExpectCommit()

	service := &TaskService{}
	taskData := map[string]interface{}{
		"title":       "Test Task",
		"description": "Test Description",
		"user_id":     userID.String(),
		"note_id":     noteID.String(),
	}

	createdTask, err := service.CreateTask(db, taskData)
	assert.NoError(t, err)
	assert.Equal(t, taskData["title"], createdTask.Title)
	assert.Equal(t, blockID, createdTask.BlockID)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestCreateTask_CreateNewBlock(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	taskID := uuid.New()
	userID := uuid.New()
	noteID := uuid.New()
	blockID := uuid.New()
	eventID := uuid.New()

	// First expect a transaction
	mock.ExpectBegin()

	// Check if user exists - First check users table
	mock.ExpectQuery(`SELECT count\(\*\) FROM "users" WHERE id = \$1`).
		WithArgs(userID.String()).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(1))

	// Expect a query to check if the note exists - use backticks format
	mock.ExpectQuery(`SELECT \* FROM "notes" WHERE id = \$1 ORDER BY "notes"."id" LIMIT \$2`).
		WithArgs(noteID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "title", "content", "created_at", "updated_at"}).
			AddRow(noteID.String(), "Test Note", "Test Content", time.Now(), time.Now()))

	// Expect a query to find the last block by order - FIXED: Added LIMIT parameter
	mock.ExpectQuery(`SELECT \* FROM "blocks" WHERE note_id = \$1 ORDER BY `+"`order`"+` DESC,"blocks"."id" LIMIT \$2`).
		WithArgs(noteID.String(), 1).
		WillReturnError(gorm.ErrRecordNotFound)

	// Expect new block creation with metadata parameter
	mock.ExpectQuery("INSERT INTO \"blocks\"").
		WithArgs(
			noteID.String(),  // note_id
			"task",           // type
			1,                // order
			sqlmock.AnyArg(), // id
			sqlmock.AnyArg(), // content as JSONB
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(blockID.String()))

	// Expect task creation
	mock.ExpectQuery("INSERT INTO \"tasks\"").
		WithArgs(
			userID.String(),  // user_id
			blockID.String(), // block_id
			"Test Task", "",  // title
			false,            // is_completed
			"",               // description
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(taskID.String()))

	// Expect event creation
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"task.created",   // event
			1,                // version
			"task",           // entity
			"create",         // operation
			sqlmock.AnyArg(), // timestamp
			userID.String(),  // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(eventID.String()))

	mock.ExpectCommit()

	service := &TaskService{}
	taskData := map[string]interface{}{
		"title":   "Test Task",
		"user_id": userID.String(),
		"note_id": noteID.String(),
	}

	createdTask, err := service.CreateTask(db, taskData)
	assert.NoError(t, err)
	assert.Equal(t, taskData["title"], createdTask.Title)
	assert.NotEqual(t, uuid.Nil, createdTask.BlockID)
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
	now := time.Now()

	// Begin transaction
	mock.ExpectBegin()

	// Mock the SELECT query that GORM performs first
	mock.ExpectQuery("SELECT (.+) FROM \"tasks\" WHERE id = \\$1 ORDER BY \"tasks\".\"id\" LIMIT \\$2").
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "user_id", "block_id", "title", "description",
			"is_completed", "due_date", "created_at", "updated_at"}).
			AddRow(existingID.String(), uuid.Nil.String(), uuid.Nil.String(),
				"Old Title", "", false, "", now, now))

	// Mock the UPDATE query
	mock.ExpectExec("UPDATE \"tasks\" SET").
		WithArgs("Updated Task", sqlmock.AnyArg(), existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect event creation for the update operation
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"task.updated",   // event
			1,                // version
			"task",           // entity
			"update",         // operation
			sqlmock.AnyArg(), // timestamp
			sqlmock.AnyArg(), // actor_id - might be null in the implementation
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	// Expect commit
	mock.ExpectCommit()

	taskService := &TaskService{}
	updatedData := models.Task{Title: "Updated Task"}
	task, err := taskService.UpdateTask(db, existingID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, "Updated Task", task.Title)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteTask_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	existingID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// Mock the SELECT query that GORM performs first
	mock.ExpectQuery(`SELECT \* FROM "tasks" WHERE id = \$1 ORDER BY "tasks"."id" LIMIT \$2`).
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "user_id", "block_id", "title", "description",
			"is_completed", "due_date"}).
			AddRow(existingID.String(), uuid.Nil.String(), uuid.Nil.String(),
				"Test Task", "", false, ""))

	// Mock the DELETE query
	mock.ExpectExec("DELETE FROM \"tasks\" WHERE").
		WithArgs(existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect event creation for the delete operation
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"task.deleted",   // event
			1,                // version
			"task",           // entity
			"delete",         // operation
			sqlmock.AnyArg(), // timestamp
			sqlmock.AnyArg(), // actor_id - might be null in implementation
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	// Expect commit
	mock.ExpectCommit()

	taskService := &TaskService{}
	err := taskService.DeleteTask(db, existingID.String())
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
