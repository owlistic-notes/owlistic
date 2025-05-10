package services

import (
	"testing"

	"owlistic-notes/owlistic/models"
	"owlistic-notes/owlistic/testutils"

	sqlmock "github.com/DATA-DOG/go-sqlmock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
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

// Add these new tests

func TestHasSystemRole(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	userIDStr := userID.String()

	// Test when user is admin
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, models.UserResource, models.AdminRole).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.AdminRole))

	hasAccess, err := service.HasSystemRole(db, userIDStr, "viewer")
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())

	// Test when user has specific role
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, models.UserResource, models.AdminRole).
		WillReturnError(ErrNotFound)

	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, userID, models.UserResource).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.EditorRole))

	hasAccess, err = service.HasSystemRole(db, userIDStr, "viewer")
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestHasAccessByStrings(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	resourceID := uuid.New()
	userIDStr := userID.String()
	resourceIDStr := resourceID.String()

	// Test successful conversion and check
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, models.UserResource, models.AdminRole).
		WillReturnError(ErrNotFound)

	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, resourceID, models.NoteResource).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.EditorRole))

	hasAccess, err := service.HasAccessByStrings(db, userIDStr, resourceIDStr, "note", "viewer")
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())

	// Test with invalid UUID
	hasAccess, err = service.HasAccessByStrings(db, "invalid-uuid", resourceIDStr, "note", "viewer")
	assert.Error(t, err)
	assert.False(t, hasAccess)

	// Test with invalid resource type
	hasAccess, err = service.HasAccessByStrings(db, userIDStr, resourceIDStr, "invalid-type", "viewer")
	assert.Error(t, err)
	assert.False(t, hasAccess)

	// Test with invalid role
	hasAccess, err = service.HasAccessByStrings(db, userIDStr, resourceIDStr, "note", "invalid-role")
	assert.Error(t, err)
	assert.False(t, hasAccess)
}

func TestHasNoteAccess(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	noteID := uuid.New()
	userIDStr := userID.String()
	noteIDStr := noteID.String()

	// Test with direct role on note
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, models.UserResource, models.AdminRole).
		WillReturnError(ErrNotFound)

	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, noteID, models.NoteResource).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.ViewerRole))

	hasAccess, err := service.HasNoteAccess(db, userIDStr, noteIDStr, "viewer")
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestHasNotebookAccess(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	notebookID := uuid.New()
	userIDStr := userID.String()
	notebookIDStr := notebookID.String()

	// Test with direct role on notebook
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, models.UserResource, models.AdminRole).
		WillReturnError(ErrNotFound)

	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, notebookID, models.NotebookResource).
		WillReturnRows(sqlmock.NewRows([]string{"id", "role"}).AddRow(uuid.New(), models.EditorRole))

	hasAccess, err := service.HasNotebookAccess(db, userIDStr, notebookIDStr, "editor")
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())
}

func TestHasBlockAccess(t *testing.T) {
	db, mock, close := testutils.SetupMockDB()
	defer close()

	service := NewRoleService()
	userID := uuid.New()
	blockID := uuid.New()
	noteID := uuid.New()
	userIDStr := userID.String()
	blockIDStr := blockID.String()

	// Test with inherited permission from note
	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_type = \\$2 AND role = \\$3").
		WithArgs(userID, models.UserResource, models.AdminRole).
		WillReturnError(ErrNotFound)

	mock.ExpectQuery("SELECT (.+) FROM \"roles\" WHERE user_id = \\$1 AND resource_id = \\$2 AND resource_type = \\$3").
		WithArgs(userID, blockID, models.BlockResource).
		WillReturnError(ErrRoleNotFound)

	// Expect block lookup
	mock.ExpectQuery("SELECT \\* FROM \"blocks\" WHERE id = \\$1 ORDER BY \"blocks\".\"id\" LIMIT \\$2").
		WithArgs(blockID, 1).
		WillReturnRows(sqlmock.NewRows([]string{"id", "note_id", "user_id"}).
			AddRow(blockID, noteID, uuid.New()))

	// Expect note lookup to check ownership
	mock.ExpectQuery("SELECT user_id FROM \"notes\" WHERE id = \\$1").
		WithArgs(noteID).
		WillReturnRows(sqlmock.NewRows([]string{"user_id"}).AddRow(userID))

	hasAccess, err := service.HasBlockAccess(db, userIDStr, blockIDStr, "editor")
	assert.NoError(t, err)
	assert.True(t, hasAccess)
	assert.NoError(t, mock.ExpectationsWereMet())
}
