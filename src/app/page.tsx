'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuthStore } from '@/stores/authStore';
import { ProtectedRoute, LoadingSpinner, UserDisplay, LogoutButton } from '@/components/auth';
import { Navbar } from '@/components/layout/Navbar';
import { Card } from '@/components/ui/Card';

function DashboardContent() {
  const { user, logout, isLoading } = useAuthStore();
  const router = useRouter();

  const handleLogout = async () => {
    await logout();
    router.push('/login');
  };

  return (
    <div className="min-h-screen bg-gray-50">
      <Navbar />
      
      <main className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <div className="px-4 py-6 sm:px-0">
          <h1 className="text-3xl font-bold text-gray-900 mb-8">Dashboard</h1>
          
          <div className="grid grid-cols-1 gap-6 md:grid-cols-2 lg:grid-cols-3">
            <Card className="col-span-full">
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="text-lg font-semibold text-gray-900">Welcome!</h2>
                  {user && (
                    <p className="mt-1 text-gray-600">
                      Logged in as <UserDisplay email={user.email} />
                    </p>
                  )}
                  <p className="mt-2 text-sm text-gray-500">
                    Member since: {user?.createdAt ? new Date(user.createdAt).toLocaleDateString() : '-'}
                  </p>
                </div>
                <LogoutButton onClick={handleLogout} isLoading={isLoading} />
              </div>
            </Card>
            
            <Card>
              <h3 className="text-lg font-semibold text-gray-900 mb-4">Quick Stats</h3>
              <div className="space-y-2">
                <div className="flex justify-between">
                  <span className="text-gray-600">Status</span>
                  <span className="font-medium text-green-600">Active</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-600">Account Type</span>
                  <span className="font-medium">Standard</span>
                </div>
              </div>
            </Card>
            
            <Card>
              <h3 className="text-lg font-semibold text-gray-900 mb-4">Activity</h3>
              <p className="text-gray-500 text-sm">No recent activity</p>
            </Card>
          </div>
        </div>
      </main>
    </div>
  );
}

function DashboardLoading() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <LoadingSpinner size="lg" text="Loading dashboard..." />
    </div>
  );
}

export default function DashboardPage() {
  const { checkAuth, isLoading } = useAuthStore();
  const router = useRouter();

  useEffect(() => {
    checkAuth();
  }, [checkAuth]);

  useEffect(() => {
    if (!isLoading) {
      const timer = setTimeout(() => {
        router.refresh();
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [isLoading, router]);

  if (isLoading) {
    return <DashboardLoading />;
  }

  return (
    <ProtectedRoute fallback={<DashboardLoading />}>
      <DashboardContent />
    </ProtectedRoute>
  );
}
