# Docker Versioning and Build System

This document describes the production-grade versioning and build system for Docker images in this project.

## Overview

The project uses a comprehensive versioning system that:
- ✅ Captures Git metadata (commit SHA, branch, tags)
- ✅ Embeds build information in Docker images
- ✅ Provides version endpoints for runtime querying
- ✅ Follows OCI (Open Container Initiative) standards
- ✅ Supports semantic versioning
- ✅ Enables image traceability

## Build Metadata

Each Docker image contains the following metadata:

| Metadata | Description | Example |
|----------|-------------|---------|
| `BUILD_VERSION` | Semantic version or git-based version | `v1.2.3` or `main-abc1234` |
| `GIT_COMMIT` | Short Git commit SHA | `abc1234` |
| `GIT_BRANCH` | Git branch name | `main`, `develop`, `feature/xyz` |
| `BUILD_DATE` | ISO 8601 timestamp | `2024-01-15T10:30:00Z` |
| `PYTHON_VERSION` | Python runtime version (backend) | `3.11` |
| `NODE_VERSION` | Node.js build version (frontend) | `20` |

## Building Images

### Using the Build Script (Recommended)

The `scripts/build.sh` script automates the build process with proper versioning:

```bash
# Basic build (auto-detects version from git)
./scripts/build.sh

# Build with specific version
./scripts/build.sh --version v1.2.3

# Build and push to registry
./scripts/build.sh --version v1.2.3 --registry ghcr.io/username --push

# Build backend only
./scripts/build.sh --backend-only

# Build with custom tag
./scripts/build.sh --version v1.2.3 --tag production

# Build without cache
./scripts/build.sh --no-cache
```

### Using Docker Compose

Set environment variables and build:

```bash
export BUILD_VERSION=v1.2.3
export GIT_COMMIT=$(git rev-parse --short HEAD)
export GIT_BRANCH=$(git branch --show-current)
export BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

docker-compose build
```

### Manual Docker Build

Build with explicit build arguments:

```bash
docker build \
  --build-arg BUILD_VERSION=v1.2.3 \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  --build-arg GIT_BRANCH=$(git branch --show-current) \
  -t myapp-backend:v1.2.3 \
  -f backend/Dockerfile \
  backend/
```

## Version Naming Strategy

The build script automatically determines version names:

| Scenario | Version Format | Example |
|----------|---------------|---------|
| Git tag exists | `{tag}` | `v1.2.3` |
| Main/master branch | `main-{commit}` | `main-abc1234` |
| Other branch | `dev-{commit}` | `dev-abc1234` |
| Uncommitted changes | `{version}-dirty` | `v1.2.3-dirty` |
| Manual override | `{specified}` | `rc1.0.0` |

## Image Labels (OCI Standard)

All images include standardized OCI labels:

```dockerfile
# View labels on a built image
docker inspect ci-backend:latest --format='{{json .Config.Labels}}' | jq '.'
```

Standard labels:
- `org.opencontainers.image.created` - Build timestamp
- `org.opencontainers.image.version` - Application version
- `org.opencontainers.image.revision` - Git commit SHA
- `org.opencontainers.image.source` - Repository URL
- `org.opencontainers.image.title` - Image title
- `org.opencontainers.image.description` - Image description

Custom labels:
- `app.version` - Application version
- `app.git.commit` - Git commit SHA
- `app.git.branch` - Git branch
- `app.build.date` - Build timestamp

## Runtime Version Querying

### Backend API

Query version information via the `/version` endpoint:

```bash
# Get version from running container
curl http://localhost:8000/version

# Response:
{
  "version": "v1.2.3",
  "commit": "abc1234",
  "build_date": "2024-01-15T10:30:00Z",
  "python_version": "3.11",
  "environment": "production"
}
```

### Frontend

Version information is available at `/version.json`:

```bash
# Get frontend version
curl http://localhost:3000/version.json

# Response:
{
  "version": "v1.2.3",
  "commit": "abc1234",
  "build_date": "2024-01-15T10:30:00Z",
  "node_version": "20"
}
```

Build info text file:

```bash
curl http://localhost:3000/build-info.txt
```

### From Docker Images

```bash
# Backend version file
docker run --rm ci-backend:latest cat /app/version.json

# Frontend version file
docker run --rm ci-frontend:latest cat /usr/share/nginx/html/version.json

# Image labels
docker inspect ci-backend:latest \
  --format='Version: {{index .Config.Labels "app.version"}}
Commit: {{index .Config.Labels "app.git.commit"}}
Built: {{index .Config.Labels "app.build.date"}}'
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Push

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Full history for git describe
      
      - name: Build images
        run: |
          ./scripts/build.sh \
            --registry ghcr.io/${{ github.repository_owner }} \
            --push
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Semantic Versioning

For proper semantic versioning, tag your releases:

```bash
# Create a new version tag
git tag -a v1.2.3 -m "Release version 1.2.3"
git push origin v1.2.3

# Build script will automatically use this version
./scripts/build.sh
```

## Image Tagging Strategy

The build process creates multiple tags:

```bash
# Example for version v1.2.3:
myapp-backend:latest       # Always points to latest build
myapp-backend:v1.2.3       # Specific version
myapp-backend:v1.2         # Minor version (optional)
myapp-backend:v1           # Major version (optional)
```

## Production Deployment

### Version Pinning

Always pin specific versions in production:

```yaml
# docker-compose.prod.yml
services:
  backend:
    image: myapp-backend:v1.2.3  # Pin exact version
    # NOT: image: myapp-backend:latest
```

### Rollback

Easy rollback with version tags:

```bash
# Rollback to previous version
docker-compose -f docker-compose.prod.yml pull backend:v1.2.2
docker-compose -f docker-compose.prod.yml up -d backend
```

## Troubleshooting

### Missing Version Information

If version endpoints return "unknown":
1. Ensure build arguments were passed correctly
2. Check if version.json exists in the image
3. Verify environment variables are set

### Verify Build Metadata

```bash
# Check if version.json exists
docker run --rm ci-backend:latest ls -l /app/version.json

# Read version file
docker run --rm ci-backend:latest cat /app/version.json

# Check environment variables
docker run --rm ci-backend:latest env | grep -E '(APP_VERSION|GIT_COMMIT|BUILD_DATE)'
```

## Best Practices

1. **Always use the build script** for consistent versioning
2. **Tag releases** with semantic versions (v1.2.3)
3. **Pin versions** in production deployments
4. **Document version changes** in CHANGELOG.md
5. **Automate builds** in CI/CD pipelines
6. **Monitor version drift** between environments
7. **Keep build metadata** for audit trails

## Environment Variables

Key environment variables used by the versioning system:

| Variable | Description | Default |
|----------|-------------|---------|
| `BUILD_VERSION` | Application version | `dev` |
| `GIT_COMMIT` | Git commit SHA | `unknown` |
| `GIT_BRANCH` | Git branch name | `unknown` |
| `BUILD_DATE` | Build timestamp | Current time |
| `APP_VERSION` | Runtime version (from build args) | From image |

## Resources

- [OCI Image Spec](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
- [Semantic Versioning](https://semver.org/)
- [Docker Build Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Multi-stage Builds](https://docs.docker.com/build/building/multi-stage/)

