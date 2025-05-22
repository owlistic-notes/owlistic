package services

import (
	"errors"

	"owlistic-notes/owlistic/broker"
	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type UserServiceInterface interface {
	CreateUser(db *database.Database, userData map[string]interface{}) (models.User, error)
	GetUserById(db *database.Database, id string) (models.User, error)
	UpdateUser(db *database.Database, id string, updatedData map[string]interface{}) (models.User, error)
	DeleteUser(db *database.Database, id string) error
	GetAllUsers(db *database.Database) ([]models.User, error)
	GetUsers(db *database.Database, params map[string]interface{}) ([]models.User, error)
	GetUserByEmail(db *database.Database, email string) (models.User, error)
	AssignRole(db *database.Database, userID uuid.UUID, role models.RoleType) error
	GetUserRole(db *database.Database, userID uuid.UUID) (models.RoleType, error)
	GetUserProfile(db *database.Database, id string) (models.UserProfile, error)
	UpdateUserProfile(db *database.Database, id string, profile models.UserProfile) (models.User, error)
}

type UserService struct {
	authService AuthServiceInterface
}

func NewUserService(authService AuthServiceInterface) *UserService {
	return &UserService{
		authService: authService,
	}
}

func (s *UserService) CreateUser(db *database.Database, userData map[string]interface{}) (models.User, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.User{}, tx.Error
	}

	email, ok := userData["email"].(string)
	if !ok || email == "" {
		tx.Rollback()
		return models.User{}, errors.New("email is required")
	}

	password, ok := userData["password"].(string)
	if !ok || password == "" {
		tx.Rollback()
		return models.User{}, errors.New("password is required")
	}

	// Check if email already exists
	var existingUser models.User
	if result := tx.Where("email = ?", email).First(&existingUser); result.Error == nil {
		tx.Rollback()
		return models.User{}, ErrUserAlreadyExists
	} else if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
		tx.Rollback()
		return models.User{}, result.Error
	}

	// Check if username exists if provided
	if username, ok := userData["username"].(string); ok && username != "" {
		if result := tx.Where("username = ?", username).First(&existingUser); result.Error == nil {
			tx.Rollback()
			return models.User{}, errors.New("username already taken")
		} else if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
			tx.Rollback()
			return models.User{}, result.Error
		}
	}

	// Hash password
	hashedPassword, err := s.authService.HashPassword(password)
	if err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	user := models.User{
		ID:           uuid.New(),
		Email:        email,
		PasswordHash: hashedPassword,
	}

	// Set optional profile fields if provided
	if username, ok := userData["username"].(string); ok {
		user.Username = username
	}
	if displayName, ok := userData["display_name"].(string); ok {
		user.DisplayName = displayName
	}
	if profilePic, ok := userData["profile_pic"].(string); ok {
		user.ProfilePic = profilePic
	}
	if preferences, ok := userData["preferences"].(map[string]interface{}); ok {
		user.Preferences = preferences
	}

	if err := tx.Create(&user).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	// Assign owner role to the user for their own account
	userRole := models.Role{
		ID:           uuid.New(),
		UserID:       user.ID,
		ResourceID:   user.ID,
		ResourceType: models.UserResource,
		Role:         models.OwnerRole,
	}

	if err := tx.Create(&userRole).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	// Create event for user creation
	event, err := models.NewEvent(
		string(broker.UserCreated),
		"user",
		"create",
		user.ID.String(),
		map[string]interface{}{
			"user_id":    user.ID.String(),
			"email":      user.Email,
			"created_at": user.CreatedAt,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	return user, nil
}

func (s *UserService) GetUserByEmail(db *database.Database, email string) (models.User, error) {
	var user models.User
	if err := db.DB.Where("email = ?", email).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.User{}, ErrUserNotFound
		}
		return models.User{}, err
	}
	return user, nil
}

func (s *UserService) GetUserById(db *database.Database, id string) (models.User, error) {
	var user models.User
	if err := db.DB.First(&user, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.User{}, ErrUserNotFound
		}
		return models.User{}, err
	}
	return user, nil
}

func (s *UserService) UpdateUser(db *database.Database, id string, updatedData map[string]interface{}) (models.User, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.User{}, tx.Error
	}

	var user models.User
	if err := tx.First(&user, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.User{}, ErrUserNotFound
		}
		return models.User{}, err
	}

	updates := make(map[string]interface{})

	// Handle email update
	if email, ok := updatedData["email"].(string); ok && email != "" {
		// Check if new email already exists for another user
		if email != user.Email {
			var existingUser models.User
			if result := tx.Where("email = ? AND id != ?", email, id).First(&existingUser); result.Error == nil {
				tx.Rollback()
				return models.User{}, errors.New("email already in use")
			} else if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
				tx.Rollback()
				return models.User{}, result.Error
			}
		}
		updates["email"] = email
	}

	// Handle username update
	if username, ok := updatedData["username"].(string); ok {
		// Check if username exists for another user
		if username != user.Username {
			var existingUser models.User
			if result := tx.Where("username = ? AND id != ?", username, id).First(&existingUser); result.Error == nil {
				tx.Rollback()
				return models.User{}, errors.New("username already taken")
			} else if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
				tx.Rollback()
				return models.User{}, result.Error
			}
		}
		updates["username"] = username
	}

	// Handle other profile fields
	if displayName, ok := updatedData["display_name"].(string); ok {
		updates["display_name"] = displayName
	}
	if profilePic, ok := updatedData["profile_pic"].(string); ok {
		updates["profile_pic"] = profilePic
	}
	if preferences, ok := updatedData["preferences"].(map[string]interface{}); ok {
		updates["preferences"] = preferences
	}

	// Handle password update separately
	if password, ok := updatedData["password"].(string); ok && password != "" {
		hashedPassword, err := s.authService.HashPassword(password)
		if err != nil {
			tx.Rollback()
			return models.User{}, err
		}
		updates["password_hash"] = hashedPassword
	}

	if len(updates) > 0 {
		if err := tx.Model(&user).Updates(updates).Error; err != nil {
			tx.Rollback()
			return models.User{}, err
		}
	}

	// Reload user to get the updated data
	if err := tx.First(&user, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	// Create event for user update
	event, err := models.NewEvent(
		"user.updated",
		"user",
		"update",
		user.ID.String(),
		map[string]interface{}{
			"user_id":    user.ID.String(),
			"email":      user.Email,
			"updated_at": user.UpdatedAt,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	return user, nil
}

func (s *UserService) DeleteUser(db *database.Database, id string) error {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return tx.Error
	}

	var user models.User
	if err := tx.First(&user, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return err
	}

	// Soft delete the user
	if err := tx.Delete(&user).Error; err != nil {
		tx.Rollback()
		return err
	}

	// Create event for user deletion
	event, err := models.NewEvent(
		"user.deleted",
		"user",
		"delete",
		user.ID.String(),
		map[string]interface{}{
			"user_id":    user.ID.String(),
			"deleted_at": user.DeletedAt,
		},
	)

	if err != nil {
		tx.Rollback()
		return err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return err
	}

	if err := tx.Commit().Error; err != nil {
		return err
	}

	return nil
}

func (s *UserService) GetAllUsers(db *database.Database) ([]models.User, error) {
	var users []models.User
	if err := db.DB.Find(&users).Error; err != nil {
		return nil, err
	}
	return users, nil
}

func (s *UserService) GetUsers(db *database.Database, params map[string]interface{}) ([]models.User, error) {
	var users []models.User
	query := db.DB

	// By default, filter out deleted users
	query = query.Where("deleted_at IS NULL")

	// Apply filters based on params
	if email, ok := params["email"].(string); ok && email != "" {
		query = query.Where("email = ?", email)
	}

	if username, ok := params["username"].(string); ok && username != "" {
		query = query.Where("username = ?", username)
	}

	if err := query.Find(&users).Error; err != nil {
		return nil, err
	}
	return users, nil
}

// AssignRole assigns a role to a user
func (s *UserService) AssignRole(db *database.Database, userID uuid.UUID, role models.RoleType) error {
	// Check if user exists
	var user models.User
	if err := db.DB.Where("id = ?", userID).First(&user).Error; err != nil {
		return ErrUserNotFound
	}

	// Create a role for the user on their own user resource
	return RoleServiceInstance.AssignRole(db, userID, userID, models.UserResource, role)
}

// GetUserRole retrieves a user's role
func (s *UserService) GetUserRole(db *database.Database, userID uuid.UUID) (models.RoleType, error) {
	role, err := RoleServiceInstance.GetRole(db, userID, userID, models.UserResource)
	if err != nil {
		return "", errors.New("role not found for user")
	}
	return role.Role, nil
}

// GetUserProfile returns the UserProfile for a given user ID
func (s *UserService) GetUserProfile(db *database.Database, id string) (models.UserProfile, error) {
	var user models.User
	if err := db.DB.First(&user, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.UserProfile{}, ErrUserNotFound
		}
		return models.UserProfile{}, err
	}

	return models.UserProfile{
		Username:    user.Username,
		DisplayName: user.DisplayName,
		ProfilePic:  user.ProfilePic,
		Preferences: user.Preferences,
	}, nil
}

// UpdateUserProfile updates just the profile fields of a user
func (s *UserService) UpdateUserProfile(db *database.Database, id string, profile models.UserProfile) (models.User, error) {
	tx := db.DB.Begin()
	if tx.Error != nil {
		return models.User{}, tx.Error
	}

	var user models.User
	if err := tx.First(&user, "id = ?", id).Error; err != nil {
		tx.Rollback()
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.User{}, ErrUserNotFound
		}
		return models.User{}, err
	}

	// Check if username exists for another user if it's changing
	if profile.Username != "" && profile.Username != user.Username {
		var existingUser models.User
		if result := tx.Where("username = ? AND id != ?", profile.Username, id).First(&existingUser); result.Error == nil {
			tx.Rollback()
			return models.User{}, errors.New("username already taken")
		} else if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
			tx.Rollback()
			return models.User{}, result.Error
		}
	}

	updates := make(map[string]interface{})
	if profile.Username != "" {
		updates["username"] = profile.Username
	}
	if profile.DisplayName != "" {
		updates["display_name"] = profile.DisplayName
	}
	if profile.ProfilePic != "" {
		updates["profile_pic"] = profile.ProfilePic
	}
	if profile.Preferences != nil {
		updates["preferences"] = profile.Preferences
	}

	if err := tx.Model(&user).Updates(updates).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	// Reload user to get the updated data
	if err := tx.First(&user, "id = ?", id).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	// Create event for profile update
	event, err := models.NewEvent(
		"user.profile_updated",
		"user",
		"update_profile",
		user.ID.String(),
		map[string]interface{}{
			"user_id":    user.ID.String(),
			"username":   user.Username,
			"updated_at": user.UpdatedAt,
		},
	)

	if err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Create(event).Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		return models.User{}, err
	}

	return user, nil
}

// Global instance that will be initialized in main.go
var UserServiceInstance UserServiceInterface
