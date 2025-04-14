package database

import (
	"testing"

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
