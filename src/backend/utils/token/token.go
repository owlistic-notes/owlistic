package token

import (
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// Common auth errors
var (
	ErrAuthHeaderMissing = errors.New("Authentication required")
	ErrInvalidAuthFormat = errors.New("Authorization header format must be Bearer {token}")
	ErrInvalidToken      = errors.New("Invalid or expired token")
)

// JWTClaims holds the standard JWT claims plus our custom claims
type JWTClaims struct {
	UserID uuid.UUID `json:"user_id"`
	Email  string    `json:"email"`
	jwt.RegisteredClaims
}

// ValidateToken validates a JWT token string and returns the claims
func ValidateToken(tokenString string, secret []byte) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return secret, nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*JWTClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, ErrInvalidToken
}

// GenerateToken creates a new JWT token for a user
func GenerateToken(userID uuid.UUID, email string, secret []byte, expiration time.Duration) (string, error) {
	claims := JWTClaims{
		UserID: userID,
		Email:  email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(expiration)),
			IssuedAt:  jwt.NewNumericDate(time.Now().UTC()),
			NotBefore: jwt.NewNumericDate(time.Now().UTC()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signedToken, err := token.SignedString(secret)
	if err != nil {
		return "", err
	}

	return signedToken, nil
}

// ExtractToken extracts a token from query parameters or authorization header
func ExtractToken(c *gin.Context) (string, error) {
	// First try to get token from query parameter (common for WebSocket connections)
	token := c.Query("token")

	// If not in query, try header (for REST API)
	if token == "" {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			return "", ErrAuthHeaderMissing
		}

		// Extract token from Bearer schema
		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			return "", ErrInvalidAuthFormat
		}
		token = parts[1]
	}

	return token, nil
}

// ExtractAndValidateToken combines extraction and validation
func ExtractAndValidateToken(c *gin.Context, secret []byte) (*JWTClaims, error) {
	tokenString, err := ExtractToken(c)
	if err != nil {
		return nil, err
	}

	return ValidateToken(tokenString, secret)
}
