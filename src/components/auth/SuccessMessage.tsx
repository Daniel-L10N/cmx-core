'use client';

interface SuccessMessageProps {
  message: string;
  className?: string;
}

export function SuccessMessage({ message, className = '' }: SuccessMessageProps) {
  if (!message) return null;

  return (
    <div
      className={`
        mt-2 p-3
        bg-green-50 text-green-600 text-sm
        border border-green-200 rounded-lg
        ${className}
      `}
      role="status"
    >
      <div className="flex items-start gap-2">
        <svg
          className="h-5 w-5 text-green-500 flex-shrink-0 mt-0.5"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
          />
        </svg>
        <span>{message}</span>
      </div>
    </div>
  );
}
