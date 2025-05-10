package routes

import (
	"net/http"

	"owlistic-notes/owlistic/database"
	"owlistic-notes/owlistic/models"
	"owlistic-notes/owlistic/services"

	"github.com/gin-gonic/gin"
)

func RegisterAuthRoutes(group *gin.RouterGroup, db *database.Database, authService services.AuthServiceInterface) {
	group.POST("/login", func(c *gin.Context) { Login(c, db, authService) })
}

func Login(c *gin.Context, db *database.Database, authService services.AuthServiceInterface) {
	var loginInput models.UserLoginInput
	if err := c.ShouldBindJSON(&loginInput); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	token, err := authService.Login(db, loginInput.Email, loginInput.Password)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid credentials"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"token": token})
}
