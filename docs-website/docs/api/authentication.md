---
sidebar_position: 1
---

# Authentication API

Owlistic uses JWT (JSON Web Tokens) for authentication. The authentication flow involves:

1. Registration or login to obtain an access token and refresh token
2. Using the access token for API requests
3. Refreshing the access token when it expires

## API Endpoints

### Register a New User

```http
POST /api/v1/auth/register
```

**Request Body:**

```json
{
  "email": "user@example.com",
  "password": "securepassword",
  "name": "User Name"
}
```

**Response:**

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "90a12345-f12a-98c4-a456-513432930000",
    "email": "user@example.com",
    "name": "User Name"
  }
}
```

### Login

```http
POST /api/v1/auth/login
```

**Request Body:**

```json
{
  "email": "user@example.com",
  "password": "securepassword"
}
```

**Response:**

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "90a12345-f12a-98c4-a456-513432930000",
    "email": "user@example.com",
    "name": "User Name"
  }
}
```

### Refresh Token

```http
POST /api/v1/auth/refresh
```

**Request Body:**

```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response:**

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### Logout

```http
POST /api/v1/auth/logout
```

**Headers:**
- Authorization: Bearer {access_token}

**Response:**

```json
{
  "message": "Successfully logged out"
}
```
