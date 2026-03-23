'use client';

import Link from 'next/link';

interface LinkToRegisterProps {
  children: React.ReactNode;
  href?: string;
  className?: string;
}

export function LinkToRegister({
  children,
  href = '/register',
  className = '',
}: LinkToRegisterProps) {
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
