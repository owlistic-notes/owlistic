package services

import (
	"regexp"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func setupMockDB(t *testing.T) (*database.Database, sqlmock.Sqlmock) {
	// Create a mock database connection
	mockDB, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("Failed to create mock database: %v", err)
	}

	dialector := postgres.New(postgres.Config{
		DSN:                  "sqlmock_db_0",
		DriverName:           "postgres",
		Conn:                 mockDB,
		PreferSimpleProtocol: true,
	})

	db, err := gorm.Open(dialector, &gorm.Config{})
	if err != nil {
		t.Fatalf("Failed to open gorm connection: %v", err)
	}

	return &database.Database{DB: db}, mock
}

func TestCreateBlock_Success(t *testing.T) {
	mockDB, mock := setupMockDB(t)
	blockService := BlockService{}

	userID := uuid.MustParse("f3c4b2a0-5d8e-4b1c-8f3b-7a2e5d6f7c8b")
	noteID := uuid.MustParse("288bafb8-baab-45b9-8f3b-42715d5d752c")
	blockID := uuid.MustParse("9fe002da-ccea-462d-99d8-2df3c9e09407")
	eventID := uuid.MustParse("847b0278-3931-4561-89a5-334fb336981a")

	// First expect the transaction to begin
	mock.ExpectBegin()

	// Then set up expectations for the note existence check
	noteCountRows := sqlmock.NewRows([]string{"count"}).AddRow(1)
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT count(*) FROM "notes" WHERE id = $1`)).
		WithArgs(noteID.String()).
		WillReturnRows(noteCountRows)

	// Set up expectations for block creation
	mock.ExpectQuery(`INSERT INTO "blocks"`).
		WithArgs(
			noteID.String(),  // note_id
			models.TextBlock, // type
			1,                // order
			sqlmock.AnyArg(), // id
			sqlmock.AnyArg(), // content as JSONB
			sqlmock.AnyArg(), // metadata as JSONB
		).
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at", "updated_at"}).
			AddRow(blockID.String(), time.Now(), time.Now()))

	// Set up expectations for event creation
	eventRows := sqlmock.NewRows([]string{"id"}).AddRow(eventID)
	mock.ExpectQuery(regexp.QuoteMeta(`INSERT INTO "events"`)).
		WithArgs(
			"block.created",  // type
			sqlmock.AnyArg(), // timestamp
			"block",          // entity_type
			"create",         // action
			sqlmock.AnyArg(), // data (JSONB)
			"user-123",       // actor_id
			sqlmock.AnyArg(), // metadata (JSONB)
			"pending",        // status
			false,            // processed
			nil,              // processed_at
			sqlmock.AnyArg(), // failed_attempts (JSONB)
		).
		WillReturnRows(eventRows)

	// Finally, expect the transaction to be committed
	mock.ExpectCommit()

	// Create block data
	blockData := map[string]interface{}{
		"note_id": noteID.String(),
		"type":    "text",
		"content": "Test Content", // Using string content to test backward compatibility
		"order":   1,
		"user_id": "user-123",
	}

	// Call the service
	block, err := blockService.CreateBlock(mockDB, blockData, map[string]interface{}{"user_id": userID.String()})

	// Assert expectations
	assert.NoError(t, err)
	assert.Equal(t, models.TextBlock, block.Type)

	// Check for the content in the structured format
	assert.Equal(t, models.BlockContent{"text": "Test Content"}, block.Content)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetBlockById_Success(t *testing.T) {
	mockDB, mock := setupMockDB(t)
	blockService := BlockService{}

	userID := uuid.MustParse("f3c4b2a0-5d8e-4b1c-8f3b-7a2e5d6f7c8b")
	blockID := uuid.MustParse("06a27d54-c96e-4916-a572-b4b47a87a539")
	noteID := uuid.MustParse("288bafb8-baab-45b9-8f3b-42715d5d752c")
	now := time.Now()

	// Create a mock BlockContent as JSON
	contentJSON := []byte(`{"text":"Test Content"}`)
	metadataJSON := []byte(`{}`)

	// Set up expectation for GetBlockById
	rows := sqlmock.NewRows([]string{"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at"}).
		AddRow(blockID, noteID, "text", contentJSON, metadataJSON, 1, now, now)

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "blocks" WHERE id = $1 ORDER BY "blocks"."id" LIMIT $2`)).
		WithArgs(blockID.String(), 1).
		WillReturnRows(rows)

	// Call the service
	block, err := blockService.GetBlockById(mockDB, blockID.String(), map[string]interface{}{"user_id": userID.String()})

	// Assert expectations
	assert.NoError(t, err)
	assert.Equal(t, blockID, block.ID)
	assert.Equal(t, "Test Content", block.Content["text"])
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateBlock_Success(t *testing.T) {
	mockDB, mock := setupMockDB(t)
	blockService := BlockService{}

	userID := uuid.MustParse("f3c4b2a0-5d8e-4b1c-8f3b-7a2e5d6f7c8b")
	blockID := uuid.MustParse("bc40d480-df75-476a-945a-f5969bc63314")
	noteID := uuid.MustParse("288bafb8-baab-45b9-8f3b-42715d5d752c")
	eventID := uuid.MustParse("959d5440-4ec6-4336-b461-09971987fbb3")

	// Create a mock BlockContent as JSON
	contentJSON := []byte(`{"text":"Test Content"}`)
	metadataJSON := []byte(`{}`)

	now := time.Now()

	// Set up expectation for block retrieval
	blockRows := sqlmock.NewRows([]string{"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at"}).
		AddRow(blockID, noteID, "text", contentJSON, metadataJSON, 1, now, now)

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "blocks" WHERE id = $1 ORDER BY "blocks"."id" LIMIT $2`)).
		WithArgs(blockID.String(), 1).
		WillReturnRows(blockRows)

	// Set up expectation for event creation
	eventRows := sqlmock.NewRows([]string{"id"}).AddRow(eventID)
	mock.ExpectQuery(regexp.QuoteMeta(`INSERT INTO "events"`)).
		WithArgs(
			"block.updated",  // type
			sqlmock.AnyArg(), // timestamp
			"block",          // entity_type
			"update",         // action
			sqlmock.AnyArg(), // data (JSONB)
			"user-123",       // actor_id
			sqlmock.AnyArg(), // metadata (JSONB)
			"pending",        // status
			false,            // processed
			nil,              // processed_at
			sqlmock.AnyArg(), // failed_attempts (JSONB)
		).
		WillReturnRows(eventRows)

	// Set up expectation for block update - needs to match the actual query GORM generates
	mock.ExpectExec(regexp.QuoteMeta(`UPDATE "blocks" SET`)).
		WithArgs(
			"user-123",       // actor_id
			sqlmock.AnyArg(), // content (JSONB)
			sqlmock.AnyArg(), // updated_at
			blockID,          // WHERE id = ?
		).
		WillReturnResult(sqlmock.NewResult(0, 1))

	mock.ExpectCommit()

	// Create update data
	updateData := map[string]interface{}{
		"content":  "Updated Content", // Using string content to test backward compatibility
		"actor_id": "user-123",
	}

	// Call the service
	block, err := blockService.UpdateBlock(mockDB, blockID.String(), updateData, map[string]interface{}{"user_id": userID.String()})

	// Assert expectations
	assert.NoError(t, err)
	assert.Equal(t, blockID, block.ID)
	assert.Equal(t, models.BlockContent{"text": "Updated Content"}, block.Content)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteBlock_Success(t *testing.T) {
	mockDB, mock := setupMockDB(t)
	blockService := BlockService{}

	userID := uuid.MustParse("f3c4b2a0-5d8e-4b1c-8f3b-7a2e5d6f7c8b")
	blockID := uuid.MustParse("bc40d480-df75-476a-945a-f5969bc63314")
	noteID := uuid.MustParse("288bafb8-baab-45b9-8f3b-42715d5d752c")
	eventID := uuid.MustParse("959d5440-4ec6-4336-b461-09971987fbb3")

	// Create a mock BlockContent as JSON
	contentJSON := []byte(`{"text":"Test Content"}`)
	metadataJSON := []byte(`{}`)
	now := time.Now()

	// Set up expectation for block retrieval
	blockRows := sqlmock.NewRows([]string{"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at"}).
		AddRow(blockID, noteID, "text", contentJSON, metadataJSON, 1, now, now)

	mock.ExpectBegin()
	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "blocks" WHERE id = $1 ORDER BY "blocks"."id" LIMIT $2`)).
		WithArgs(blockID.String(), 1).
		WillReturnRows(blockRows)

	// Set up expectation for block deletion
	mock.ExpectExec(regexp.QuoteMeta(`DELETE FROM "blocks" WHERE`)).
		WithArgs(blockID).
		WillReturnResult(sqlmock.NewResult(0, 1))

	// Set up expectation for event creation
	eventRows := sqlmock.NewRows([]string{"id"}).AddRow(eventID)
	mock.ExpectQuery(regexp.QuoteMeta(`INSERT INTO "events"`)).
		WithArgs(
			"block.deleted",  // type
			sqlmock.AnyArg(), // timestamp
			"block",          // entity_type
			"delete",         // action
			sqlmock.AnyArg(), // data (JSONB)
			"system",         // actor_id
			sqlmock.AnyArg(), // metadata (JSONB)
			"pending",        // status
			false,            // processed
			nil,              // processed_at
			sqlmock.AnyArg(), // failed_attempts (JSONB)
		).
		WillReturnRows(eventRows)

	mock.ExpectCommit()

	// Call the service
	err := blockService.DeleteBlock(mockDB, blockID.String(), map[string]interface{}{"user_id": userID.String()})

	// Assert expectations
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestListBlocksByNote_Success(t *testing.T) {
	mockDB, mock := setupMockDB(t)
	blockService := BlockService{}

	userID := uuid.MustParse("f3c4b2a0-5d8e-4b1c-8f3b-7a2e5d6f7c8b")
	noteID := uuid.MustParse("1b32487f-c44b-4076-be53-599b62f7c415")
	blockID := uuid.MustParse("bc40d480-df75-476a-945a-f5969bc63314")

	// Create a mock BlockContent as JSON
	contentJSON := []byte(`{"text":"Test Content"}`)
	metadataJSON := []byte(`{}`)
	now := time.Now()

	// Set up expectation for block retrieval
	rows := sqlmock.NewRows([]string{"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at"}).
		AddRow(blockID, noteID, "text", contentJSON, metadataJSON, 1, now, now)

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "blocks" WHERE note_id = $1 ORDER BY "order" asc`)).
		WithArgs(noteID.String()).
		WillReturnRows(rows)

	// Call the service
	blocks, err := blockService.ListBlocksByNote(mockDB, noteID.String(), map[string]interface{}{"user_id": userID.String()})

	// Assert expectations
	assert.NoError(t, err)
	assert.Equal(t, 1, len(blocks))
	assert.Equal(t, blockID, blocks[0].ID)
	assert.Equal(t, "Test Content", blocks[0].Content["text"])
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetBlocks_Success(t *testing.T) {
	mockDB, mock := setupMockDB(t)
	blockService := BlockService{}

	noteID := uuid.MustParse("1b32487f-c44b-4076-be53-599b62f7c415")
	blockID1 := uuid.MustParse("bc40d480-df75-476a-945a-f5969bc63314")
	blockID2 := uuid.MustParse("cd50d480-df75-476a-945a-f5969bc63315")

	// Create a mock BlockContent as JSON for two blocks
	contentJSON1 := []byte(`{"text":"Test Content 1"}`)
	contentJSON2 := []byte(`{"text":"Test Content 2"}`)
	metadataJSON := []byte(`{}`)
	now := time.Now()

	// Set up expectation for blocks retrieval
	rows := sqlmock.NewRows([]string{"id", "note_id", "type", "content", "metadata", "order", "created_at", "updated_at"}).
		AddRow(blockID1, noteID, "text", contentJSON1, metadataJSON, 1, now, now).
		AddRow(blockID2, noteID, "heading", contentJSON2, metadataJSON, 2, now, now)

	mock.ExpectQuery(regexp.QuoteMeta(`SELECT * FROM "blocks" WHERE note_id = $1 AND type = $2 ORDER BY "order" asc`)).
		WithArgs(noteID.String(), "text").
		WillReturnRows(rows)

	// Call the service
	params := map[string]interface{}{
		"note_id": noteID.String(),
		"type":    "text",
	}
	blocks, err := blockService.GetBlocks(mockDB, params)

	// Assert expectations
	assert.NoError(t, err)
	assert.Equal(t, 2, len(blocks))
	assert.Equal(t, blockID1, blocks[0].ID)
	assert.Equal(t, "Test Content 1", blocks[0].Content["text"])
	assert.Equal(t, blockID2, blocks[1].ID)
	assert.Equal(t, "Test Content 2", blocks[1].Content["text"])
	assert.NoError(t, mock.ExpectationsWereMet())
}
