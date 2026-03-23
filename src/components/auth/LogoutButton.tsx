'use client';

import type { ButtonHTMLAttributes } from 'react';
import { Button } from '@/components/ui/Button';

interface LogoutButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'> {
  onClick: () => void;
  isLoading?: boolean;
  children?: React.ReactNode;
}

export function LogoutButton({
  onClick,
  isLoading = false,
  children = 'Logout',
  disabled,
  ...props
}: LogoutButtonProps) {
  return (
    <Button
      variant="danger"
      onClick={onClick}
      disabled={disabled || isLoading}
      isLoading={isLoading}
      className="inline-flex items-center gap-2"
      {...props}
    >
      <svg
        className="h-4 w-4"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={2}
          d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
        />
      </svg>
      {children}
    </Button>
  );
}
