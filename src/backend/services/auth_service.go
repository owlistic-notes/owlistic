package services

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/thinkstack/database"
	"github.com/thinkstack/models"
	"golang.org/x/crypto/bcrypt"
)

// Common auth errors
var (
	ErrAuthHeaderMissing = errors.New("Authentication required")
	ErrInvalidAuthFormat = errors.New("Authorization header format must be Bearer {token}")
)

// JWTClaims holds the standard JWT claims plus our custom claims
type JWTClaims struct {
	UserID uuid.UUID `json:"user_id"`
	Email  string    `json:"email"`
	jwt.RegisteredClaims
}

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

	token, err := s.generateToken(user)
	if err != nil {
		return "", err
	}

	return token, nil
}

func (s *AuthService) ValidateToken(tokenString string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return s.jwtSecret, nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*JWTClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, ErrInvalidToken
}

func (s *AuthService) generateToken(user models.User) (string, error) {
	claims := JWTClaims{
		UserID: user.ID,
		Email:  user.Email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(s.jwtExpiration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signedToken, err := token.SignedString(s.jwtSecret)
	if err != nil {
		return "", err
	}

	return signedToken, nil
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
