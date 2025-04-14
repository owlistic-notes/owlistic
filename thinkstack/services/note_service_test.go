package services

import (
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/testutils"
	"gorm.io/gorm"
)

func TestCreateNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("INSERT INTO `notes`").
		WithArgs(
			"550e8400-e29b-41d4-a716-446655440000",
			"123e4567-e89b-12d3-a456-426614174000",
			"Test Note",
			"This is a test note.",
			"test,tag",
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	noteService := &NoteService{}
	noteData := map[string]interface{}{
		"user_id": "123e4567-e89b-12d3-a456-426614174000",
		"title":   "Test Note",
		"content": "This is a test note.",
		"tags":    []string{"test", "tag"},
	}

	note, err := noteService.CreateNote(db, noteData)
	assert.NoError(t, err)
	assert.Equal(t, "Test Note", note.Title)
	assert.Equal(t, "This is a test note.", note.Content)
	assert.Equal(t, []string{}, note.Tags)
	assert.NotNil(t, note.CreatedAt)
	assert.NotNil(t, note.UpdatedAt)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetNoteById_NotFound(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT \\* FROM `notes` WHERE id = \\?").WithArgs("non-existent-id").WillReturnError(gorm.ErrRecordNotFound)

	noteService := &NoteService{}

	_, err := noteService.GetNoteById(db, "non-existent-id")
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "note not found")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE `notes` SET").WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg()).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	noteService := &NoteService{}

	updatedData := map[string]interface{}{
		"title": "Updated Title",
	}

	note, err := noteService.UpdateNote(db, "existing-id", updatedData)
	assert.NoError(t, err)
	assert.Equal(t, note.Title, "Updated Title")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("DELETE FROM `notes` WHERE id = \\?").WithArgs("existing-id").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	noteService := &NoteService{}

	err := noteService.DeleteNote(db, "existing-id")
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestListNotesByUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT \\* FROM `notes` WHERE user_id = \\?").WithArgs("user-id").WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "title", "content", "tags"}).AddRow("1", "user-id", "Test Note", "This is a test note.", "test,note"))

	noteService := &NoteService{}

	notes, err := noteService.ListNotesByUser(db, "user-id")
	assert.NoError(t, err)
	assert.NotEmpty(t, notes)
	assert.NoError(t, mock.ExpectationsWereMet())
}
