package services

import (
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/models"
	"github.com/thinkstack/testutils"
	"gorm.io/gorm"
)

func TestCreateUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New()
	user := models.User{
		ID:    userID,
		Email: "test@example.com",
	}

	mock.ExpectBegin()
	mock.ExpectQuery(`INSERT INTO "users"`).
		WithArgs(sqlmock.AnyArg(), "test@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(userID))

	mock.ExpectQuery(`INSERT INTO "events"`).
		WithArgs(
			"user.created",   // event
			1,                // version
			"user",           // entity
			"create",         // operation
			sqlmock.AnyArg(), // timestamp
			userID.String(),  // actor_id
			sqlmock.AnyArg(), // data json
			"pending",        // status
			false,            // dispatched
			nil,              // dispatched_at
			sqlmock.AnyArg(), // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New()))

	mock.ExpectCommit()

	service := &UserService{}
	createdUser, err := service.CreateUser(db, user)
	assert.NoError(t, err)
	assert.Equal(t, user.Email, createdUser.Email)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetUserById_NotFound(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT (.+) FROM \"users\" WHERE id = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs("non-existent-id", 1).
		WillReturnError(gorm.ErrRecordNotFound)

	userService := &UserService{}
	_, err := userService.GetUserById(db, "non-existent-id")
	assert.Error(t, err)
	assert.Equal(t, err.Error(), "user not found")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	existingID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// Expect the initial user query
	mock.ExpectQuery(`SELECT \* FROM "users"`).
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email", "password_hash"}).
			AddRow(existingID.String(), "old@example.com", ""))

	// Expect the update
	mock.ExpectExec(`UPDATE "users" SET`).
		WithArgs("updated@example.com", existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect commit
	mock.ExpectCommit()

	userService := &UserService{}
	updatedData := models.User{Email: "updated@example.com"}
	user, err := userService.UpdateUser(db, existingID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, updatedData.Email, user.Email)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	existingID := uuid.New()

	// Begin transaction
	mock.ExpectBegin()

	// Expect the initial user query
	mock.ExpectQuery(`SELECT \* FROM "users"`).
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email", "password_hash"}).
			AddRow(existingID.String(), "test@example.com", ""))

	// Expect the delete
	mock.ExpectExec(`DELETE FROM "users"`).
		WithArgs(existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	// Expect commit
	mock.ExpectCommit()

	userService := &UserService{}
	err := userService.DeleteUser(db, existingID.String())
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
