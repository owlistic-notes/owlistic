package testutils

import (
	"encoding/json"
	"time"

	"database/sql/driver"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/thinkstack/models"
)

func MockEventRows(events []models.Event) *sqlmock.Rows {
	rows := sqlmock.NewRows([]string{
		"id",
		"event",
		"version",
		"entity",
		"operation",
		"timestamp",
		"actor_id",
		"data",
		"status",
		"dispatched",
		"dispatched_at",
	})

	defaultData := json.RawMessage(`{"test":"data"}`)

	for _, event := range events {
		rows.AddRow(
			uuid.New(),      // id
			event.Event,     // event
			1,               // version
			event.Entity,    // entity
			event.Operation, // operation
			time.Now(),      // timestamp
			event.ActorID,   // actor_id
			defaultData,     // data (as json.RawMessage)
			"pending",       // status
			false,           // dispatched
			nil,             // dispatched_at
		)
	}

	return rows
}

func MockEventInsert() *sqlmock.Rows {
	return sqlmock.NewRows([]string{"id"}).AddRow(uuid.New())
}

func NewResult(lastInsertID, rowsAffected int64) driver.Result {
	return sqlmock.NewResult(lastInsertID, rowsAffected)
}
