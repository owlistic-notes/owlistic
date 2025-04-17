package testutils

import (
	"database/sql"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/thinkstack/database"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

// SetupMockDB sets up a mock database connection
func SetupMockDB() (*database.Database, sqlmock.Sqlmock, func()) {
	var db *sql.DB
	var mock sqlmock.Sqlmock
	var err error

	db, mock, err = sqlmock.New()
	if err != nil {
		panic(err)
	}

	dialector := postgres.New(postgres.Config{
		DSN:                  "sqlmock_db_0",
		DriverName:           "postgres",
		Conn:                 db,
		PreferSimpleProtocol: true,
	})

	gormDB, err := gorm.Open(dialector, &gorm.Config{})
	if err != nil {
		panic(err)
	}

	mockDB := &database.Database{
		DB: gormDB,
	}

	close := func() {
		db.Close()
	}

	return mockDB, mock, close
}
