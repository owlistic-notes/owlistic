package services

import (
	"time"

	"daviderutigliano/owlistic/database"
	"daviderutigliano/owlistic/models"
	"daviderutigliano/owlistic/utils/token"

	"golang.org/x/crypto/bcrypt"
)

// Use the JWTClaims from token package
type JWTClaims = token.JWTClaims

type AuthServiceInterface interface {
	Login(db *database.Database, email, password string) (string, error)
	ValidateToken(tokenString string) (*JWTClaims, error)
	HashPassword(password string) (string, error)
	ComparePasswords(hashedPassword, password string) error
}

type AuthService struct {
	jwtSecret     []byte
	jwtExpiration time.Duration
}

func NewAuthService(jwtSecret string, jwtExpirationHours int) *AuthService {
	return &AuthService{
		jwtSecret:     []byte(jwtSecret),
		jwtExpiration: time.Duration(jwtExpirationHours) * time.Hour,
	}
}

func (s *AuthService) Login(db *database.Database, email, password string) (string, error) {
	var user models.User
	if err := db.DB.Where("email = ?", email).First(&user).Error; err != nil {
		return "", ErrInvalidCredentials
	}

	if err := s.ComparePasswords(user.PasswordHash, password); err != nil {
		return "", ErrInvalidCredentials
	}

	// Check if the user has any notebooks
	var notebookCount int64
	if err := db.DB.Model(&models.Notebook{}).Where("user_id = ?", user.ID).Count(&notebookCount).Error; err != nil {
		return "", err
	}

	// Use the utility function instead
	tokenString, err := token.GenerateToken(user.ID, user.Email, s.jwtSecret, s.jwtExpiration)
	if err != nil {
		return "", err
	}

	return tokenString, nil
}

// ValidateToken uses the token utility to validate tokens
func (s *AuthService) ValidateToken(tokenString string) (*JWTClaims, error) {
	return token.ValidateToken(tokenString, s.jwtSecret)
}

func (s *AuthService) HashPassword(password string) (string, error) {
	hashedBytes, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hashedBytes), nil
}

func (s *AuthService) ComparePasswords(hashedPassword, password string) error {
	return bcrypt.CompareHashAndPassword([]byte(hashedPassword), []byte(password))
}

var AuthServiceInstance AuthServiceInterface
