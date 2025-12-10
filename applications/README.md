# Applications Directory

This directory contains service definitions organized by application. Each application has its own namespace and can be independently deployed.

## Directory Structure

```
applications/
├── legacy/              # Legacy application
│   ├── services/        # Infrastructure service definitions
│   │   ├── api.yaml
│   │   └── frontend.yaml
│   ├── backend/         # OPTIONAL: App-specific backend code
│   ├── frontend/        # OPTIONAL: App-specific frontend code
│   └── docker-compose.yml  # OPTIONAL: App-specific local dev setup
└── {app-name}/          # New applications
    └── services/
        └── {service}.yaml
```

## Application Code Organization

### Shared Code (Default)

By default, applications use shared code from the root `backend/` and `frontend/` directories:

```yaml
# applications/legacy/services/api.yaml
name: api
application: legacy
image_repo: ghcr.io/orshalit/ci-backend  # Shared backend image
```

**When to use:**
- Applications share most functionality
- Single team managing all applications
- Want to minimize code duplication

### Application-Specific Code

Applications can have their own code directories:

```
applications/
└── test-app/
    ├── backend/         # Custom backend for test-app
    │   ├── Dockerfile
    │   └── ...
    ├── frontend/        # Custom frontend for test-app
    │   ├── Dockerfile
    │   └── ...
    └── services/
        └── api.yaml     # References: ghcr.io/orshalit/test-app-backend
```

```yaml
# applications/test-app/services/api.yaml
name: api
application: test-app
image_repo: ghcr.io/orshalit/test-app-backend  # App-specific image
```

**When to use:**
- Application has unique requirements
- Different team owns the application
- Application may be extracted to separate repo later
- Significant code differences from shared codebase

### Mixed Approach

Applications can mix shared and custom code:

```yaml
# Shared backend, custom frontend
image_repo: ghcr.io/orshalit/ci-backend        # Shared
image_repo: ghcr.io/orshalit/test-app-frontend # Custom
```

## Service Definition Schema

Each service YAML file must include:

```yaml
name: {service-name}
application: {application-name}  # REQUIRED - must match directory name
image_repo: {image-repository}   # REQUIRED - Docker image repository

# Example: Shared image
image_repo: ghcr.io/orshalit/ci-backend

# Example: App-specific image
image_repo: ghcr.io/orshalit/legacy-backend

container_port: 8000
cpu: 256
memory: 512
desired_count: 2

env:
  LOG_LEVEL: INFO
  APPLICATION_NAME: legacy  # Optional: for runtime differentiation

alb:
  alb_id: app_shared
  listener_protocol: HTTPS
  listener_port: 443
  path_patterns:
    - "/legacy-api/*"
  health_check_path: "/health"
```

## Image Repository Naming

### Shared Images
- Format: `ghcr.io/{owner}/ci-{service-type}`
- Examples:
  - `ghcr.io/orshalit/ci-backend`
  - `ghcr.io/orshalit/ci-frontend`

### Application-Specific Images
- Format: `ghcr.io/{owner}/{app-name}-{service-type}`
- Examples:
  - `ghcr.io/orshalit/legacy-backend`
  - `ghcr.io/orshalit/test-app-frontend`

## Local Development

### Using Shared Code

```bash
# Use root docker-compose.yml
docker-compose up
```

### Using App-Specific Code

```bash
# Use app-specific docker-compose.yml
cd applications/test-app
docker-compose up
```

## CI/CD Build Process

The CI workflow automatically detects and builds:
1. **Shared images** (from `backend/` and `frontend/` at root)
2. **App-specific images** (from `applications/{app}/backend/` and `applications/{app}/frontend/`)

Images are built when:
- Code in the respective directory changes
- On version tags
- Manual workflow dispatch

## Best Practices

1. **Start with shared code** - Use shared images unless you have a specific need
2. **Explicit image_repo** - Always specify `image_repo` in service definitions
3. **Consistent naming** - Follow naming conventions for image repositories
4. **Document decisions** - Note why an application uses custom vs shared code
5. **Path patterns** - Use unique path patterns per application to avoid ALB conflicts

## Migration Path

### From Shared to App-Specific

1. Create `applications/{app}/backend/` or `applications/{app}/frontend/`
2. Copy or create app-specific code
3. Update service definition `image_repo` to app-specific image
4. CI will automatically build the new image

### From App-Specific to Shared

1. Move shared code to root `backend/` or `frontend/`
2. Update service definition `image_repo` to shared image
3. Remove app-specific code directory
4. CI will stop building app-specific image automatically

