import { NextRequest, NextResponse } from 'next/server';
import { setTokens, clearTokens } from '@/lib/jwt';
import type { RegisterRequest, AuthResponse } from '@/types/auth';

export async function POST(request: NextRequest): Promise<NextResponse<AuthResponse>> {
  try {
    const body: RegisterRequest = await request.json();
    
    const { email, password, passwordConfirm } = body;
    
    if (!email || !password || !passwordConfirm) {
      return NextResponse.json(
        { success: false, message: 'Email, password y confirmación son requeridos' },
        { status: 400 }
      );
    }
    
    if (password !== passwordConfirm) {
      return NextResponse.json(
        { success: false, message: 'Las contraseñas no coinciden' },
        { status: 400 }
      );
    }
    
    // Validación de formato de email
    const emailRegex = /^[\w.-]+@[\w.-]+\.\w+$/;
    if (!emailRegex.test(email)) {
      return NextResponse.json(
        { success: false, message: 'Formato de email inválido' },
        { status: 400 }
      );
    }
    
    // Validación de fortaleza de contraseña: mínimo 8 chars, un número y un símbolo
    const passwordRegex = /^(?=.*[0-9])(?=.*[!@#$%^&*]).{8,}$/;
    if (!passwordRegex.test(password)) {
      return NextResponse.json(
        { success: false, message: 'La contraseña debe tener al menos 8 caracteres, un número y un símbolo' },
        { status: 400 }
      );
    }
    
    const apiUrl = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';
    const response = await fetch(`${apiUrl}/api/auth/register/`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password, password_confirm: passwordConfirm }),
    });
    
    const data = await response.json();
    
    if (!response.ok) {
      return NextResponse.json(
        { success: false, message: data.message || 'Error en el registro' },
        { status: response.status }
      );
    }
    
    if (data.access_token && data.refresh_token) {
      await setTokens(data.access_token, data.refresh_token);
    }
    
    return NextResponse.json({
      success: true,
      message: 'Usuario registrado exitosamente',
      user: data.user,
    });
  } catch (error) {
    console.error('Register error:', error);
    return NextResponse.json(
      { success: false, message: 'Error interno del servidor' },
      { status: 500 }
    );
  }
}