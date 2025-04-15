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

	mock.ExpectBegin()
	mock.ExpectQuery(`INSERT INTO "notes" \("user_id","title","content","is_deleted","id"\) VALUES \(\$1,\$2,\$3,\$4,\$5\) RETURNING "id"`).
		WithArgs(
			"123e4567-e89b-12d3-a456-426614174000", // user_id
			"Test Note",                            // title
			"This is a test note.",                 // content
			false,                                  // is_deleted
			sqlmock.AnyArg(),                       // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(noteID.String()))
	mock.ExpectCommit()

	noteService := &NoteService{}
	noteData := map[string]interface{}{
		"user_id": "123e4567-e89b-12d3-a456-426614174000",
		"title":   "Test Note",
		"content": "This is a test note.",
	}

	note, err := noteService.CreateNote(db, noteData)
	assert.NoError(t, err)
	assert.Equal(t, "Test Note", note.Title)
	assert.Equal(t, "This is a test note.", note.Content)
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

func TestUpdateNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	existingID := uuid.New()
	userID := uuid.New()

	// Mock the SELECT query that GORM performs first
	mock.ExpectQuery("SELECT (.+) FROM \"notes\" WHERE id = \\$1 ORDER BY \"notes\".\"id\" LIMIT \\$2").
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "title", "content", "is_deleted", "update_date"}).
			AddRow(existingID.String(), userID.String(), "Old Title", "Old Content", false, nil))

	// Mock the UPDATE query
	mock.ExpectBegin()
	mock.ExpectExec("UPDATE \"notes\" SET (.+) WHERE").
		WithArgs("Updated Title", existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	noteService := &NoteService{}
	updatedData := map[string]interface{}{
		"title": "Updated Title",
	}

	note, err := noteService.UpdateNote(db, existingID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, note.Title, "Updated Title")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	existingID := uuid.New()
	userID := uuid.New()

	// Mock the SELECT query that GORM performs first
	mock.ExpectQuery("SELECT (.+) FROM \"notes\" WHERE id = \\$1 ORDER BY \"notes\".\"id\" LIMIT \\$2").
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "title", "content", "is_deleted", "update_date"}).
			AddRow(existingID.String(), userID.String(), "Title", "Content", false, nil))

	// Mock the DELETE query
	mock.ExpectBegin()
	mock.ExpectExec("DELETE FROM \"notes\" WHERE").
		WithArgs(existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))
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
