# Frontend Skills — React / Next.js / TypeScript

## Technology Stack
- **Framework**: Next.js 14+ (App Router)
- **UI Library**: React 18+
- **Language**: TypeScript (strict mode)
- **Styling**: Tailwind CSS
- **State Management**: Zustand or React Query
- **Testing**: Vitest + React Testing Library + Playwright

## TypeScript Conventions

### Strict Mode Required
```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitReturns": true
  }
}
```

### Prefer Types Over Interfaces for Props
```typescript
// Props use type for consistency
type ButtonProps = {
  children: React.ReactNode;
  variant?: 'primary' | 'secondary';
  onClick?: () => void;
};

// Internal types can use interface
interface User {
  id: string;
  name: string;
}
```

### Avoid `any` — Use Unknown
```typescript
// Bad
function parse(data: any) { ... }

// Good
function parse(data: unknown) {
  if (typeof data === 'string') {
    return JSON.parse(data);
  }
  throw new Error('Invalid data');
}
```

## React Patterns

### Component Structure
```typescript
'use client';

import { useState, useCallback } from 'react';
import { cn } from '@/lib/utils';

type Props = {
  initialCount?: number;
  className?: string;
};

export function Counter({ initialCount = 0, className }: Props) {
  const [count, setCount] = useState(initialCount);
  
  const increment = useCallback(() => {
    setCount(c => c + 1);
  }, []);
  
  return (
    <button
      onClick={increment}
      className={cn('px-4 py-2', className)}
    >
      Count: {count}
    </button>
  );
}
```

### Server vs Client Components
- **Server Components** (default): For data fetching, SEO-critical content
- **Client Components** (`'use client'`): For interactivity, hooks, browser APIs

### Data Fetching
```typescript
// App Router — prefer async components
async function UsersPage() {
  const users = await db.user.findMany();
  return <UserList users={users} />;
}
```

## Next.js Conventions

### File Naming
- Components: `PascalCase.tsx`
- Utilities: `camelCase.ts`
- Pages/Routes: `kebab-case/page.tsx`
- API Routes: `route.ts`

### Route Handlers
```typescript
// app/api/users/route.ts
export async function GET(request: Request) {
  const users = await db.user.findMany();
  return Response.json(users);
}
```

### Middleware
```typescript
// middleware.ts
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  // Logic here
  return NextResponse.next();
}

export const config = {
  matcher: ['/protected/:path*'],
};
```

## Testing Patterns

### Component Tests
```typescript
import { render, screen, userEvent } from '@/test/utils';
import { Counter } from './Counter';

describe('Counter', () => {
  it('increments when clicked', async () => {
    const user = userEvent.setup();
    render(<Counter initialCount={0} />);
    
    await user.click(screen.getByRole('button'));
    
    expect(screen.getByText('Count: 1')).toBeInTheDocument();
  });
});
```

## Performance Guidelines
1. Use `React.memo` only when profiling shows benefit
2. Implement proper loading states with Suspense
3. Use `next/image` for all images
4. Lazy load heavy components with `next/dynamic`
5. Minimize client components — prefer Server Components
