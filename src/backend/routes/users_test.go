package routes

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"github.com/thinkstack/services"
)

type MockUserService struct{}

func (m *MockUserService) CreateUser(db *database.Database, user models.User) (models.User, error) {
	return user, nil
}

func (m *MockUserService) GetUserById(db *database.Database, id string) (models.User, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.User{ID: uuid.Must(uuid.Parse(id)), Email: "test@example.com"}, nil
	}
	return models.User{}, services.ErrUserNotFound
}

func (m *MockUserService) UpdateUser(db *database.Database, id string, updatedData models.User) (models.User, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.User{ID: uuid.Must(uuid.Parse(id)), Email: updatedData.Email}, nil
	}
	return models.User{}, services.ErrUserNotFound
}

func (m *MockUserService) DeleteUser(db *database.Database, id string) error {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return nil
	}
	return services.ErrUserNotFound
}

func (m *MockUserService) GetAllUsers(db *database.Database) ([]models.User, error) {
	return []models.User{
		{ID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")), Email: "test@example.com"},
		{ID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")), Email: "test2@example.com"},
	}, nil
}

func TestCreateUser(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockUserService{}
	RegisterUserRoutes(router, db, mockService)

	t.Run("Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/users/", bytes.NewBuffer([]byte("invalid json")))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("Valid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/users/", bytes.NewBuffer([]byte(`{"name":"Test User"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusCreated, w.Code)
	})
}

func TestGetUserById(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockUserService{}
	RegisterUserRoutes(router, db, mockService)

	t.Run("User Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/users/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("User Found", func(t *testing.T) {

		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestUpdateUser(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockUserService{}
	RegisterUserRoutes(router, db, mockService)

	t.Run("Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte("invalid json")))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("User Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174001", bytes.NewBuffer([]byte(`{"email":"updated@example.com"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("User Updated", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte(`{"email":"updated@example.com"}`)))
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestDeleteUser(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockUserService{}
	RegisterUserRoutes(router, db, mockService)

	t.Run("User Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/users/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("User Deleted", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNoContent, w.Code)
	})
}

func TestGetAllUsers(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockService := &MockUserService{}
	RegisterUserRoutes(router, db, mockService)

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/users/", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "test@example.com")
	assert.Contains(t, w.Body.String(), "test2@example.com")
}
