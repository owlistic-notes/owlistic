package routes

import (
	"errors"
	"net/http"

	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"github.com/thinkstack/services"

	"github.com/gin-gonic/gin"
)

func RegisterUserRoutes(router *gin.Engine, db *database.Database, userService services.UserServiceInterface) {
	group := router.Group("/api/v1/users")
	{
		group.GET("/", func(c *gin.Context) { GetAllUsers(c, db, userService) })
		group.POST("/", func(c *gin.Context) { CreateUser(c, db, userService) })
		group.GET("/:id", func(c *gin.Context) { GetUserById(c, db, userService) })
		group.PUT("/:id", func(c *gin.Context) { UpdateUser(c, db, userService) })
		group.DELETE("/:id", func(c *gin.Context) { DeleteUser(c, db, userService) })
	}
}

func CreateUser(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	var user models.User
	if err := c.ShouldBindJSON(&user); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	createdUser, err := userService.CreateUser(db, user)
	if err != nil {
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

func UpdateUser(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	id := c.Param("id")
	var user models.User
	if err := c.ShouldBindJSON(&user); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	updatedUser, err := userService.UpdateUser(db, id, user)
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

func GetAllUsers(c *gin.Context, db *database.Database, userService services.UserServiceInterface) {
	users, err := userService.GetAllUsers(db)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, users)
}
