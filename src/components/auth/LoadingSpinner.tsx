'use client';

interface LoadingSpinnerProps {
  size?: 'sm' | 'md' | 'lg';
  fullScreen?: boolean;
  text?: string;
  className?: string;
}

import { Spinner } from '@/components/ui/Spinner';

export function LoadingSpinner({
  size = 'md',
  fullScreen = false,
  text,
  className = '',
}: LoadingSpinnerProps) {
  if (fullScreen) {
    return (
      <div
        className={`
          fixed inset-0
          flex flex-col items-center justify-center
          bg-white/80 backdrop-blur-sm
          z-50
          ${className}
        `}
      >
        <Spinner size="lg" />
        {text && <p className="mt-4 text-gray-600">{text}</p>}
      </div>
    );
  }

  return (
    <div
      className={`
        flex flex-col items-center justify-center
        ${className}
      `}
    >
      <Spinner size={size} />
      {text && <p className="mt-2 text-gray-600 text-sm">{text}</p>}
    </div>
  );
}
