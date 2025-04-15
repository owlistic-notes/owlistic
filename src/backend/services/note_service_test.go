package services

import (
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/testutils"
	"gorm.io/gorm"
)

func TestCreateNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	noteID := uuid.New()
	userID := uuid.New()
	notebookID := uuid.New()
	eventID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// Create note - match exact column order: user_id, notebook_id, title, is_deleted, id
	mock.ExpectQuery(`INSERT INTO "notes"`).
		WithArgs(userID.String(), notebookID.String(), "Test Note", false, noteID.String()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "notebook_id", "title", "is_deleted"}).
			AddRow(noteID.String(), userID.String(), notebookID.String(), "Test Note", false))

	// Create event expectation
	mock.ExpectQuery(`INSERT INTO "events"`).
		WithArgs(
			"note.created",   // event
			1,                // version
			"note",           // entity
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

	service := &NoteService{}
	noteData := map[string]interface{}{
		"title":       "Test Note",
		"user_id":     userID.String(),
		"notebook_id": notebookID.String(),
	}

	note, err := service.CreateNote(db, noteData)
	assert.NoError(t, err)
	assert.Equal(t, "Test Note", note.Title)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	noteID := uuid.New()
	userID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// Get existing note
	mock.ExpectQuery("SELECT (.+) FROM \"notes\" WHERE id = \\$1 ORDER BY \"notes\".\"id\" LIMIT \\$2").
		WithArgs(noteID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "title", "user_id"}).
			AddRow(noteID.String(), "Old Title", userID.String()))

	// Query for blocks associated with the note
	mock.ExpectQuery(`SELECT \* FROM "blocks" WHERE "blocks"."note_id" = \\$1`).
		WithArgs(noteID.String()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "note_id"}))

	// Update note
	mock.ExpectExec(`UPDATE "notes"`).
		WithArgs("Updated Title", sqlmock.AnyArg(), noteID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Create event expectation
	mock.ExpectQuery(`INSERT INTO "events"`).
		WithArgs(
			"note.updated",   // event
			1,                // version
			"note",           // entity
			"update",         // operation
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

	service := &NoteService{}
	updatedData := map[string]interface{}{
		"title":   "Updated Title",
		"user_id": userID.String(),
	}

	note, err := service.UpdateNote(db, noteID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, "Updated Title", note.Title)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetNoteById_NotFound(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT (.+) FROM \"notes\" WHERE id = \\$1 ORDER BY \"notes\".\"id\" LIMIT \\$2").
		WithArgs("non-existent-id", 1).
		WillReturnError(gorm.ErrRecordNotFound)

	noteService := &NoteService{}

	_, err := noteService.GetNoteById(db, "non-existent-id")
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "note not found")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	existingID := uuid.New()
	userID := uuid.New()
	eventID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// Expect the initial note query
	mock.ExpectQuery(`SELECT \* FROM "notes"`).
		WithArgs(existingID.String(), 1). // Fix: Expect two arguments
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "title", "content", "is_deleted", "update_date"}).
			AddRow(existingID.String(), userID.String(), "Title", "Content", false, nil))

	// Expect the delete
	mock.ExpectExec(`DELETE FROM "notes"`).
		WithArgs(existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect event creation
	mock.ExpectQuery(`INSERT INTO "events"`).
		WithArgs(
			"note.deleted",   // event
			1,                // version
			"note",           // entity
			"delete",         // operation
			sqlmock.AnyArg(), // timestamp
			sqlmock.AnyArg(), // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(eventID.String()))

	mock.ExpectCommit()

	noteService := &NoteService{}
	err := noteService.DeleteNote(db, existingID.String())
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestListNotesByUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New()
	noteID := uuid.New()

	mock.ExpectQuery("SELECT (.+) FROM \"notes\" WHERE user_id = \\$1").
		WithArgs(userID.String()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "title", "content", "is_deleted", "update_date"}).
			AddRow(noteID.String(), userID.String(), "Test Note", "This is a test note.", false, nil))

	noteService := &NoteService{}
	notes, err := noteService.ListNotesByUser(db, userID.String())
	assert.NoError(t, err)
	assert.NotEmpty(t, notes)
	assert.NoError(t, mock.ExpectationsWereMet())
}
