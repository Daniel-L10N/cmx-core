/**
 * JWT Authentication Library - Server-Side Token Management
 * 
 * Security Model:
 * - Tokens are stored in HTTP-only cookies (NOT localStorage)
 * - HttpOnly flag prevents JavaScript access (XSS protection)
 * - Secure flag ensures HTTPS-only transmission
 * - SameSite=Strict prevents CSRF attacks
 * 
 * All functions marked "server-only" should only be called from:
 * - API Route Handlers (app/api/*)
 * - Server Actions (server-only)
 * - Middleware (middleware.ts)
 * 
 * NEVER call these from client components!
 */

import { cookies } from 'next/headers';
import type { JWTPayload, AuthUser, CookieOptions, TOKEN_COOKIE_NAMES } from '@/types/auth';

// =============================================================================
// Constants
// =============================================================================

const ACCESS_TOKEN_COOKIE = 'accessToken';
const REFRESH_TOKEN_COOKIE = 'refreshToken';

/**
 * Token expiration times (in seconds)
 * Access token: 15 minutes (900 seconds)
 * Refresh token: 7 days (604800 seconds)
 */
export const TOKEN_EXPIRY = {
  ACCESS: 900,      // 15 minutes
  REFRESH: 604800, // 7 days
} as const;

// =============================================================================
// Cookie Configuration
// =============================================================================

/**
 * Get cookie options for access token
 * Short-lived, needs secure defaults
 */
function getAccessTokenCookieOptions(): CookieOptions {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: TOKEN_EXPIRY.ACCESS,
    path: '/',
  };
}

/**
 * Get cookie options for refresh token
 * Longer-lived, same security requirements
 */
function getRefreshTokenCookieOptions(): CookieOptions {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: TOKEN_EXPIRY.REFRESH,
    path: '/',
  };
}

// =============================================================================
// Token Reading (Server-Side Only)
// =============================================================================

/**
 * Get access token from HTTP-only cookie
 * 
 * SECURITY: This function reads from HttpOnly cookies, NOT localStorage.
 * JavaScript/XSS attacks CANNOT access tokens via this function.
 * 
 * @returns The access token string or null if not present/expired
 */
export async function getAccessToken(): Promise<string | null> {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get(ACCESS_TOKEN_COOKIE);
  
  if (!accessToken?.value) {
    return null;
  }
  
  // Validate token structure and expiration
  if (isTokenExpired(accessToken.value)) {
    // Token expired, clear it
    await clearTokens();
    return null;
  }
  
  return accessToken.value;
}

/**
 * Get refresh token from HTTP-only cookie
 * Used for refreshing expired access tokens
 */
export async function getRefreshToken(): Promise<string | null> {
  const cookieStore = await cookies();
  const refreshToken = cookieStore.get(REFRESH_TOKEN_COOKIE);
  return refreshToken?.value ?? null;
}

/**
 * Decode JWT payload without verification
 * Use only for reading claims, not for authentication
 */
export function decodeJWT(token: string): JWTPayload | null {
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const jsonPayload = decodeURIComponent(
      atob(base64)
        .split('')
        .map((c) => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
        .join('')
    );
    return JSON.parse(jsonPayload) as JWTPayload;
  } catch {
    return null;
  }
}

/**
 * Check if a JWT token is expired
 * Compares exp claim against current time
 */
export function isTokenExpired(token: string): boolean {
  const payload = decodeJWT(token);
  if (!payload) return true;
  
  // Add 30-second buffer for clock skew
  return payload.exp * 1000 < Date.now() - 30000;
}

/**
 * Extract user info from access token payload
 */
export async function getUserFromToken(): Promise<AuthUser | null> {
  const token = await getAccessToken();
  if (!token) return null;
  
  const payload = decodeJWT(token);
  if (!payload) return null;
  
  return {
    id: payload.sub,
    email: payload.email,
    createdAt: new Date(payload.iat * 1000).toISOString(),
  };
}

// =============================================================================
// Token Storage (Server-Side Only - Set-Cookie)
// =============================================================================

/**
 * Set authentication tokens as HTTP-only cookies
 * 
 * SECURITY: This function sets HttpOnly cookies, making tokens
 * inaccessible to JavaScript. XSS attacks cannot steal tokens.
 * 
 * @param accessToken - JWT access token (short-lived)
 * @param refreshToken - JWT refresh token (long-lived)
 */
export async function setTokens(
  accessToken: string,
  refreshToken: string
): Promise<void> {
  const cookieStore = await cookies();
  
  cookieStore.set(ACCESS_TOKEN_COOKIE, accessToken, getAccessTokenCookieOptions());
  cookieStore.set(REFRESH_TOKEN_COOKIE, refreshToken, getRefreshTokenCookieOptions());
}

/**
 * Clear all authentication cookies
 * Used on logout and token refresh failures
 */
export async function clearTokens(): Promise<void> {
  const cookieStore = await cookies();
  
  cookieStore.delete(ACCESS_TOKEN_COOKIE);
  cookieStore.delete(REFRESH_TOKEN_COOKIE);
}

/**
 * Set only the access token (for refresh operations)
 * Keeps the refresh token cookie unchanged
 */
export async function setAccessToken(accessToken: string): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.set(ACCESS_TOKEN_COOKIE, accessToken, getAccessTokenCookieOptions());
}

// =============================================================================
// Token Refresh
// =============================================================================

/**
 * Refresh the access token using the refresh token
 * 
 * SECURITY: Both tokens are sent/received via HTTP-only cookies.
 * The refresh token is NOT exposed to JavaScript.
 * 
 * @returns The new access token or null if refresh failed
 */
export async function refreshAccessToken(): Promise<string | null> {
  const refreshToken = await getRefreshToken();
  if (!refreshToken) {
    return null;
  }
  
  try {
    // Call backend to refresh tokens
    // Backend reads refresh token from cookie, sets new access token cookie
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_API_URL}/api/auth/refresh/`,
      {
        method: 'POST',
        credentials: 'include', // IMPORTANT: Send cookies to backend
        headers: {
          'Content-Type': 'application/json',
        },
        // Refresh token is automatically sent via HTTP-only cookie
        // NO need to include it in request body
      }
    );
    
    if (!response.ok) {
      // Refresh failed, clear all tokens
      await clearTokens();
      return null;
    }
    
    const data = await response.json();
    
    if (data.success && data.accessToken) {
      // Set the new access token cookie
      await setAccessToken(data.accessToken);
      return data.accessToken;
    }
    
    return null;
  } catch (error) {
    // Network error or invalid response
    console.error('Token refresh failed:', error);
    await clearTokens();
    return null;
  }
}

/**
 * Get a valid access token, refreshing if necessary
 * 
 * @returns The access token or null if unavailable
 */
export async function getValidAccessToken(): Promise<string | null> {
  const token = await getAccessToken();
  
  if (token && !isTokenExpired(token)) {
    return token;
  }
  
  // Token missing or expired, try to refresh
  return refreshAccessToken();
}

// =============================================================================
// Authentication Headers (for Server-Side Fetching)
// =============================================================================

/**
 * Get authorization header for API requests
 * Used when making requests from server to backend API
 */
export async function getAuthHeaders(): Promise<Record<string, string>> {
  const token = await getAccessToken();
  
  if (token) {
    return {
      Authorization: `Bearer ${token}`,
    };
  }
  
  return {};
}

/**
 * Get authorization header with automatic token refresh
 * Ensures the token is valid before making requests
 */
export async function getValidAuthHeaders(): Promise<Record<string, string>> {
  const token = await getValidAccessToken();
  
  if (token) {
    return {
      Authorization: `Bearer ${token}`,
    };
  }
  
  return {};
}

// =============================================================================
// Authenticated Fetch Wrapper
// =============================================================================

/**
 * Fetch wrapper that automatically includes auth credentials
 * For server-side API calls to protected endpoints
 */
export async function authFetch(
  url: string,
  options: RequestInit = {}
): Promise<Response> {
  const headers = await getValidAuthHeaders();
  
  const response = await fetch(url, {
    ...options,
    credentials: 'include', // Include HTTP-only cookies
    headers: {
      'Content-Type': 'application/json',
      ...headers,
      ...options.headers,
    },
  });
  
  // If 401, tokens were invalidated server-side
  if (response.status === 401) {
    await clearTokens();
  }
  
  return response;
}

// =============================================================================
// Client-Side Token Check (No Token Exposure)
// =============================================================================

/**
 * Check if user is authenticated (without exposing token)
 * This function does NOT return the token itself, only auth state.
 * 
 * Uses /api/auth/me endpoint which reads the HTTP-only cookie.
 * The token value is NEVER exposed to client-side JavaScript.
 */
export async function checkAuthStatus(): Promise<AuthUser | null> {
  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_API_URL}/api/auth/me/`,
      {
        credentials: 'include', // Send HTTP-only cookie
        cache: 'no-store', // Don't cache auth state
      }
    );
    
    if (!response.ok) {
      return null;
    }
    
    const data = await response.json();
    
    if (data.success && data.user) {
      return data.user as AuthUser;
    }
    
    return null;
  } catch {
    return null;
  }
}
