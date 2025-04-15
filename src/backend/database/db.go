package database

import (
	"fmt"
	"log"

	"github.com/thinkstack/config"
	"github.com/thinkstack/models"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

type Database struct {
	DB *gorm.DB
}

func Setup(cfg config.Config) (*Database, error) {

	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.DBHost,
		cfg.DBPort,
		cfg.DBUser,
		cfg.DBPassword,
		cfg.DBName,
	)

	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database: %w", err)
	}

	// Drop all tables
	if err := db.Exec(`DROP TABLE IF EXISTS notes, notebooks, users, tasks CASCADE`).Error; err != nil {
		return nil, fmt.Errorf("failed to drop tables: %w", err)
	}

	// Create tables fresh
	if err := db.AutoMigrate(&models.User{}, &models.Notebook{}, &models.Note{}, &models.Task{}); err != nil {
		return nil, fmt.Errorf("failed to create tables: %w", err)
	}

	return &Database{DB: db}, nil
}

func (d *Database) Close() {
	if d.DB == nil {
		log.Println("Database connection is nil, nothing to close.")
		return
	}
	sqlDB, err := d.DB.DB()
	if err != nil {
		log.Printf("Failed to get database connection: %v", err)
		return
	}
	if err := sqlDB.Close(); err != nil {
		log.Printf("Failed to close database connection: %v", err)
	}
}

func (d *Database) Query(query string, args ...interface{}) (*gorm.DB, error) {
	result := d.DB.Raw(query, args...)
	return result, result.Error
}

func (d *Database) Execute(query string, args ...interface{}) error {
	result := d.DB.Exec(query, args...)
	return result.Error
}
