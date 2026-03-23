/**
 * Authentication Types - JWT Authentication System
 * 
 * Spec: artifacts/specs/test-feature.json v1.0.0
 * All interfaces match the technical specification.
 */

// =============================================================================
// Core User Types
// =============================================================================

/**
 * AuthUser - User data returned from authentication endpoints
 * Matches spec: id (UUID string), email, createdAt (ISO string)
 */
export interface AuthUser {
  id: string;
  email: string;
  createdAt: string;
}

/**
 * JWTPayload - Structure of JWT token payload
 * Standard JWT claims: sub (subject/user ID), email, iat, exp
 */
export interface JWTPayload {
  sub: string;
  email: string;
  iat: number;
  exp: number;
}

/**
 * AuthState - Global authentication state
 * Used with Zustand/Context for global auth state management
 */
export interface AuthState {
  user: AuthUser | null;
  isAuthenticated: boolean;
  isLoading: boolean;
}

// =============================================================================
// Request Types (API Calls)
// =============================================================================

/**
 * RegisterRequest - Body for POST /api/auth/register
 * Fields: email, password, passwordConfirm (camelCase per spec)
 */
export interface RegisterRequest {
  email: string;
  password: string;
  passwordConfirm: string;
}

/**
 * LoginRequest - Body for POST /api/auth/login
 * Fields: email, password (per spec)
 */
export interface LoginRequest {
  email: string;
  password: string;
}

// =============================================================================
// Response Types (API Responses)
// =============================================================================

/**
 * AuthResponse - Generic authentication response
 * Contains success flag, optional message, and optional user data
 */
export interface AuthResponse {
  success: boolean;
  message?: string;
  user?: AuthUser;
}

/**
 * RefreshTokenResponse - Body for POST /api/auth/refresh
 * Returns new accessToken in JSON body (tokens managed via HTTP-only cookies)
 */
export interface RefreshTokenResponse {
  success: boolean;
  accessToken: string;
}

// =============================================================================
// Token Management (Server-Side Only)
// =============================================================================

/**
 * CookieOptions - Configuration for HTTP-only cookies
 * Security flags: HttpOnly, Secure, SameSite=Strict
 */
export interface CookieOptions {
  httpOnly: boolean;
  secure: boolean;
  sameSite: 'strict' | 'lax' | 'none';
  maxAge?: number;
  path?: string;
  domain?: string;
}

/**
 * TokenCookieNames - Cookie name constants
 * IMPORTANT: These are HTTP-only cookie names, NOT localStorage keys
 */
export const TOKEN_COOKIE_NAMES = {
  ACCESS_TOKEN: 'accessToken',
  REFRESH_TOKEN: 'refreshToken',
} as const;

/**
 * Default cookie options for authentication tokens
 * HttpOnly: Prevents JavaScript access (XSS protection)
 * Secure: HTTPS only in production
 * SameSite=Strict: Prevents CSRF attacks
 */
export const DEFAULT_COOKIE_OPTIONS: CookieOptions = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'strict',
  path: '/',
};

// =============================================================================
// Utility Types
// =============================================================================

/**
 * AuthError - Standard error format from authentication endpoints
 */
export interface AuthError {
  code: string;
  message: string;
  details?: Record<string, string[]>;
}

/**
 * ValidationError - Field-level validation errors
 */
export interface ValidationError {
  field: string;
  message: string;
}
