package database

import (
	"log"

	"github.com/thinkstack/models"
	"gorm.io/gorm"
)

// RunMigrations runs database migrations to ensure tables are up to date
func RunMigrations(db *gorm.DB) error {
	log.Println("Running database migrations...")

	// Add all models that should be migrated
	err := db.AutoMigrate(
		&models.User{},
		// Add more models here as needed
	)

	if err != nil {
		log.Printf("Migration failed: %v", err)
		return err
	}

	log.Println("Migration completed successfully")
	return nil
}
