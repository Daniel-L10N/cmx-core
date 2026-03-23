'use client';

import type { ButtonHTMLAttributes } from 'react';
import { Button as BaseButton } from '@/components/ui/Button';

interface SubmitButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'type'> {
  isLoading?: boolean;
  loadingText?: string;
  children: React.ReactNode;
}

export function SubmitButton({
  isLoading = false,
  loadingText = 'Loading...',
  children,
  disabled,
  ...props
}: SubmitButtonProps) {
  return (
    <BaseButton
      type="submit"
      isLoading={isLoading}
      disabled={disabled || isLoading}
      className="w-full"
      {...props}
    >
      {isLoading ? loadingText : children}
    </BaseButton>
  );
}
