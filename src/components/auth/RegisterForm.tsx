'use client';

import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { useAuthStore } from '@/stores/authStore';
import { Input } from '@/components/ui/Input';
import { PasswordInput } from '@/components/ui/PasswordInput';
import { Card } from '@/components/ui/Card';
import { SubmitButton } from './SubmitButton';
import { ErrorMessage } from './ErrorMessage';
import { LinkToLogin } from './LinkToLogin';

interface RegisterFormProps {
  onSuccess?: () => void;
}

const PASSWORD_MIN_LENGTH = 8;
const PASSWORD_REGEX = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]/;

export function RegisterForm({ onSuccess }: RegisterFormProps) {
  const router = useRouter();
  const { register, isLoading } = useAuthStore();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [passwordConfirm, setPasswordConfirm] = useState('');
  const [errors, setErrors] = useState<{
    email?: string;
    password?: string;
    passwordConfirm?: string;
    general?: string;
  }>({});

  const validateForm = (): boolean => {
    const newErrors: typeof errors = {};

    if (!email) {
      newErrors.email = 'Email is required';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      newErrors.email = 'Please enter a valid email address';
    }

    if (!password) {
      newErrors.password = 'Password is required';
    } else if (password.length < PASSWORD_MIN_LENGTH) {
      newErrors.password = `Password must be at least ${PASSWORD_MIN_LENGTH} characters`;
    } else if (!PASSWORD_REGEX.test(password)) {
      newErrors.password = 'Password must contain uppercase, lowercase, number, and special character';
    }

    if (!passwordConfirm) {
      newErrors.passwordConfirm = 'Please confirm your password';
    } else if (password !== passwordConfirm) {
      newErrors.passwordConfirm = 'Passwords do not match';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setErrors({});

    if (!validateForm()) return;

    const success = await register({ email, password, passwordConfirm });

    if (success) {
      onSuccess?.();
      router.push('/');
    } else {
      setErrors({ general: 'Registration failed. This email may already be in use.' });
    }
  };

  return (
    <Card className="max-w-md mx-auto mt-8">
      <form onSubmit={handleSubmit} className="space-y-6">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-gray-900">Create Account</h1>
          <p className="mt-2 text-sm text-gray-600">
            Get started with your free account
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
          placeholder="Create a strong password"
          autoComplete="new-password"
          required
          disabled={isLoading}
          helperText={`At least ${PASSWORD_MIN_LENGTH} characters with uppercase, lowercase, number, and symbol`}
        />

        <PasswordInput
          label="Confirm Password"
          id="passwordConfirm"
          name="passwordConfirm"
          value={passwordConfirm}
          onChange={(e) => setPasswordConfirm(e.target.value)}
          error={errors.passwordConfirm}
          placeholder="Confirm your password"
          autoComplete="new-password"
          required
          disabled={isLoading}
        />

        <SubmitButton
          isLoading={isLoading}
          loadingText="Creating account..."
        >
          Create Account
        </SubmitButton>

        <p className="text-center text-sm text-gray-600">
          Already have an account?{' '}
          <LinkToLogin href="/login">
            Sign in
          </LinkToLogin>
        </p>
      </form>
    </Card>
  );
}
