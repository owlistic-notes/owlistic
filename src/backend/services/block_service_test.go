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

	mock.ExpectBegin()
	mock.ExpectQuery(`INSERT INTO "blocks"`).
		WithArgs(
			noteID.String(),  // note_id
			"text",           // type
			"Test Content",   // content
			"",               // metadata
			1,                // order
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at", "updated_at"}).
			AddRow(uuid.New().String(), time.Now(), time.Now()))
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

	mock.ExpectQuery(`SELECT \* FROM "blocks"`).
		WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg()). // id and LIMIT args
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at",
		}).AddRow(
			blockID.String(),
			noteID.String(),
			"text",
			"Test Content",
			"",
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

	// First query to get the block
	mock.ExpectQuery(`SELECT \* FROM "blocks"`).
		WithArgs(sqlmock.AnyArg(), sqlmock.AnyArg()). // id and LIMIT args
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at",
		}).AddRow(
			blockID.String(),
			noteID.String(),
			"text",
			"Old Content",
			"",
			1,
			time.Now(),
			time.Now(),
		))

	// Update query
	mock.ExpectBegin()
	mock.ExpectExec(`UPDATE "blocks"`).
		WithArgs(
			"Updated Content", // content
			sqlmock.AnyArg(),  // updated_at
			blockID.String(),  // where id = ?
		).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	service := &BlockService{}
	blockData := map[string]interface{}{
		"content": "Updated Content",
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

	mock.ExpectBegin()
	mock.ExpectExec(`DELETE FROM "blocks"`).
		WithArgs(blockID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	service := &BlockService{}
	err := service.DeleteBlock(db, blockID.String())
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
