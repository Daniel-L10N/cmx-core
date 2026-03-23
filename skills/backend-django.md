# Backend Skills — Django / Django REST Framework

## Technology Stack
- **Framework**: Django 5+
- **API**: Django REST Framework (DRF)
- **Database**: PostgreSQL (preferred), SQLite (dev)
- **Authentication**: JWT (djangorestframework-simplejwt)
- **Testing**: pytest + pytest-django

## Django Conventions

### Project Structure
```
project/
├── config/              # Django settings
│   ├── __init__.py
│   ├── settings.py
│   ├── urls.py
│   └── wsgi.py
├── apps/                 # Django apps
│   └── users/
│       ├── __init__.py
│       ├── models.py
│       ├── serializers.py
│       ├── views.py
│       ├── urls.py
│       ├── admin.py
│       └── tests/
│           ├── __init__.py
│           └── test_views.py
├── conftest.py           # pytest fixtures
└── manage.py
```

### Models

```python
# apps/users/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    """Custom user model."""
    
    email = models.EmailField(unique=True)
    bio = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'users'
        verbose_name = 'user'
        verbose_name_plural = 'users'
    
    def __str__(self) -> str:
        return self.username


class Post(models.Model):
    """Example related model."""
    
    title = models.CharField(max_length=255)
    slug = models.SlugField(unique=True)
    content = models.TextField()
    author = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='posts'
    )
    published_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'posts'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['slug']),
            models.Index(fields=['-created_at']),
        ]
    
    def __str__(self) -> str:
        return self.title
```

### Serializers

```python
# apps/users/serializers.py
from rest_framework import serializers
from .models import User, Post


class UserSerializer(serializers.ModelSerializer):
    """Serializer for User model."""
    
    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'bio', 'created_at']
        read_only_fields = ['id', 'created_at']


class PostSerializer(serializers.ModelSerializer):
    """Serializer for Post model."""
    
    author = UserSerializer(read_only=True)
    author_id = serializers.PrimaryKeyRelatedField(
        queryset=User.objects.all(),
        source='author',
        write_only=True
    )
    
    class Meta:
        model = Post
        fields = [
            'id', 'title', 'slug', 'content',
            'author', 'author_id',
            'published_at', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'slug', 'created_at', 'updated_at']
    
    def create(self, validated_data: dict) -> Post:
        """Create post with current user as author."""
        validated_data['author'] = self.context['request'].user
        return super().create(validated_data)
```

### Views

```python
# apps/users/views.py
from rest_framework import viewsets, permissions, filters
from rest_framework.decorators import action
from django_filters.rest_framework import DjangoFilterBackend

from .models import User, Post
from .serializers import UserSerializer, PostSerializer


class IsOwnerOrReadOnly(permissions.BasePermission):
    """Object-level permission to only allow owners to edit."""
    
    def has_object_permission(self, request, view, obj) -> bool:
        if request.method in permissions.SAFE_METHODS:
            return True
        return obj.author == request.user


class UserViewSet(viewsets.ModelViewSet):
    """ViewSet for User model."""
    
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['username', 'email']
    ordering_fields = ['created_at', 'username']
    
    def get_permissions(self):
        if self.action == 'me':
            return [permissions.IsAuthenticated()]
        return super().get_permissions()
    
    @action(detail=False, methods=['get'])
    def me(self, request):
        """Get current user profile."""
        serializer = self.get_serializer(request.user)
        return Response(serializer.data)


class PostViewSet(viewsets.ModelViewSet):
    """ViewSet for Post model."""
    
    queryset = Post.objects.select_related('author').all()
    serializer_class = PostSerializer
    permission_classes = [permissions.IsAuthenticatedOrReadOnly, IsOwnerOrReadOnly]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    filterset_fields = ['author', 'published_at']
    search_fields = ['title', 'content']
    ordering_fields = ['created_at', 'published_at']
    lookup_field = 'slug'
```

### URLs

```python
# apps/users/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter

from .views import UserViewSet, PostViewSet

router = DefaultRouter()
router.register(r'users', UserViewSet)
router.register(r'posts', PostViewSet)

urlpatterns = [
    path('', include(router.urls)),
]
```

### Testing

```python
# apps/users/tests/test_views.py
import pytest
from rest_framework import status
from rest_framework.test import APIClient

from apps.users.models import User, Post


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def user(db):
    return User.objects.create_user(
        username='testuser',
        email='test@example.com',
        password='testpass123'
    )


@pytest.fixture
def post(db, user):
    return Post.objects.create(
        title='Test Post',
        slug='test-post',
        content='Test content',
        author=user
    )


@pytest.mark.django_db
class TestPostViewSet:
    """Tests for PostViewSet."""
    
    def test_list_posts(self, api_client, post):
        """Test listing posts."""
        response = api_client.get('/api/posts/')
        
        assert response.status_code == status.HTTP_200_OK
        assert len(response.data['results']) == 1
        assert response.data['results'][0]['title'] == 'Test Post'
    
    def test_create_post_authenticated(self, api_client, user):
        """Test creating a post when authenticated."""
        api_client.force_authenticate(user=user)
        data = {
            'title': 'New Post',
            'content': 'New content',
            'author_id': user.id
        }
        
        response = api_client.post('/api/posts/', data)
        
        assert response.status_code == status.HTTP_201_CREATED
        assert Post.objects.filter(title='New Post').exists()
    
    def test_create_post_unauthenticated(self, api_client):
        """Test creating a post when not authenticated."""
        data = {'title': 'New Post', 'content': 'Content'}
        
        response = api_client.post('/api/posts/', data)
        
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
```

## DRF Best Practices

1. **Use ViewSets** for CRUD operations
2. **Implement proper permissions** at object level
3. **Use select_related/prefetch_related** in querysets
4. **Validate with serializers**, not in views
5. **Use pagination** for list endpoints
6. **Document with drf-spectacular** for OpenAPI schema

## Security Checklist
- [ ] Use `django.contrib.auth.hashers` for passwords
- [ ] Validate all input with serializers
- [ ] Implement CORS properly (django-cors-headers)
- [ ] Use HTTPS in production
- [ ] Rate limit API endpoints
- [ ] Audit dependencies regularly
