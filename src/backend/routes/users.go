package routes

import (
	"errors"
	"net/http"

	"github.com/google/uuid"
	"github.com/owlistic/database"
	"github.com/owlistic/middleware"
	"github.com/owlistic/services"

	"github.com/gin-gonic/gin"
)

// Request model for registration since User no longer has Password field
type registrationRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func RegisterUserRoutes(group *gin.RouterGroup, db *database.Database, userService services.UserServiceInterface, authService services.AuthServiceInterface) {
	// Public registration endpoint - no auth required
	group.POST("/register", func(c *gin.Context) { CreateUser(c, db, userService) })

	// Protected user routes
	userGroup := group.Group("/users")
	userGroup.Use(middleware.AuthMiddleware(authService))
	{
		// Collection endpoints with query parameters
		userGroup.GET("/", func(c *gin.Context) { GetUsers(c, db, userService) })

		// Resource-specific endpoints
		userGroup.GET("/:id", func(c *gin.Context) { GetUserById(c, db, userService) })
		userGroup.PUT("/:id", func(c *gin.Context) { UpdateUser(c, db, userService) })
		userGroup.DELETE("/:id", func(c *gin.Context) { DeleteUser(c, db, userService) })
	}
}

func CreateUser(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	var req registrationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create user data map from request
	userData := map[string]interface{}{
		"email":    req.Email,
		"password": req.Password,
	}

	createdUser, err := userService.CreateUser(db, userData)
	if err != nil {
		if errors.Is(err, services.ErrUserAlreadyExists) {
			c.JSON(http.StatusConflict, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, createdUser)
}

func GetUserById(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	id := c.Param("id")
	user, err := userService.GetUserById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrUserNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, user)
}

// Request model for updates
type updateUserRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func UpdateUser(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	id := c.Param("id")
	var req updateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if the authenticated user is updating their own account
	// This is a simple authorization check
	contextUserID, exists := c.Get("userID")
	if exists {
		userUUID, ok := contextUserID.(uuid.UUID)
		if ok {
			// Convert the path parameter ID to UUID for comparison
			pathID, err := uuid.Parse(id)
			if err == nil && userUUID != pathID {
				c.JSON(http.StatusForbidden, gin.H{"error": "You can only update your own account"})
				return
			}
		}
	}

	// Create update data map from request
	updateData := make(map[string]interface{})
	if req.Email != "" {
		updateData["email"] = req.Email
	}
	if req.Password != "" {
		updateData["password"] = req.Password
	}

	updatedUser, err := userService.UpdateUser(db, id, updateData)
	if err != nil {
		if errors.Is(err, services.ErrUserNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, updatedUser)
}

func DeleteUser(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	id := c.Param("id")

	// Authorization check - same as update
	contextUserID, exists := c.Get("userID")
	if exists {
		userUUID, ok := contextUserID.(uuid.UUID)
		if ok {
			// Convert the path parameter ID to UUID for comparison
			pathID, err := uuid.Parse(id)
			if err == nil && userUUID != pathID {
				c.JSON(http.StatusForbidden, gin.H{"error": "You can only delete your own account"})
				return
			}
		}
	}

	if err := userService.DeleteUser(db, id); err != nil {
		if errors.Is(err, services.ErrUserNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusNoContent, gin.H{})
}

func GetUsers(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	// Extract query parameters
	params := make(map[string]interface{})

	// Add any query params that might be used for filtering
	if email := c.Query("email"); email != "" {
		params["email"] = email
	}

	users, err := userService.GetUsers(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, users)
}
