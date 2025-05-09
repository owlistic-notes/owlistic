package services

import (
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/owlistic/testutils"
	"github.com/stretchr/testify/assert"
)

func TestGetTrashedItems_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New().String()

	// Mock trashed notes query
	mock.ExpectQuery("SELECT (.+) FROM \"notes\" WHERE user_id = (.+) AND deleted_at IS NOT NULL").
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "title", "user_id", "notebook_id", "deleted_at"}).
			AddRow(uuid.New().String(), "Deleted Note", userID, uuid.New().String(), time.Now()))

	// Mock trashed notebooks query
	mock.ExpectQuery("SELECT (.+) FROM \"notebooks\" WHERE user_id = (.+) AND deleted_at IS NOT NULL").
		WithArgs(userID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "name", "user_id", "deleted_at"}).
			AddRow(uuid.New().String(), "Deleted Notebook", userID, time.Now()))

	trashService := &TrashService{}
	result, err := trashService.GetTrashedItems(db, userID)

	assert.NoError(t, err)
	assert.NotNil(t, result)
	assert.Contains(t, result, "notes")
	assert.Contains(t, result, "notebooks")
	// Fix: Don't cast slices incorrectly
	assert.NotEmpty(t, result["notes"])
	assert.NotEmpty(t, result["notebooks"])
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestRestoreItem_Note(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	noteID := uuid.New().String()
	userID := uuid.New().String()

	// Begin transaction
	mock.ExpectBegin()

	// Expect UPDATE for restoring the note
	mock.ExpectExec("UPDATE notes SET deleted_at = NULL WHERE").
		WithArgs(noteID, userID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect UPDATE for restoring blocks
	mock.ExpectExec("UPDATE blocks SET deleted_at = NULL").
		WithArgs(noteID).
		WillReturnResult(sqlmock.NewResult(1, 2))

	// Expect event creation with all 12 required arguments
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"note.restored",  // event
			sqlmock.AnyArg(), // version
			"note",           // entity
			"restore",        // operation
			sqlmock.AnyArg(), // timestamp
			userID,           // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			nil,              // deleted_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	// Expect commit
	mock.ExpectCommit()

	trashService := &TrashService{}
	err := trashService.RestoreItem(db, "note", noteID, userID)

	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestPermanentlyDeleteItem_Notebook(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	notebookID := uuid.New().String()
	userID := uuid.New().String()

	// Begin transaction
	mock.ExpectBegin()

	// Expect DELETE for tasks first (matching implementation order)
	mock.ExpectExec("DELETE FROM tasks WHERE").
		WithArgs(notebookID, userID).
		WillReturnResult(sqlmock.NewResult(1, 2))

	// Expect DELETE for blocks
	mock.ExpectExec("DELETE FROM blocks WHERE").
		WithArgs(notebookID, userID).
		WillReturnResult(sqlmock.NewResult(1, 3))

	// Expect DELETE for notes
	mock.ExpectExec("DELETE FROM notes WHERE notebook_id").
		WithArgs(notebookID, userID).
		WillReturnResult(sqlmock.NewResult(1, 2))

	// Expect DELETE for notebook
	mock.ExpectExec("DELETE FROM notebooks WHERE id").
		WithArgs(notebookID, userID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect event creation with all 12 required arguments
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"notebook.permanent_deleted", // event
			sqlmock.AnyArg(),             // version
			"notebook",                   // entity
			"permanent_delete",           // operation
			sqlmock.AnyArg(),             // timestamp
			userID,                       // actor_id
			sqlmock.AnyArg(),             // data json
			"pending",                    // status
			false,                        // dispatched
			nil,                          // dispatched_at
			nil,                          // deleted_at
			sqlmock.AnyArg(),             // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	// Expect commit
	mock.ExpectCommit()

	trashService := &TrashService{}
	err := trashService.PermanentlyDeleteItem(db, "notebook", notebookID, userID)

	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestEmptyTrash_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New().String()

	// Begin transaction
	mock.ExpectBegin()

	// Expect DELETE for tasks first (matching implementation order)
	mock.ExpectExec("DELETE FROM tasks WHERE").
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(1, 3))

	// Expect DELETE for blocks
	mock.ExpectExec("DELETE FROM blocks WHERE").
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(1, 5))

	// Expect DELETE for notes
	mock.ExpectExec("DELETE FROM notes WHERE user_id").
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(1, 2))

	// Expect DELETE for notebooks
	mock.ExpectExec("DELETE FROM notebooks WHERE user_id").
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect event creation with all 12 required arguments
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"trash.emptied",  // event
			sqlmock.AnyArg(), // version
			"trash",          // entity
			"empty",          // operation
			sqlmock.AnyArg(), // timestamp
			userID,           // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			nil,              // deleted_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	// Expect commit
	mock.ExpectCommit()

	trashService := &TrashService{}
	err := trashService.EmptyTrash(db, userID)

	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
