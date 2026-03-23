import { NextRequest, NextResponse } from 'next/server';
import { setAccessToken, getRefreshToken } from '@/lib/jwt';
import type { AuthResponse, RefreshTokenResponse } from '@/types/auth';

export async function POST(request: NextRequest): Promise<NextResponse<RefreshTokenResponse>> {
  try {
    const refreshToken = await getRefreshToken();
    
    if (!refreshToken) {
      return NextResponse.json(
        { success: false, accessToken: '' },
        { status: 401 }
      );
    }
    
    const apiUrl = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';
    const response = await fetch(`${apiUrl}/api/auth/refresh/`, {
      method: 'POST',
      credentials: 'include',
      headers: {
        'Content-Type': 'application/json',
      },
    });
    
    const data = await response.json();
    
    if (!response.ok) {
      return NextResponse.json(
        { success: false, accessToken: '' },
        { status: response.status }
      );
    }
    
    if (data.access_token) {
      await setAccessToken(data.access_token);
      return NextResponse.json({
        success: true,
        accessToken: data.access_token,
      });
    }
    
    return NextResponse.json(
      { success: false, accessToken: '' },
      { status: 400 }
    );
  } catch (error) {
    console.error('Refresh error:', error);
    return NextResponse.json(
      { success: false, accessToken: '' },
      { status: 500 }
    );
  }
}