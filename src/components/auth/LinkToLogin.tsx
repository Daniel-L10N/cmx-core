'use client';

import Link from 'next/link';

interface LinkToLoginProps {
  children: React.ReactNode;
  href?: string;
  className?: string;
}

export function LinkToLogin({
  children,
  href = '/login',
  className = '',
}: LinkToLoginProps) {
  return (
    <Link
      href={href}
      className={`
        text-blue-600 hover:text-blue-700 hover:underline
        transition-colors duration-200
        ${className}
      `}
    >
      {children}
    </Link>
  );
}
