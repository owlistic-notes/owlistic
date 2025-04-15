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

	notebookID := uuid.New()
	userID := "123e4567-e89b-12d3-a456-426614174000"

	mock.ExpectBegin()
	mock.ExpectQuery(`INSERT INTO "notebooks"`).
		WithArgs(
			uuid.Must(uuid.Parse(userID)), // UserID
			"Test Notebook",               // Name
			"Description",                 // Description
			false,                         // IsDeleted
			sqlmock.AnyArg(),              // ID
		).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at", "updated_at"}).
			AddRow(notebookID, time.Now(), time.Now()))
	mock.ExpectCommit()

	notebookService := &NotebookService{}
	notebookData := map[string]interface{}{
		"user_id":     userID,
		"name":        "Test Notebook",
		"description": "Description",
	}

	notebook, err := notebookService.CreateNotebook(db, notebookData)
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

	mock.ExpectQuery(`SELECT \* FROM "notebooks"`).
		WithArgs(notebookID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "name"}).
			AddRow(notebookID, userID, "Old Name"))

	mock.ExpectBegin()
	mock.ExpectExec(`UPDATE "notebooks"`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	notebookService := &NotebookService{}
	updatedData := map[string]interface{}{
		"name": "Updated Name",
	}

	_, err := notebookService.UpdateNotebook(db, notebookID.String(), updatedData)
	assert.NoError(t, err)
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
