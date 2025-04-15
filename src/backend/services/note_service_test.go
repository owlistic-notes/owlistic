package services

import (
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/testutils"
	"gorm.io/gorm"
)

func TestCreateNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userId := uuid.MustParse("123e4567-e89b-12d3-a456-426614174000")
	notebookId := uuid.MustParse("068bcfa6-1516-42cb-be98-064198e1b300")
	now := time.Now()

	noteData := map[string]interface{}{
		"user_id":     userId.String(),
		"notebook_id": notebookId.String(),
		"title":       "Test Note",
		"blocks": []map[string]interface{}{
			{
				"type":    "text",
				"content": "Test Content",
				"order":   1,
			},
		},
	}

	mock.ExpectBegin()
	mock.ExpectQuery(`INSERT INTO "notes" \("user_id","notebook_id","title","tags","is_deleted","id"\) VALUES \(\$1,\$2,\$3,\(NULL\),\$4,\$5\)`).
		WithArgs(
			userId.String(),     // user_id
			notebookId.String(), // notebook_id
			"Test Note",         // title
			false,               // is_deleted
			sqlmock.AnyArg(),    // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at", "updated_at"}).
			AddRow(uuid.New().String(), now, now))

	mock.ExpectQuery(`INSERT INTO "blocks" \("note_id","type","content","metadata","order","id"\) VALUES \(\$1,\$2,\$3,\$4,\$5,\$6\)`).
		WithArgs(
			sqlmock.AnyArg(), // note_id
			"text",           // type
			"Test Content",   // content
			"{}",             // metadata (default value)
			1,                // order
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at", "updated_at"}).
			AddRow(uuid.New().String(), now, now))

	mock.ExpectCommit()

	noteService := &NoteService{}
	createdNote, err := noteService.CreateNote(db, noteData)

	assert.NoError(t, err)
	assert.Equal(t, noteData["title"], createdNote.Title)
	assert.Equal(t, 1, len(createdNote.Blocks))
	if assert.NotEmpty(t, createdNote.Blocks) {
		assert.Equal(t, "Test Content", createdNote.Blocks[0].Content)
	}
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
	now := time.Now()

	mock.ExpectQuery("SELECT (.+) FROM \"notes\"").
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "user_id", "notebook_id", "title", "tags",
			"is_deleted", "created_at", "updated_at"}).
			AddRow(existingID.String(), userID.String(), uuid.Nil.String(),
				"Old Title", nil, false, now, now))

	mock.ExpectQuery("SELECT (.+) FROM \"blocks\"").
		WithArgs(existingID.String()).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "note_id", "type", "content", "order",
			"created_at", "updated_at"}))

	mock.ExpectBegin()
	mock.ExpectExec(`UPDATE "notes" SET "user_id"=\$1,"notebook_id"=\$2,"title"=\$3,"tags"=\(NULL\),"is_deleted"=\$4,"created_at"=\$5,"updated_at"=\$6 WHERE "id" = \$7`).
		WithArgs(
			userID.String(),     // user_id
			uuid.Nil.String(),   // notebook_id
			"Updated Title",     // title
			false,               // is_deleted
			sqlmock.AnyArg(),    // created_at
			sqlmock.AnyArg(),    // updated_at
			existingID.String(), // id
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	noteService := &NoteService{}
	updatedData := map[string]interface{}{
		"title": "Updated Title",
	}

	note, err := noteService.UpdateNote(db, existingID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, "Updated Title", note.Title)
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
