package testutils

import (
	"database/sql/driver"
	"encoding/json"
	"time"

	"owlistic-notes/owlistic/models"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
)

// MockEventRows creates mock SQL rows for events testing
func MockEventRows(events []models.Event) *sqlmock.Rows {
	rows := sqlmock.NewRows([]string{
		"id", "event", "version", "entity", "operation",
		"timestamp", "actor_id", "data", "status",
		"dispatched", "dispatched_at",
	})

	for _, event := range events {
		if event.ID == uuid.Nil {
			event.ID = uuid.New()
		}
		if event.Timestamp.IsZero() {
			event.Timestamp = time.Now()
		}
		if event.Data == nil {
			event.Data = json.RawMessage(`{}`)
		}
		if event.Status == "" {
			event.Status = "pending"
		}

		rows.AddRow(
			event.ID,
			event.Event,
			event.Version,
			event.Entity,
			event.Operation,
			event.Timestamp,
			event.ActorID,
			event.Data,
			event.Status,
			event.Dispatched,
			event.DispatchedAt,
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
