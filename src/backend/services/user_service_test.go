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

	userID := uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000"))

	mock.ExpectBegin()
	mock.ExpectQuery(`INSERT INTO "users" \("email","password_hash","id"\) VALUES \(\$1,\$2,\$3\) RETURNING "id"`).
		WithArgs(
			"test@example.com", // email
			"",                 // password_hash
			userID,             // id
		).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(userID.String()))
	mock.ExpectCommit()

	userService := &UserService{}
	user := models.User{
		ID:    userID,
		Email: "test@example.com",
	}

	createdUser, err := userService.CreateUser(db, user)
	assert.NoError(t, err)
	assert.Equal(t, createdUser.Email, "test@example.com")
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

	// Mock the SELECT query that GORM performs first
	mock.ExpectQuery("SELECT (.+) FROM \"users\" WHERE id = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs(existingID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email", "password_hash"}).
			AddRow(existingID.String(), "old@example.com", ""))

	// Mock the UPDATE query
	mock.ExpectBegin()
	mock.ExpectExec("UPDATE \"users\" SET (.+) WHERE").
		WithArgs("updated@example.com", existingID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	userService := &UserService{}
	updatedData := models.User{Email: "updated@example.com"}
	user, err := userService.UpdateUser(db, existingID.String(), updatedData)
	assert.NoError(t, err)
	assert.Equal(t, user.Email, "updated@example.com")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectBegin()
	mock.ExpectExec("DELETE FROM \"users\" WHERE id = \\$1").WithArgs("existing-id").WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	userService := &UserService{}
	err := userService.DeleteUser(db, "existing-id")
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}
