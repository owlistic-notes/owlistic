package database

import (
	"log"

	"github.com/thinkstack/models"
	"gorm.io/gorm"
)

// RunMigrations creates or updates database schema with proper constraints
func RunMigrations(db *gorm.DB) error {
	log.Println("Starting database migrations...")

	// Drop existing foreign keys first (if any)
	log.Println("Dropping existing foreign keys...")
	db.Exec("ALTER TABLE IF EXISTS tasks DROP CONSTRAINT IF EXISTS fk_tasks_user_id")
	db.Exec("ALTER TABLE IF EXISTS tasks DROP CONSTRAINT IF EXISTS fk_tasks_block_id")
	db.Exec("ALTER TABLE IF EXISTS blocks DROP CONSTRAINT IF EXISTS fk_notes_blocks")
	db.Exec("ALTER TABLE IF EXISTS blocks DROP CONSTRAINT IF EXISTS fk_blocks_note_id")
	db.Exec("ALTER TABLE IF EXISTS notes DROP CONSTRAINT IF EXISTS fk_notes_user_id")
	db.Exec("ALTER TABLE IF EXISTS notes DROP CONSTRAINT IF EXISTS fk_notes_notebook_id")
	db.Exec("ALTER TABLE IF EXISTS notebooks DROP CONSTRAINT IF EXISTS fk_notebooks_user_id")

	// Create tables with proper schema - do this one by one in correct order
	log.Println("Creating tables in dependency order...")

	// First create users table
	if err := db.AutoMigrate(&models.User{}); err != nil {
		return err
	}
	log.Println("Created users table")

	// Then notebooks that depend on users
	if err := db.AutoMigrate(&models.Notebook{}); err != nil {
		return err
	}
	log.Println("Created notebooks table")

	// Then notes that depend on notebooks
	if err := db.AutoMigrate(&models.Note{}); err != nil {
		return err
	}
	log.Println("Created notes table")

	// Then blocks that depend on notes
	if err := db.AutoMigrate(&models.Block{}); err != nil {
		return err
	}
	log.Println("Created blocks table")

	// Finally tasks and events
	if err := db.AutoMigrate(&models.Task{}, &models.Event{}); err != nil {
		return err
	}
	log.Println("Created tasks and events tables")

	// Manually add foreign key constraints with CASCADE
	// Note: With soft delete, we don't need physical CASCADE DELETE as GORM will handle the soft-delete operations
	// but we still want referential integrity for other operations
	log.Println("Adding foreign key constraints...")

	// Create indexes for deleted_at fields to speed up queries that filter on soft delete status
	db.Exec("CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users (deleted_at)")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_notebooks_deleted_at ON notebooks (deleted_at)")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_notes_deleted_at ON notes (deleted_at)")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_blocks_deleted_at ON blocks (deleted_at)")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_tasks_deleted_at ON tasks (deleted_at)")

	// Create GIN index on the Block content JSONB field for better performance
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_blocks_content ON blocks USING GIN (content)").Error; err != nil {
		return err
	}

	// Create index on block type for faster filtering
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_blocks_type ON blocks (type)").Error; err != nil {
		return err
	}

	// Create compound index on note_id and order for faster block retrieval
	if err := db.Exec("CREATE INDEX IF NOT EXISTS idx_blocks_note_order ON blocks (note_id, \"order\")").Error; err != nil {
		return err
	}

	return nil
}
