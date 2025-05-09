package database

import (
	"testing"

	"daviderutigliano/owlistic/models"

	"github.com/stretchr/testify/assert"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func TestClose(t *testing.T) {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	assert.NoError(t, err)
	database := &Database{DB: db}

	assert.NotPanics(t, func() {
		database.Close()
	})
}

func TestQuery(t *testing.T) {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	assert.NoError(t, err)
	database := &Database{DB: db}

	err = database.Execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
	assert.NoError(t, err)
	err = database.Execute("INSERT INTO test (name) VALUES (?)", "test_name")
	assert.NoError(t, err)

	query := "SELECT * FROM test WHERE name = ?"
	result, err := database.Query(query, "test_name")
	assert.NoError(t, err)

	var rows []map[string]interface{}
	err = result.Scan(&rows).Error
	assert.NoError(t, err)

	assert.Len(t, rows, 1)
	assert.Equal(t, "test_name", rows[0]["name"])
}

func TestExecute(t *testing.T) {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	assert.NoError(t, err)
	database := &Database{DB: db}

	err = database.Execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
	assert.NoError(t, err)

	err = database.Execute("INSERT INTO test (name) VALUES (?)", "test_name")
	assert.NoError(t, err)

	var count int64
	err = db.Table("test").Count(&count).Error
	assert.NoError(t, err)
	assert.Equal(t, int64(1), count)
}

// Add new test for soft delete functionality
func TestSoftDelete(t *testing.T) {
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	assert.NoError(t, err)

	// Create necessary tables for testing
	err = db.AutoMigrate(&models.User{}, &models.Notebook{}, &models.Note{}, &models.Block{})
	assert.NoError(t, err)

	// Create a test user
	user := models.User{
		Email:        "test@example.com",
		PasswordHash: "hash",
	}
	result := db.Create(&user)
	assert.NoError(t, result.Error)

	// Create a notebook
	notebook := models.Notebook{
		UserID:      user.ID,
		Name:        "Test Notebook",
		Description: "Description",
	}
	result = db.Create(&notebook)
	assert.NoError(t, result.Error)

	// Create a note
	note := models.Note{
		UserID:     user.ID,
		NotebookID: notebook.ID,
		Title:      "Test Note",
	}
	result = db.Create(&note)
	assert.NoError(t, result.Error)

	// Create a block
	block := models.Block{
		UserID:  user.ID,
		NoteID:  note.ID,
		Type:    models.TextBlock,
		Content: models.BlockContent{"text": "Test content"},
		Order:   1,
	}
	result = db.Create(&block)
	assert.NoError(t, result.Error)

	// Soft delete the note
	result = db.Delete(&note)
	assert.NoError(t, result.Error)

	// Test note soft deletion
	var deletedNote models.Note
	result = db.Unscoped().First(&deletedNote, note.ID)
	assert.NoError(t, result.Error)
	assert.NotNil(t, deletedNote.DeletedAt.Time)

	// Try to find the note with normal query (should not find it)
	var foundNote models.Note
	result = db.First(&foundNote, note.ID)
	assert.Error(t, result.Error) // Should error because note is soft-deleted

	// Test cascade effect - blocks should also be soft-deleted
	var foundBlock models.Block
	result = db.First(&foundBlock, block.ID)
	assert.Error(t, result.Error) // Should not find the block

	// But it should exist in the database with deletedAt set
	var deletedBlock models.Block
	result = db.Unscoped().First(&deletedBlock, block.ID)
	assert.NoError(t, result.Error)
	assert.NotNil(t, deletedBlock.DeletedAt.Time)
}
