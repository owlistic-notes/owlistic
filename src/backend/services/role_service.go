package services

import (
	"errors"
	"log"

	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"gorm.io/gorm"
)

var (
	ErrRoleNotFound       = errors.New("role not found")
	ErrResourceNotFound   = errors.New("resource not found")
	ErrInsufficientAccess = errors.New("insufficient access rights")
)

type RoleServiceInterface interface {
	AssignRole(db *database.Database, userID uuid.UUID, resourceID uuid.UUID, resourceType models.ResourceType, role models.RoleType) error
	HasAccess(db *database.Database, userID uuid.UUID, resourceID uuid.UUID, resourceType models.ResourceType, minimumRole models.RoleType) (bool, error)
	GetRole(db *database.Database, userID uuid.UUID, resourceID uuid.UUID, resourceType models.ResourceType) (models.Role, error)
	GetRoles(db *database.Database, params map[string]interface{}) ([]models.Role, error)
	RemoveRole(db *database.Database, roleID uuid.UUID) error
}

type RoleService struct{}

func NewRoleService() *RoleService {
	return &RoleService{}
}

// AssignRole assigns a role to a user for a specific resource
func (s *RoleService) AssignRole(db *database.Database, userID uuid.UUID, resourceID uuid.UUID, resourceType models.ResourceType, role models.RoleType) error {
	// Check if a role already exists for this user and resource
	var existingRole models.Role
	result := db.DB.Where("user_id = ? AND resource_id = ? AND resource_type = ?", userID, resourceID, resourceType).First(&existingRole)

	// If a role already exists, update it
	if result.Error == nil {
		existingRole.Role = role
		if err := db.DB.Save(&existingRole).Error; err != nil {
			return err
		}
		return nil
	} else if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
		// Return any error other than "record not found"
		return result.Error
	}

	// Create new role assignment
	newRole := models.Role{
		ID:           uuid.New(),
		UserID:       userID,
		ResourceID:   resourceID,
		ResourceType: resourceType,
		Role:         role,
	}

	if err := db.DB.Create(&newRole).Error; err != nil {
		return err
	}

	return nil
}

// HasAccess checks if a user has the required role for a resource
func (s *RoleService) HasAccess(db *database.Database, userID uuid.UUID, resourceID uuid.UUID, resourceType models.ResourceType, minimumRole models.RoleType) (bool, error) {
	log.Printf("Checking if user %s has %s access to %s resource %s",
		userID, minimumRole, resourceType, resourceID)

	// Check for admin role first - admins have access to everything
	var adminRoleCount int64
	if err := db.DB.Model(&models.Role{}).
		Where("user_id = ? AND resource_type = ? AND role = ?",
			userID, models.UserResource, models.AdminRole).
		Count(&adminRoleCount).Error; err != nil {
		return false, err
	}

	if adminRoleCount > 0 {
		log.Printf("User %s is an admin, granting access", userID)
		return true, nil
	}

	// For user resources, check if the user is accessing their own profile
	if resourceType == models.UserResource && userID == resourceID {
		log.Printf("User %s is accessing their own profile, granting access", userID)
		return true, nil
	}

	// Check for direct role assignment
	var role models.Role
	result := db.DB.Where("user_id = ? AND resource_id = ? AND resource_type = ?",
		userID, resourceID, resourceType).First(&role)

	if result.Error == nil {
		// Role found directly, check if it's sufficient
		sufficient := isRoleSufficient(role.Role, minimumRole)
		log.Printf("User %s has direct role %s for resource %s (required: %s): access %v",
			userID, role.Role, resourceID, minimumRole, sufficient)
		return sufficient, nil
	}

	if !errors.Is(result.Error, gorm.ErrRecordNotFound) {
		// Database error occurred
		return false, result.Error
	}

	// No direct role found, check for inherited permissions through parent resources
	log.Printf("No direct role found, checking parent resources")

	if resourceType == models.BlockResource || resourceType == models.TaskResource {
		// For blocks and tasks, check permission on their parent note
		var parentID uuid.UUID
		switch resourceType {
		case models.BlockResource:
			var block models.Block
			if err := db.DB.First(&block, "id = ?", resourceID).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					log.Printf("Block %s not found", resourceID)
					return false, nil
				}
				return false, err
			}
			parentID = block.NoteID
			log.Printf("Found parent note %s for block %s", parentID, resourceID)

		case models.TaskResource:
			var task models.Task
			if err := db.DB.First(&task, "id = ?", resourceID).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					log.Printf("Task %s not found", resourceID)
					return false, nil
				}
				return false, err
			}
			// If task is linked to a note via a block
			if task.BlockID != uuid.Nil {
				var block models.Block
				if err := db.DB.First(&block, "id = ?", task.BlockID).Error; err != nil {
					return false, err
				}
				parentID = block.NoteID
				log.Printf("Found parent note %s for task %s through block %s",
					parentID, resourceID, task.BlockID)
			} else {
				// Stand-alone task
				log.Printf("Task %s is standalone with no parent note", resourceID)
				return false, nil
			}
		}

		// Check if the resource belongs to the user directly
		var noteUserID uuid.UUID
		if err := db.DB.Model(&models.Note{}).
			Where("id = ?", parentID).
			Select("user_id").
			Take(&noteUserID).Error; err == nil {

			if noteUserID == userID {
				log.Printf("User %s owns the parent note %s, granting access", userID, parentID)
				return true, nil
			}
		}

		// Check permission on parent note through roles
		var parentRole models.Role
		parentResult := db.DB.Where(
			"user_id = ? AND resource_id = ? AND resource_type = ?",
			userID, parentID, models.NoteResource).First(&parentRole)

		if parentResult.Error == nil {
			// Check if parent role is sufficient
			sufficient := isRoleSufficient(parentRole.Role, minimumRole)
			log.Printf("User %s has role %s for parent note %s (required: %s): access %v",
				userID, parentRole.Role, parentID, minimumRole, sufficient)
			return sufficient, nil
		} else if !errors.Is(parentResult.Error, gorm.ErrRecordNotFound) {
			return false, parentResult.Error
		}

		// If note not found or no role, check parent notebook
		var note models.Note
		if err := db.DB.Select("notebook_id").First(&note, "id = ?", parentID).Error; err == nil {
			var notebookRole models.Role
			notebookResult := db.DB.Where(
				"user_id = ? AND resource_id = ? AND resource_type = ?",
				userID, note.NotebookID, models.NotebookResource).First(&notebookRole)

			if notebookResult.Error == nil {
				// Check if notebook role is sufficient
				sufficient := isRoleSufficient(notebookRole.Role, minimumRole)
				log.Printf("User %s has role %s for grandparent notebook %s (required: %s): access %v",
					userID, notebookRole.Role, note.NotebookID, minimumRole, sufficient)
				return sufficient, nil
			}
		}
	} else if resourceType == models.NoteResource {
		// For notes, check if user has access to the parent notebook
		var note models.Note
		if err := db.DB.Select("notebook_id, user_id").First(&note, "id = ?", resourceID).Error; err == nil {
			// Check if user owns the note directly
			if note.UserID == userID {
				log.Printf("User %s owns note %s directly, granting access", userID, resourceID)
				return true, nil
			}

			// Check for inherited permissions from notebook
			var notebookRole models.Role
			notebookResult := db.DB.Where(
				"user_id = ? AND resource_id = ? AND resource_type = ?",
				userID, note.NotebookID, models.NotebookResource).First(&notebookRole)

			if notebookResult.Error == nil {
				// Check if notebook role is sufficient
				sufficient := isRoleSufficient(notebookRole.Role, minimumRole)
				log.Printf("User %s has role %s for parent notebook %s (required: %s): access %v",
					userID, notebookRole.Role, note.NotebookID, minimumRole, sufficient)
				return sufficient, nil
			}
		}
	}

	// No relevant role found
	log.Printf("No access found for user %s to resource %s", userID, resourceID)
	return false, nil
}

// isRoleSufficient checks if the assigned role is at least as powerful as the required role
func isRoleSufficient(assigned models.RoleType, required models.RoleType) bool {
	roleRank := map[models.RoleType]int{
		models.AdminRole:  4,
		models.OwnerRole:  3,
		models.EditorRole: 2,
		models.ViewerRole: 1,
	}

	return roleRank[assigned] >= roleRank[required]
}

// GetRole retrieves a specific role
func (s *RoleService) GetRole(db *database.Database, userID uuid.UUID, resourceID uuid.UUID, resourceType models.ResourceType) (models.Role, error) {
	var role models.Role
	if err := db.DB.Where("user_id = ? AND resource_id = ? AND resource_type = ?", userID, resourceID, resourceType).First(&role).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return models.Role{}, ErrRoleNotFound
		}
		return models.Role{}, err
	}
	return role, nil
}

// GetRoles retrieves roles based on query parameters
func (s *RoleService) GetRoles(db *database.Database, params map[string]interface{}) ([]models.Role, error) {
	var roles []models.Role
	query := db.DB

	if userID, ok := params["user_id"].(string); ok && userID != "" {
		query = query.Where("user_id = ?", userID)
	}

	if resourceID, ok := params["resource_id"].(string); ok && resourceID != "" {
		query = query.Where("resource_id = ?", resourceID)
	}

	if resourceType, ok := params["resource_type"].(string); ok && resourceType != "" {
		query = query.Where("resource_type = ?", resourceType)
	}

	if roleType, ok := params["role"].(string); ok && roleType != "" {
		query = query.Where("role = ?", roleType)
	}

	if err := query.Find(&roles).Error; err != nil {
		return nil, err
	}

	return roles, nil
}

// RemoveRole deletes a role assignment
func (s *RoleService) RemoveRole(db *database.Database, roleID uuid.UUID) error {
	if err := db.DB.Delete(&models.Role{}, "id = ?", roleID).Error; err != nil {
		return err
	}
	return nil
}

// Global instance that will be initialized in main.go
var RoleServiceInstance RoleServiceInterface
