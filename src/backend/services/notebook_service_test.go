package services

import (
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/testutils"
)

func TestCreateNotebook_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New()
	notebookID := uuid.New()

	mock.ExpectBegin()

	// Expect notebook creation
	mock.ExpectQuery(`INSERT INTO "notebooks"`).
		WithArgs(
			sqlmock.AnyArg(),              // id
			userID.String(),			   // user_id
			"Test Notebook",               // name
			"Description",                 // description
			false,                         // is_deleted
			sqlmock.AnyArg(),              // created_at
			sqlmock.AnyArg(),              // updated_at
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(notebookID))

	// Expect event creation with exact fields
	mock.ExpectQuery(`INSERT INTO "events"`).
		WithArgs(
			"notebook.created", // event
			1,                  // version
			"notebook",         // entity
			"create",           // operation
			sqlmock.AnyArg(),   // timestamp
			userID,             // actor_id
			sqlmock.AnyArg(),   // data json
			"pending",          // status
			false,              // dispatched
			nil,                // dispatched_at
			sqlmock.AnyArg(),   // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(userID.String()))

	mock.ExpectCommit()

	service := &NotebookService{}
	notebookData := map[string]interface{}{
		"name":        "Test Notebook",
		"description": "Description",
		"user_id":     userID.String(),
	}

	notebook, err := service.CreateNotebook(db, notebookData)
	assert.NoError(t, err)
	assert.Equal(t, "Test Notebook", notebook.Name)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetNotebookById_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	notebookID := uuid.New()
	userID := uuid.New()

	rows := sqlmock.NewRows([]string{"id", "user_id", "name", "description", "is_deleted"}).
		AddRow(notebookID, userID, "Test Notebook", "Description", false)

	mock.ExpectQuery(`SELECT \* FROM "notebooks"`).
		WithArgs(notebookID.String(), 1).
		WillReturnRows(rows)

	mock.ExpectQuery(`SELECT (.+) FROM "notes"`).
		WillReturnRows(sqlmock.NewRows([]string{"id"}))

	notebookService := &NotebookService{}
	notebook, err := notebookService.GetNotebookById(db, notebookID.String())

	assert.NoError(t, err)
	assert.Equal(t, "Test Notebook", notebook.Name)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateNotebook_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	notebookID := uuid.New()
	userID := uuid.New()

	mock.ExpectBegin()

	// Initial notebook query
	mock.ExpectQuery(`SELECT \* FROM "notebooks"`).
		WithArgs(notebookID.String()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "user_id", "name", "description", "is_deleted", "created_at", "updated_at",
		}).AddRow(
			notebookID,
			userID,
			"Old Name",
			"Old Description",
			false,
			time.Now(),
			time.Now(),
		))

	// Update notebook
	mock.ExpectExec(`UPDATE "notebooks"`).
		WithArgs(
			"Updated Name",        // name
			"Updated Description", // description
			sqlmock.AnyArg(),      // updated_at
			notebookID.String(),   // where id = ?
		).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect event creation
	mock.ExpectQuery(`INSERT INTO "events"`).
		WithArgs(
			"notebook.updated", // event
			1,                  // version
			"notebook",         // entity
			"update",           // operation
			sqlmock.AnyArg(),   // timestamp
			userID.String(),    // actor_id
			sqlmock.AnyArg(),   // data json
			"pending",          // status
			false,              // dispatched
			nil,                // dispatched_at
			sqlmock.AnyArg(),   // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New()))

	mock.ExpectCommit()

	service := &NotebookService{}
	updatedData := map[string]interface{}{
		"name":        "Updated Name",
		"description": "Updated Description",
	}

	notebook, err := service.UpdateNotebook(db, notebookID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, "Updated Name", notebook.Name)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteNotebook_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	notebookID := uuid.New()
	userID := uuid.New()

	mock.ExpectQuery(`SELECT \* FROM "notebooks"`).
		WithArgs(notebookID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "name"}).
			AddRow(notebookID, userID, "Test Notebook"))

	mock.ExpectBegin()
	mock.ExpectExec(`UPDATE "notebooks" SET "is_deleted"=\$1,"updated_at"=\$2 WHERE "id" = \$3`).
		WithArgs(true, sqlmock.AnyArg(), notebookID).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	notebookService := &NotebookService{}
	err := notebookService.DeleteNotebook(db, notebookID.String())
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestListNotebooksByUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New()

	rows := sqlmock.NewRows([]string{"id", "user_id", "name", "description", "is_deleted"}).
		AddRow(uuid.New(), userID, "Notebook 1", "Description 1", false).
		AddRow(uuid.New(), userID, "Notebook 2", "Description 2", false)

	mock.ExpectQuery(`SELECT (.+) FROM "notebooks"`).
		WithArgs(userID.String()).
		WillReturnRows(rows)

	mock.ExpectQuery(`SELECT (.+) FROM "notes"`).
		WillReturnRows(sqlmock.NewRows([]string{"id"}))

	notebookService := &NotebookService{}
	notebooks, err := notebookService.ListNotebooksByUser(db, userID.String())

	assert.NoError(t, err)
	assert.Equal(t, 2, len(notebooks))
	assert.NoError(t, mock.ExpectationsWereMet())
}
