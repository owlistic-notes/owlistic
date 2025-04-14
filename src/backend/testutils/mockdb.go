package testutils

import (
	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/thinkstack/database"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func SetupMockDB() (*database.Database, sqlmock.Sqlmock, func()) {
	sqlDB, mock, err := sqlmock.New()
	if err != nil {
		panic("failed to create sqlmock: " + err.Error())
	}
	gormDB, err := gorm.Open(postgres.New(postgres.Config{Conn: sqlDB}), &gorm.Config{})
	if err != nil {
		panic("failed to create gorm DB from sqlmock: " + err.Error())
	}
	closeFunc := func() {
		sqlDB.Close()
	}
	return &database.Database{DB: gormDB}, mock, closeFunc
}
