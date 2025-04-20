package routes

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/thinkstack/database"
	"github.com/thinkstack/services"
)

type loginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

type loginResponse struct {
	Token string `json:"token"`
}

func RegisterAuthRoutes(router *gin.Engine, db *database.Database, authService services.AuthServiceInterface) {
	group := router.Group("/api/v1/auth")
	{
		group.POST("/login", func(c *gin.Context) { Login(c, db, authService) })
	}
}

func Login(c *gin.Context, db *database.Database, authService services.AuthServiceInterface) {
	var request loginRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	token, err := authService.Login(db, request.Email, request.Password)
	if err != nil {
		if err == services.ErrInvalidCredentials {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid email or password"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, loginResponse{Token: token})
}
