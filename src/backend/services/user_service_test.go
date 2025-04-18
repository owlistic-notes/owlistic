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
	email := "test@example.com"
	passwordHash := "hashed_password"

	// Check if email exists
	mock.ExpectQuery("SELECT \\* FROM \"users\" WHERE email = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs(email, 1).
		WillReturnError(gorm.ErrRecordNotFound)

	// Create user
	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO \"users\"").
		WithArgs(email, passwordHash, userID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(userID))
	mock.ExpectCommit()

	service := &UserService{}
	user := models.User{
		ID:           userID,
		Email:        email,
		PasswordHash: passwordHash,
	}

	createdUser, err := service.CreateUser(db, user)
	assert.NoError(t, err)
	assert.Equal(t, email, createdUser.Email)
	assert.Equal(t, userID, createdUser.ID)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestCreateUser_EmailExists(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	email := "existing@example.com"

	// Check if email exists - return a user to simulate email exists
	mock.ExpectQuery("SELECT (.+) FROM \"users\" WHERE email = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs(email, 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow(uuid.New(), email))

	service := &UserService{}
	user := models.User{
		Email:        email,
		PasswordHash: "password",
	}

	_, err := service.CreateUser(db, user)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "already exists")
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetUserById_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New()
	email := "test@example.com"

	mock.ExpectQuery("SELECT \\* FROM \"users\" WHERE id = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs(userID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow(userID, email))

	service := &UserService{}
	user, err := service.GetUserById(db, userID.String())
	assert.NoError(t, err)
	assert.Equal(t, email, user.Email)
	assert.Equal(t, userID, user.ID)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetUserById_NotFound(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT \\* FROM \"users\" WHERE id = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs("non-existent-id", 1).
		WillReturnError(gorm.ErrRecordNotFound)

	service := &UserService{}
	_, err := service.GetUserById(db, "non-existent-id")
	assert.Error(t, err)
	assert.Equal(t, ErrUserNotFound, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New()
	oldEmail := "old@example.com"
	newEmail := "new@example.com"

	// Get existing user
	mock.ExpectQuery("SELECT \\* FROM \"users\" WHERE id = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs(userID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow(userID, oldEmail))

	mock.ExpectBegin()

	// Update user
	mock.ExpectExec("UPDATE \"users\" SET").
		WithArgs(newEmail, userID.String()).
		WillReturnResult(sqlmock.NewResult(1, 1))

	mock.ExpectCommit()

	// Get updated user
	mock.ExpectQuery("SELECT \\* FROM \"users\" WHERE id = \\$1 AND \"users\".\"id\" = \\$2 ORDER BY \"users\".\"id\" LIMIT \\$3").
		WithArgs(userID.String(), userID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow(userID, newEmail))

	service := &UserService{}
	updatedUser, err := service.UpdateUser(db, userID.String(), models.User{Email: newEmail})
	assert.NoError(t, err)
	assert.Equal(t, newEmail, updatedUser.Email)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestUpdateUser_NotFound(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT \\* FROM \"users\" WHERE id = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs("non-existent-id", 1).
		WillReturnError(gorm.ErrRecordNotFound)

	service := &UserService{}
	_, err := service.UpdateUser(db, "non-existent-id", models.User{Email: "new@example.com"})
	assert.Error(t, err)
	assert.Equal(t, ErrUserNotFound, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestDeleteUser_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	userID := uuid.New()

	// Get existing user
	mock.ExpectQuery("SELECT (.+) FROM \"users\" WHERE id = \\$1 ORDER BY \"users\".\"id\" LIMIT \\$2").
		WithArgs(userID.String(), 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow(userID, "test@example.com"))

	// Delete user
	mock.ExpectBegin()
	mock.ExpectExec("DELETE FROM \"users\" WHERE").
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	service := &UserService{}
	err := service.DeleteUser(db, userID.String())
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetAllUsers_Success(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	mock.ExpectQuery("SELECT (.+) FROM \"users\"").
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow(uuid.New(), "user1@example.com").
			AddRow(uuid.New(), "user2@example.com"))

	service := &UserService{}
	users, err := service.GetAllUsers(db)
	assert.NoError(t, err)
	assert.Equal(t, 2, len(users))
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetUsers_WithFilters(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	email := "filtered@example.com"

	mock.ExpectQuery("SELECT (.+) FROM \"users\" WHERE email = \\$1").
		WithArgs(email).
		WillReturnRows(sqlmock.NewRows([]string{"id", "email"}).
			AddRow(uuid.New(), email))

	service := &UserService{}
	users, err := service.GetUsers(db, map[string]interface{}{"email": email})
	assert.NoError(t, err)
	assert.Equal(t, 1, len(users))
	assert.Equal(t, email, users[0].Email)
	assert.NoError(t, mock.ExpectationsWereMet())
}
