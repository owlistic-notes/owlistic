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
		&models.Role{}, // Updated to use the new Role model instead of UserRole
		&models.Notebook{},
		&models.Note{},
		&models.Block{},
		&models.Task{},
		&models.Event{},
		// Add more models here as needed
	)

	if err != nil {
		log.Printf("Migration failed: %v", err)
		return err
	}

	// If transitioning from UserRole, you might want to run a migration
	// that converts old UserRole records to the new Role format

	log.Println("Migration completed successfully")
	return nil
}
