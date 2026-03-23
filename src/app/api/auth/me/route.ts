import { NextRequest, NextResponse } from 'next/server';
import { getUserFromToken } from '@/lib/jwt';
import type { AuthResponse } from '@/types/auth';

export async function GET(request: NextRequest): Promise<NextResponse<AuthResponse>> {
  try {
    const user = await getUserFromToken();
    
    if (!user) {
      return NextResponse.json(
        { success: false, message: 'No autenticado' },
        { status: 401 }
      );
    }
    
    return NextResponse.json({
      success: true,
      user,
    });
  } catch (error) {
    console.error('Me error:', error);
    return NextResponse.json(
      { success: false, message: 'Error interno del servidor' },
      { status: 500 }
    );
  }
}