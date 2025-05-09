package database

import (
	"log"

	"github.com/owlistic/models"
	"gorm.io/gorm"
)

// RunMigrations runs database migrations to ensure tables are up to date
func RunMigrations(db *gorm.DB) error {
	log.Println("Running database migrations...")

	// Add all models that should be migrated
	err := db.AutoMigrate(
		&models.User{},
		&models.Role{},
		&models.Notebook{},
		&models.Note{},
		&models.Block{},
		&models.Task{},
		&models.Event{},
	)

	if err != nil {
		log.Printf("Migration failed: %v", err)
		return err
	}

	log.Println("Migration completed successfully")
	return nil
}
