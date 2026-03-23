# Authentication API Documentation

## Overview

The Authentication API provides endpoints for user registration, login, logout, token refresh, and user information retrieval. It uses JWT tokens stored in HTTP-only cookies for secure authentication.

## Base URL

```
http://localhost:3000/api/auth
```

## Endpoints

### POST /api/auth/register

Register a new user account.

**Request**

```json
{
  "email": "string",
  "password": "string",
  "passwordConfirm": "string"
}
```

**Headers**
- `Content-Type: application/json`

**Validation Rules**
- `email`: Must be a valid email format (e.g., `user@example.com`)
- `password`: Minimum 8 characters, must contain at least one number and one symbol
- `passwordConfirm`: Must match `password`

**Response (201 Created)**

```json
{
  "success": true,
  "message": "Usuario registrado exitosamente",
  "user": {
    "id": "string",
    "email": "string",
    "createdAt": "string"
  }
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| 400 | Missing required fields, invalid email format, weak password, passwords don't match |
| 409 | Email already registered |
| 500 | Internal server error |

**Example Request**

```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "secure123!",
    "passwordConfirm": "secure123!"
  }'
```

---

### POST /api/auth/login

Authenticate a user and generate JWT tokens.

**Request**

```json
{
  "email": "string",
  "password": "string"
}
```

**Headers**
- `Content-Type: application/json`

**Response (200 OK)**

```json
{
  "success": true,
  "message": "Login exitoso",
  "user": {
    "id": "string",
    "email": "string"
  }
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| 400 | Missing email or password |
| 401 | Invalid credentials |
| 429 | Too many requests (rate limited) |
| 500 | Internal server error |

**Example Request**

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "secure123!"
  }'
```

**Notes**
- On successful login, tokens are set as HTTP-only cookies:
  - `accessToken`: 15 minutes expiration
  - `refreshToken`: 7 days expiration

---

### POST /api/auth/logout

Log out the current user and clear authentication cookies.

**Headers**
- `Cookie: accessToken=...; refreshToken=...`

**Response (200 OK)**

```json
{
  "success": true,
  "message": "Logout exitoso"
}
```

**Example Request**

```bash
curl -X POST http://localhost:3000/api/auth/logout \
  -H "Cookie: accessToken=...; refreshToken=..."
```

**Notes**
- Clears both access and refresh token cookies
- Also calls backend logout endpoint to invalidate refresh token

---

### POST /api/auth/refresh

Refresh the access token using the refresh token.

**Headers**
- `Cookie: refreshToken=...`

**Response (200 OK)**

```json
{
  "success": true,
  "accessToken": "string"
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| 401 | No refresh token provided or invalid token |
| 500 | Internal server error |

**Example Request**

```bash
curl -X POST http://localhost:3000/api/auth/refresh \
  -H "Cookie: refreshToken=..."
```

**Notes**
- Does not require credentials, only the refresh token cookie
- Returns a new access token that can be used for subsequent requests

---

### GET /api/auth/me

Get the current authenticated user's information.

**Headers**
- `Cookie: accessToken=...`

**Response (200 OK)**

```json
{
  "success": true,
  "user": {
    "id": "string",
    "email": "string",
    "createdAt": "string"
  }
}
```

**Error Responses**

| Status | Description |
|--------|-------------|
| 401 | No access token provided or invalid/expired token |
| 500 | Internal server error |

**Example Request**

```bash
curl -X GET http://localhost:3000/api/auth/me \
  -H "Cookie: accessToken=..."
```

---

## Token Configuration

| Token | Expiration | Storage |
|-------|------------|---------|
| Access Token | 15 minutes | HTTP-only cookie |
| Refresh Token | 7 days | HTTP-only cookie |

### Cookie Attributes

- `Secure`: `false` in development, `true` in production
- `SameSite`: `strict`
- `HttpOnly`: `true` (always)

## Rate Limiting

Authentication endpoints are rate-limited to prevent brute-force attacks.

- **Limit**: 5 requests per 60 seconds
- **Response**: 429 Too Many Requests

## Environment Variables

The following environment variables configure the authentication system:

| Variable | Description | Default |
|----------|-------------|---------|
| `JWT_SECRET_KEY` | Backend JWT secret | - |
| `ACCESS_TOKEN_LIFETIME` | Access token lifetime (seconds) | 900 |
| `REFRESH_TOKEN_LIFETIME` | Refresh token lifetime (seconds) | 604800 |
| `AUTH_RATE_LIMIT_MAX` | Max requests per window | 5 |
| `AUTH_RATE_LIMIT_WINDOW` | Rate limit window (seconds) | 60 |

## Error Responses

All endpoints return consistent error responses:

```json
{
  "success": false,
  "message": "Error description"
}
```