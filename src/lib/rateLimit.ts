import { NextRequest, NextResponse } from 'next/server';

interface RateLimitEntry {
  count: number;
  resetTime: number;
}

const rateLimitStore = new Map<string, RateLimitEntry>();

function cleanupExpiredEntries(): void {
  const now = Date.now();
  for (const [key, entry] of rateLimitStore.entries()) {
    if (entry.resetTime < now) {
      rateLimitStore.delete(key);
    }
  }
}

export function getRateLimitKey(request: NextRequest, identifier: string): string {
  const forwarded = request.headers.get('x-forwarded-for');
  const ip = forwarded ? forwarded.split(',')[0].trim() : request.ip || 'unknown';
  return `${identifier}:${ip}`;
}

export interface RateLimitConfig {
  maxRequests: number;
  windowSeconds: number;
  message?: string;
}

const DEFAULT_CONFIG: RateLimitConfig = {
  maxRequests: parseInt(process.env.AUTH_RATE_LIMIT_MAX || '5'),
  windowSeconds: parseInt(process.env.AUTH_RATE_LIMIT_WINDOW || '60'),
  message: 'Demasiadas solicitudes. Por favor intenta más tarde.',
};

export function checkRateLimit(
  request: NextRequest,
  config: RateLimitConfig = DEFAULT_CONFIG
): { success: boolean; remaining: number; resetTime: number } {
  cleanupExpiredEntries();
  
  const key = getRateLimitKey(request, 'auth');
  const now = Date.now();
  const windowMs = config.windowSeconds * 1000;
  
  const entry = rateLimitStore.get(key);
  
  if (!entry || entry.resetTime < now) {
    rateLimitStore.set(key, {
      count: 1,
      resetTime: now + windowMs,
    });
    return {
      success: true,
      remaining: config.maxRequests - 1,
      resetTime: now + windowMs,
    };
  }
  
  if (entry.count >= config.maxRequests) {
    return {
      success: false,
      remaining: 0,
      resetTime: entry.resetTime,
    };
  }
  
  entry.count++;
  return {
    success: true,
    remaining: config.maxRequests - entry.count,
    resetTime: entry.resetTime,
  };
}

export function rateLimitMiddleware(
  config: RateLimitConfig = DEFAULT_CONFIG
) {
  return (request: NextRequest): NextResponse | null => {
    const result = checkRateLimit(request, config);
    
    if (!result.success) {
      const response = NextResponse.json(
        {
          success: false,
          message: config.message || DEFAULT_CONFIG.message,
          retryAfter: Math.ceil((result.resetTime - Date.now()) / 1000),
        },
        { status: 429 }
      );
      
      response.headers.set('Retry-After', Math.ceil((result.resetTime - Date.now()) / 1000).toString());
      response.headers.set('X-RateLimit-Limit', config.maxRequests.toString());
      response.headers.set('X-RateLimit-Remaining', '0');
      
      return response;
    }
    
    const response = NextResponse.next();
    response.headers.set('X-RateLimit-Limit', config.maxRequests.toString());
    response.headers.set('X-RateLimit-Remaining', result.remaining.toString());
    
    return response;
  };
}

export async function withRateLimit(
  request: NextRequest,
  handler: (request: NextRequest) => Promise<NextResponse>,
  config: RateLimitConfig = DEFAULT_CONFIG
): Promise<NextResponse> {
  const rateLimitResult = checkRateLimit(request, config);
  
  if (!rateLimitResult.success) {
    return NextResponse.json(
      {
        success: false,
        message: config.message || DEFAULT_CONFIG.message,
        retryAfter: Math.ceil((rateLimitResult.resetTime - Date.now()) / 1000),
      },
      { status: 429 }
    );
  }
  
  const response = await handler(request);
  
  response.headers.set('X-RateLimit-Limit', config.maxRequests.toString());
  response.headers.set('X-RateLimit-Remaining', rateLimitResult.remaining.toString());
  
  return response;
}