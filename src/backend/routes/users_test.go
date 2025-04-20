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

// Updated MockUserService to match the new interface
type MockUserService struct{}

func (m *MockUserService) GetUsers(db *database.Database, params map[string]interface{}) ([]models.User, error) {
	email, hasEmail := params["email"].(string)

	users := []models.User{
		{
			ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
			Email: "test@example.com",
		},
		{
			ID:    uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174001")),
			Email: "test2@example.com",
		},
	}

	// Apply email filter
	if hasEmail && email != "" {
		var filteredUsers []models.User
		for _, user := range users {
			if user.Email == email {
				filteredUsers = append(filteredUsers, user)
			}
		}
		return filteredUsers, nil
	}

	return users, nil
}

func (m *MockUserService) CreateUser(db *database.Database, userData map[string]interface{}) (models.User, error) {
	email, _ := userData["email"].(string)
	return models.User{
		ID:    uuid.New(),
		Email: email,
	}, nil
}

func (m *MockUserService) GetUserById(db *database.Database, id string) (models.User, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		return models.User{ID: uuid.Must(uuid.Parse(id)), Email: "test@example.com"}, nil
	}
	return models.User{}, services.ErrUserNotFound
}

func (m *MockUserService) UpdateUser(db *database.Database, id string, updatedData map[string]interface{}) (models.User, error) {
	if id == "123e4567-e89b-12d3-a456-426614174000" {
		email, _ := updatedData["email"].(string)
		return models.User{ID: uuid.Must(uuid.Parse(id)), Email: email}, nil
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

func (m *MockUserService) GetUserByEmail(db *database.Database, email string) (models.User, error) {
	if email == "test@example.com" {
		return models.User{ID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")), Email: email}, nil
	}
	return models.User{}, services.ErrUserNotFound
}

func (m *MockUserService) AssignRole(db *database.Database, userID uuid.UUID, role models.RoleType) error {
	if userID == uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")) {
		return nil
	}
	return services.ErrUserNotFound
}

func (m *MockUserService) GetUserRole(db *database.Database, userID uuid.UUID) (models.RoleType, error) {
	if userID == uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")) {
		return models.OwnerRole, nil
	}
	return "", services.ErrUserNotFound
}

// Mock authentication service for testing
type MockAuthService struct{}

func (m *MockAuthService) Login(db *database.Database, email, password string) (string, error) {
	return "mock.jwt.token", nil
}

func (m *MockAuthService) ValidateToken(tokenString string) (*services.JWTClaims, error) {
	return &services.JWTClaims{
		UserID: uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")),
		Email:  "test@example.com",
	}, nil
}

func (m *MockAuthService) HashPassword(password string) (string, error) {
	return "hashed-" + password, nil
}

func (m *MockAuthService) ComparePasswords(hashedPassword, password string) error {
	return nil
}

// Mock middleware that sets the user ID as a string to better match the test scenario
func mockAuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Set user context values that would normally come from JWT
		// Important: Set the UUID directly, not as a string
		c.Set("userID", uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")))
		c.Set("email", "test@example.com")
		c.Next()
	}
}

// Setup a router with mock middleware for testing protected routes
func setupTestRouter() (*gin.Engine, *database.Database, *MockUserService, *MockAuthService) {
	router := gin.Default()
	db := &database.Database{}
	mockUserService := &MockUserService{}
	mockAuthService := &MockAuthService{}

	// Register public routes first
	apiGroup := router.Group("/api/v1")

	// Apply mock middleware for authentication
	router.Use(func(c *gin.Context) {
		// Set user context values that would normally come from JWT
		c.Set("userID", uuid.Must(uuid.Parse("123e4567-e89b-12d3-a456-426614174000")))
		c.Set("email", "test@example.com")
		c.Next()
	})

	// Register routes with the apiGroup
	RegisterUserRoutes(apiGroup, db, mockUserService, mockAuthService)

	return router, db, mockUserService, mockAuthService
}

func TestRegisterUser(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockUserService := &MockUserService{}

	// Create router group for user routes
	apiGroup := router.Group("/api/v1")

	// Register user routes
	RegisterUserRoutes(apiGroup, db, mockUserService, nil)

	t.Run("Register User with Valid Input", func(t *testing.T) {
		w := httptest.NewRecorder()
		reqBody := `{"email":"new@example.com","password":"password123"}`
		req, _ := http.NewRequest("POST", "/api/v1/register", bytes.NewBufferString(reqBody))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusCreated, w.Code)
		assert.Contains(t, w.Body.String(), "new@example.com")
	})

	t.Run("Register User with Missing Password", func(t *testing.T) {
		w := httptest.NewRecorder()
		reqBody := `{"email":"new@example.com"}`
		req, _ := http.NewRequest("POST", "/api/v1/register", bytes.NewBufferString(reqBody))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusBadRequest, w.Code)
		assert.Contains(t, w.Body.String(), "Password is required")
	})
}

func TestProtectedRoutes(t *testing.T) {
	router, _, _, _ := setupTestRouter()

	// Test GetUsers with authentication
	t.Run("Get Users With Authentication", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/users/", nil)
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "test@example.com")
	})

	// Test UpdateUser with authentication
	t.Run("Update User with Authentication", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000",
			bytes.NewBufferString(`{"email":"updated@example.com"}`))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "updated@example.com")
	})

	// Test authorization check - trying to update someone else's account
	t.Run("Update Another User's Account Forbidden", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174001",
			bytes.NewBufferString(`{"email":"hacked@example.com"}`))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusForbidden, w.Code)
		assert.Contains(t, w.Body.String(), "You can only update your own account")
	})
}

func TestLoginRoute(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockAuthService := &MockAuthService{}

	// Create auth group
	authGroup := router.Group("/api/v1/auth")
	authGroup.POST("/login", func(c *gin.Context) { Login(c, db, mockAuthService) })

	t.Run("Login with Valid Credentials", func(t *testing.T) {
		w := httptest.NewRecorder()
		reqBody := `{"email":"test@example.com","password":"password123"}`
		req, _ := http.NewRequest("POST", "/api/v1/auth/login", bytes.NewBufferString(reqBody))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "token")
	})

	t.Run("Login with Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/auth/login", bytes.NewBufferString(`invalid json`))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("Login with Missing Required Fields", func(t *testing.T) {
		w := httptest.NewRecorder()
		reqBody := `{"email":"test@example.com"}` // Missing password
		req, _ := http.NewRequest("POST", "/api/v1/auth/login", bytes.NewBufferString(reqBody))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusBadRequest, w.Code)
	})
}

func TestCreateUser(t *testing.T) {
	router := gin.Default()
	db := &database.Database{}
	mockUserService := &MockUserService{}

	// Create router group for user routes
	apiGroup := router.Group("/api/v1")

	// Register user routes
	RegisterUserRoutes(apiGroup, db, mockUserService, nil)

	t.Run("Valid Registration", func(t *testing.T) {
		w := httptest.NewRecorder()
		reqBody := `{"email":"new@example.com","password":"password123"}`
		req, _ := http.NewRequest("POST", "/api/v1/register", bytes.NewBufferString(reqBody))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusCreated, w.Code)
	})

	t.Run("Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("POST", "/api/v1/register", bytes.NewBuffer([]byte("invalid json")))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusBadRequest, w.Code)
	})
}

func TestGetUserById(t *testing.T) {
	router, _, _, _ := setupTestRouter()

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
	router, _, _, _ := setupTestRouter()

	t.Run("Invalid JSON", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000", bytes.NewBuffer([]byte("invalid json")))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("User Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174001",
			bytes.NewBufferString(`{"email":"updated@example.com"}`))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)
		// This should now return forbidden since we've added authorization checks
		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("User Updated", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("PUT", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000",
			bytes.NewBufferString(`{"email":"updated@example.com"}`))
		req.Header.Set("Content-Type", "application/json")
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
	})
}

func TestDeleteUser(t *testing.T) {
	router, _, _, _ := setupTestRouter()

	t.Run("User Not Found", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/users/123e4567-e89b-12d3-a456-426614174001", nil)
		router.ServeHTTP(w, req)
		// This should now return forbidden since we've added authorization checks
		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("User Deleted", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("DELETE", "/api/v1/users/123e4567-e89b-12d3-a456-426614174000", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusNoContent, w.Code)
	})
}

func TestGetAllUsers(t *testing.T) {
	router, _, _, _ := setupTestRouter()

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/api/v1/users/", nil)
	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "test@example.com")
	assert.Contains(t, w.Body.String(), "test2@example.com")
}

// Add new test for users with query parameters
func TestGetUsers(t *testing.T) {
	router, _, _, _ := setupTestRouter()

	t.Run("Get Users With No Filters", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/users/", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "test@example.com")
		assert.Contains(t, w.Body.String(), "test2@example.com")
	})

	t.Run("Get Users By Email", func(t *testing.T) {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/api/v1/users/?email=test@example.com", nil)
		router.ServeHTTP(w, req)
		assert.Equal(t, http.StatusOK, w.Code)
		assert.Contains(t, w.Body.String(), "test@example.com")
		assert.NotContains(t, w.Body.String(), "test2@example.com")
	})
}
