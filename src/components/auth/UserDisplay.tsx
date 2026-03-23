'use client';

interface UserDisplayProps {
  email: string;
  className?: string;
}

export function UserDisplay({ email, className = '' }: UserDisplayProps) {
  return (
    <span
      className={`
        text-gray-700 font-medium
        ${className}
      `}
    >
      {email}
    </span>
  );
}
