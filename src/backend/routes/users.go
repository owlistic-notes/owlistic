package routes

import (
	"errors"
	"net/http"
	"strings"

	"daviderutigliano/owlistic/database"
	"daviderutigliano/owlistic/models"
	"daviderutigliano/owlistic/services"

	"github.com/google/uuid"

	"github.com/gin-gonic/gin"
)

func RegisterPublicUserRoutes(group *gin.RouterGroup, db *database.Database, userService services.UserServiceInterface, authService services.AuthServiceInterface) {
	// Public registration endpoint - no auth required
	group.POST("/register", func(c *gin.Context) { CreateUser(c, db, userService) })
}

func RegisterProtectedUserRoutes(group *gin.RouterGroup, db *database.Database, userService services.UserServiceInterface, authService services.AuthServiceInterface) {
	// Collection endpoints with query parameters
	group.GET("/", func(c *gin.Context) { GetUsers(c, db, userService) })

	// Resource-specific endpoints
	group.GET("/:id", func(c *gin.Context) { GetUserById(c, db, userService) })
	group.PUT("/:id", func(c *gin.Context) { UpdateUser(c, db, userService) })
	group.DELETE("/:id", func(c *gin.Context) { DeleteUser(c, db, userService) })
	group.PUT("/:id/password", func(c *gin.Context) { UpdateUserPassword(c, db, userService, authService) })
}

func CreateUser(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	var req models.UserRegistrationInput
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create user data map from request
	userData := map[string]interface{}{
		"email":        req.Email,
		"password":     req.Password,
		"username":     req.Username,
		"display_name": req.DisplayName,
		"profile_pic":  req.ProfilePic,
		"preferences":  req.Preferences,
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

	// Check if the authenticated user is requesting their own data or has permission
	contextUserID, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	userUUID, ok := contextUserID.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
		return
	}

	// Convert the path parameter ID to UUID for comparison
	pathID, err := uuid.Parse(id)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID format"})
		return
	}

	// Get user data
	user, err := userService.GetUserById(db, id)
	if err != nil {
		if errors.Is(err, services.ErrUserNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Check if fields parameter exists to filter response
	if fields := c.Query("fields"); fields != "" && userUUID != pathID {
		// If not the user themselves, only return specific fields
		// for security/privacy reasons
		fieldList := strings.Split(fields, ",")
		filteredData := make(map[string]interface{})

		// Only allow certain fields for security
		allowedFields := map[string]bool{
			"id": true, "username": true, "display_name": true, "profile_pic": true,
		}

		for _, field := range fieldList {
			field = strings.TrimSpace(field)
			if allowedFields[field] {
				switch field {
				case "id":
					filteredData["id"] = user.ID
				case "username":
					filteredData["username"] = user.Username
				case "display_name":
					filteredData["display_name"] = user.DisplayName
				case "profile_pic":
					filteredData["profile_pic"] = user.ProfilePic
				}
			}
		}
		c.JSON(http.StatusOK, filteredData)
		return
	}

	// If the user is requesting their own data, return full data
	// Or if no fields specified, but hide sensitive info for other users
	if userUUID != pathID {
		// Return limited data for other users
		c.JSON(http.StatusOK, gin.H{
			"id":           user.ID,
			"username":     user.Username,
			"display_name": user.DisplayName,
			"profile_pic":  user.ProfilePic,
		})
	} else {
		// Return all data for the user themselves
		c.JSON(http.StatusOK, user)
	}
}

func UpdateUser(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	id := c.Param("id")
	var req models.UserUpdateInput
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Check if the authenticated user is updating their own account
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
	if req.Username != "" {
		updateData["username"] = req.Username
	}
	if req.DisplayName != "" {
		updateData["display_name"] = req.DisplayName
	}
	if req.ProfilePic != "" {
		updateData["profile_pic"] = req.ProfilePic
	}
	if req.Preferences != nil {
		updateData["preferences"] = req.Preferences
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

	if username := c.Query("username"); username != "" {
		params["username"] = username
	}

	// Add support for fields parameter
	if fields := c.Query("fields"); fields != "" {
		params["fields"] = fields
	}

	users, err := userService.GetUsers(db, params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Check if fields parameter exists to filter response
	if fields, ok := params["fields"].(string); ok && fields != "" {
		fieldList := strings.Split(fields, ",")
		var filteredUsers []map[string]interface{}

		// Only allow certain fields for security
		allowedFields := map[string]bool{
			"id": true, "username": true, "display_name": true,
			"profile_pic": true, "email": true, "created_at": true,
			"updated_at": true, "preferences": true,
		}

		for _, user := range users {
			filteredUser := make(map[string]interface{})

			for _, field := range fieldList {
				field = strings.TrimSpace(field)
				if allowedFields[field] {
					switch field {
					case "id":
						filteredUser["id"] = user.ID
					case "username":
						filteredUser["username"] = user.Username
					case "display_name":
						filteredUser["display_name"] = user.DisplayName
					case "profile_pic":
						filteredUser["profile_pic"] = user.ProfilePic
					case "email":
						filteredUser["email"] = user.Email
					case "created_at":
						filteredUser["created_at"] = user.CreatedAt
					case "updated_at":
						filteredUser["updated_at"] = user.UpdatedAt
					case "preferences":
						filteredUser["preferences"] = user.Preferences
					}
				}
			}
			filteredUsers = append(filteredUsers, filteredUser)
		}
		c.JSON(http.StatusOK, filteredUsers)
		return
	}

	c.JSON(http.StatusOK, users)
}

// UpdateUserPassword handles password changes with verification of the current password
func UpdateUserPassword(c *gin.Context, db *database.Database, userService services.UserServiceInterface, authService services.AuthServiceInterface) {
	id := c.Param("id")

	// Check if the authenticated user is updating their own password
	contextUserID, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User not authenticated"})
		return
	}

	userUUID, ok := contextUserID.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Invalid user ID format"})
		return
	}

	// Convert the path parameter ID to UUID for comparison
	pathID, err := uuid.Parse(id)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID format"})
		return
	}

	// Only allow users to update their own password
	if userUUID != pathID {
		c.JSON(http.StatusForbidden, gin.H{"error": "You can only update your own password"})
		return
	}

	var passwordData models.UserPasswordUpdateInput
	if err := c.ShouldBindJSON(&passwordData); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify current password
	user, err := userService.GetUserById(db, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to retrieve user"})
		return
	}

	if err := authService.ComparePasswords(user.PasswordHash, passwordData.CurrentPassword); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Current password is incorrect"})
		return
	}

	// Update with new password
	updateData := map[string]interface{}{
		"password": passwordData.NewPassword,
	}

	_, err = userService.UpdateUser(db, id, updateData)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update password"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Password updated successfully"})
}
