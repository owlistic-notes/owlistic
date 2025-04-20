package services

import (
	"testing"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/models"
	"github.com/thinkstack/testutils"
)

func TestAssignRole(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	resourceID := uuid.New()
	resourceType := models.NoteResource
	role := models.OwnerRole

	// Test when role doesn't exist yet
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, resourceID, resourceType).
		WillReturnError(ErrNotFound)

	mock.ExpectBegin()
	mock.ExpectQuery("INSERT INTO \"roles\"").
		WithArgs(sqlmock.AnyArg(), userID, resourceID, resourceType, role, sqlmock.AnyArg(), sqlmock.AnyArg(), nil).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(uuid.New()))
	mock.ExpectCommit()

	err := service.AssignRole(db, userID, resourceID, resourceType, role)
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())

	// Test when role exists and needs update
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, resourceID, resourceType).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "resource_id", "resource_type", "role"}).
			AddRow(uuid.New(), userID, resourceID, resourceType, models.ViewerRole))

	mock.ExpectBegin()
	mock.ExpectExec("UPDATE \"roles\" SET").
		WithArgs(sqlmock.AnyArg(), models.OwnerRole, sqlmock.AnyArg(), sqlmock.AnyArg()).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	err = service.AssignRole(db, userID, resourceID, resourceType, role)
	assert.NoError(t, err)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestHasAccess(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	resourceID := uuid.New()
	resourceType := models.NoteResource

	// Test when user has direct role
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, "user", models.AdminRole).
		WillReturnError(ErrNotFound)

	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, resourceID, resourceType).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.OwnerRole))

	hasAccess, err := service.HasAccess(db, userID, resourceID, resourceType, models.EditorRole)
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())

	// Test when user has admin role
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, "user", models.AdminRole).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.AdminRole))

	hasAccess, err = service.HasAccess(db, userID, resourceID, resourceType, models.OwnerRole)
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())

	// Test when user doesn't have sufficient role
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, "user", models.AdminRole).
		WillReturnError(ErrNotFound)

	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, resourceID, resourceType).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.ViewerRole))

	hasAccess, err = service.HasAccess(db, userID, resourceID, resourceType, models.EditorRole)
	assert.NoError(t, err)
	assert.False(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestGetRole(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	resourceID := uuid.New()
	resourceType := models.NoteResource
	roleID := uuid.New()

	// Test successful retrieval
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, resourceID, resourceType).
		WillReturnRows(sqlmock.NewRows([]string{"id", "user_id", "resource_id", "resource_type", "role"}).
			AddRow(roleID, userID, resourceID, resourceType, models.OwnerRole))

	role, err := service.GetRole(db, userID, resourceID, resourceType)
	assert.NoError(t, err)
	assert.Equal(t, models.OwnerRole, role.Role)
	assert.Equal(t, roleID, role.ID)
	assert.NoError(t, mock.ExpectationsWereMet())
}
