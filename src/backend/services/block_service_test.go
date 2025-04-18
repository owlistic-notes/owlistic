package services

import (
	"testing"
	"time"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/models"
	"github.com/thinkstack/testutils"
)

func TestCreateBlock_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	noteID := uuid.New()
	blockID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// First expect the note existence check - use backticks format
	mock.ExpectQuery(`SELECT count\(\*\) FROM "notes" WHERE id = \$1`).
		WithArgs(noteID.String()).
		WillReturnRows(sqlmock.NewRows([]string{"count"}).AddRow(1))

	// Then expect the block creation
	mock.ExpectQuery("INSERT INTO \"blocks\"").
		WithArgs(
			noteID.String(),  // note_id
			"text",           // type
			"Test Content",   // content
			"{}",             // metadata
			1,                // order
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at", "updated_at"}).
			AddRow(blockID.String(), time.Now(), time.Now()))

	// Expect creating an event for the block creation
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"block.created",  // event
			1,                // version
			"block",          // entity
			"create",         // operation
			sqlmock.AnyArg(), // timestamp
			"system",         // actor_id - default when not provided
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	// Expect commit
	mock.ExpectCommit()

	service := &BlockService{}
	blockData := map[string]interface{}{
		"note_id": noteID.String(),
		"type":    "text",
		"content": "Test Content",
		"order":   1,
	}

	block, err := service.CreateBlock(db, blockData)
	assert.NoError(t, err)
	assert.Equal(t, models.TextBlock, block.Type)
	assert.Equal(t, "Test Content", block.Content)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetBlockById_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	blockID := uuid.New()
	noteID := uuid.New()

	mock.ExpectQuery("SELECT \\* FROM \"blocks\"").
		WithArgs(blockID.String(), 1). // id and LIMIT args
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at",
		}).AddRow(
			blockID.String(),
			noteID.String(),
			"text",
			"Test Content",
			"{}",
			1,
			time.Now(),
			time.Now(),
		))

	service := &BlockService{}
	block, err := service.GetBlockById(db, blockID.String())
	assert.NoError(t, err)
	assert.Equal(t, blockID, block.ID)
	assert.Equal(t, "Test Content", block.Content)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateBlock_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	blockID := uuid.New()
	noteID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// First query to get the block
	mock.ExpectQuery("SELECT \\* FROM \"blocks\"").
		WithArgs(blockID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at",
		}).AddRow(
			blockID.String(),
			noteID.String(),
			"text",
			"Old Content",
			"{}", // metadata
			1,
			time.Now(),
			time.Now(),
		))

	// Update the event creation expectation
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"block.updated",  // event
			1,                // version
			"block",          // entity
			"update",         // operation
			sqlmock.AnyArg(), // timestamp
			"user-123",       // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New()))

	// Update query - Fix the order of arguments to match the actual implementation
	mock.ExpectExec("UPDATE \"blocks\"").
		WithArgs(
			"user-123",        // actor_id - first parameter
			"Updated Content", // content - second parameter
			"text",            // type - third parameter
			sqlmock.AnyArg(),  // updated_at - fourth parameter
			blockID.String(),  // where id = ? - fifth parameter
		).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect transaction commit
	mock.ExpectCommit()

	service := &BlockService{}
	blockData := map[string]interface{}{
		"content":  "Updated Content",
		"type":     "text",
		"actor_id": "user-123",
	}

	_, err := service.UpdateBlock(db, blockID.String(), blockData)
	assert.NoError(t, err)
	assert.Equal(t, "Updated Content", blockData["content"])
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestListBlocksByNote_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	noteID := uuid.New()
	blockID := uuid.New()

	mock.ExpectQuery(`SELECT \* FROM "blocks" WHERE note_id = \$1`).
		WithArgs(noteID.String()).
		WillReturnRows(sqlmock.NewRows([]string{"id", "note_id", "type", "content", "order"}).
			AddRow(blockID.String(), noteID.String(), "text", "Test Content", 1))

	service := &BlockService{}
	blocks, err := service.ListBlocksByNote(db, noteID.String())
	assert.NoError(t, err)
	assert.Len(t, blocks, 1)
	assert.Equal(t, "Test Content", blocks[0].Content)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteBlock_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	blockID := uuid.New()
	noteID := uuid.New()

	mock.ExpectBegin()
	mock.ExpectQuery("SELECT \\* FROM \"blocks\"").
		WithArgs(blockID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "note_id", "type", "content", "metadata", "order"}).
			AddRow(blockID.String(), noteID.String(), "text", "Content",
				"{}", 1))

	mock.ExpectExec("DELETE FROM \"blocks\"").
		WithArgs(blockID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect creating an event for the block deletion
	mock.ExpectQuery("INSERT INTO \"events\"").
		WithArgs(
			"block.deleted",  // event
			1,                // version
			"block",          // entity
			"delete",         // operation
			sqlmock.AnyArg(), // timestamp
			"system",         // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New().String()))

	mock.ExpectCommit()

	service := &BlockService{}
	err := service.DeleteBlock(db, blockID.String())
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateBlock_WithEvent(t *testing.T) {
	// ...existing code...
}
