'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { useAuthStore } from '@/stores/authStore';
import { Input } from '@/components/ui/Input';
import { PasswordInput } from '@/components/ui/PasswordInput';
import { Card } from '@/components/ui/Card';
import { SubmitButton } from './SubmitButton';
import { ErrorMessage } from './ErrorMessage';
import { LinkToRegister } from './LinkToRegister';

interface LoginFormProps {
  onSuccess?: () => void;
}

export function LoginForm({ onSuccess }: LoginFormProps) {
  const router = useRouter();
  const { login, isLoading } = useAuthStore();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errors, setErrors] = useState<{ email?: string; password?: string; general?: string }>({});

  const validateForm = (): boolean => {
    const newErrors: typeof errors = {};

    if (!email) {
      newErrors.email = 'Email is required';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      newErrors.email = 'Please enter a valid email address';
    }

    if (!password) {
      newErrors.password = 'Password is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setErrors({});

    if (!validateForm()) return;

    const success = await login({ email, password });

    if (success) {
      onSuccess?.();
      router.push('/');
    } else {
      setErrors({ general: 'Invalid email or password. Please try again.' });
    }
  };

  return (
    <Card className="max-w-md mx-auto mt-8">
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-gray-900">Welcome Back</h1>
          <p className="mt-2 text-sm text-gray-600">
            Sign in to your account
          </p>
        </div>

        {errors.general && (
          <ErrorMessage message={errors.general} />
        )}

        <Input
          label="Email Address"
          type="email"
          id="email"
          name="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          error={errors.email}
          placeholder="you@example.com"
          autoComplete="email"
          required
          disabled={isLoading}
        />

        <PasswordInput
          label="Password"
          id="password"
          name="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          error={errors.password}
          placeholder="Enter your password"
          autoComplete="current-password"
          required
          disabled={isLoading}
        />

        <SubmitButton
          isLoading={isLoading}
          loadingText="Signing in..."
        >
          Sign In
        </SubmitButton>

        <p className="text-center text-sm text-gray-600">
          Don&apos;t have an account?{' '}
          <LinkToRegister href="/register">
            Create one now
          </LinkToRegister>
        </p>
      </form>
    </Card>
  );
}
