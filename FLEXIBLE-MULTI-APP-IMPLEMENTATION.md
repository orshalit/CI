# Flexible Multi-Application Implementation

## Summary

We've implemented a flexible multi-application structure that supports:
- **Shared code**: Applications can use shared `backend/` and `frontend/` code
- **App-specific code**: Applications can have their own `applications/{app}/backend/` and `applications/{app}/frontend/`
- **Mixed approach**: Applications can mix shared and custom code (e.g., shared backend + custom frontend)
- **Automatic detection**: CI/CD automatically detects and builds the right images

## What Changed

### 1. Service Definitions Now Require `image_repo`

All service definitions must explicitly specify the Docker image repository:

```yaml
# applications/legacy/services/api.yaml
name: api
application: legacy
image_repo: ghcr.io/orshalit/ci-backend  # Shared image
```

```yaml
# applications/test-app/services/api.yaml  
name: api
application: test-app
image_repo: ghcr.io/orshalit/test-app-backend  # App-specific image (if backend/ exists)
```

### 2. New Detection Script

Created `scripts/detect-app-images.py` that:
- Scans `applications/` directory for app-specific code
- Generates build matrix for CI/CD
- Supports both shared and app-specific images

### 3. Updated CI Workflow

The CI workflow now:
- Detects which images need to be built dynamically
- Builds shared images (`ci-backend`, `ci-frontend`) from root directories
- Builds app-specific images (`{app}-backend`, `{app}-frontend`) when directories exist
- Uses a dynamic build matrix instead of hardcoded services

### 4. Updated Generation Script

The generation script:
- Requires `image_repo` field (no more defaults)
- Provides helpful error messages with suggestions
- Validates image repository format

## How It Works

### Shared Code (Current Setup)

```
CI/
├── backend/              # Shared backend code
├── frontend/             # Shared frontend code
└── applications/
    ├── legacy/
    │   └── services/
    │       ├── api.yaml      # image_repo: ghcr.io/orshalit/ci-backend
    │       └── frontend.yaml # image_repo: ghcr.io/orshalit/ci-frontend
    └── test-app/
        └── services/
            ├── api.yaml      # image_repo: ghcr.io/orshalit/ci-backend
            └── frontend.yaml # image_repo: ghcr.io/orshalit/ci-frontend
```

**Build Process:**
- CI builds: `ci-backend`, `ci-frontend` (shared)
- All applications use these shared images

### App-Specific Code

```
CI/
├── backend/              # Shared backend (still exists)
├── frontend/             # Shared frontend (still exists)
└── applications/
    └── test-app/
        ├── backend/      # Custom backend for test-app
        │   └── Dockerfile
        ├── frontend/     # Custom frontend for test-app
        │   └── Dockerfile
        └── services/
            ├── api.yaml      # image_repo: ghcr.io/orshalit/test-app-backend
            └── frontend.yaml # image_repo: ghcr.io/orshalit/test-app-frontend
```

**Build Process:**
- CI builds: `ci-backend`, `ci-frontend` (shared) + `test-app-backend`, `test-app-frontend` (app-specific)
- test-app uses its custom images, other apps use shared images

### Mixed Approach

```
CI/
├── backend/              # Shared backend
├── frontend/             # Shared frontend
└── applications/
    └── test-app/
        ├── frontend/     # Only custom frontend
        │   └── Dockerfile
        └── services/
            ├── api.yaml      # image_repo: ghcr.io/orshalit/ci-backend (shared)
            └── frontend.yaml # image_repo: ghcr.io/orshalit/test-app-frontend (custom)
```

**Build Process:**
- CI builds: `ci-backend`, `ci-frontend` (shared) + `test-app-frontend` (app-specific)
- test-app uses shared backend + custom frontend

## Image Naming Convention

### Shared Images
- Format: `ghcr.io/{owner}/ci-{service-type}`
- Examples:
  - `ghcr.io/orshalit/ci-backend`
  - `ghcr.io/orshalit/ci-frontend`

### App-Specific Images
- Format: `ghcr.io/{owner}/{app-name}-{service-type}`
- Examples:
  - `ghcr.io/orshalit/legacy-backend`
  - `ghcr.io/orshalit/test-app-frontend`

## Usage Examples

### Adding a New Application with Shared Code

1. Create service definitions:
```bash
mkdir -p applications/new-app/services
```

2. Create service YAML:
```yaml
# applications/new-app/services/api.yaml
name: api
application: new-app
image_repo: ghcr.io/orshalit/ci-backend  # Use shared backend
container_port: 8000
# ... rest of config
```

3. That's it! CI will automatically use shared images.

### Adding App-Specific Code

1. Create app-specific code directory:
```bash
mkdir -p applications/new-app/backend
# Copy or create backend code
cp -r backend/* applications/new-app/backend/
# Customize as needed
```

2. Create Dockerfile:
```dockerfile
# applications/new-app/backend/Dockerfile
FROM python:3.11-slim
# ... app-specific build steps
```

3. Update service definition:
```yaml
# applications/new-app/services/api.yaml
name: api
application: new-app
image_repo: ghcr.io/orshalit/new-app-backend  # Use app-specific image
# ... rest of config
```

4. CI will automatically detect and build `new-app-backend` image.

## Migration Guide

### From Current Setup (All Shared)

**Current state:** All apps use shared images
**Action:** No changes needed! Current setup already works.

### To App-Specific Code

1. Create app-specific directory:
   ```bash
   mkdir -p applications/{app}/backend
   ```

2. Copy or create code:
   ```bash
   cp -r backend/* applications/{app}/backend/
   # Customize as needed
   ```

3. Update service definition:
   ```yaml
   image_repo: ghcr.io/orshalit/{app}-backend
   ```

4. CI will automatically build the new image on next run.

### Back to Shared Code

1. Remove app-specific directory:
   ```bash
   rm -rf applications/{app}/backend
   ```

2. Update service definition:
   ```yaml
   image_repo: ghcr.io/orshalit/ci-backend
   ```

3. CI will stop building app-specific image automatically.

## Testing

### Test Detection Script

```bash
# See what images would be built
python scripts/detect-app-images.py

# Get GitHub Actions matrix format
python scripts/detect-app-images.py --format matrix

# List image names only
python scripts/detect-app-images.py --format list
```

### Test Service Generation

```bash
# Generate tfvars (will validate image_repo is present)
python scripts/generate_ecs_services_tfvars.py \
  --base-dir . \
  --devops-dir ../DEVOPS \
  --environment dev
```

## Benefits

1. **Flexibility**: Choose shared or app-specific code per application
2. **No Breaking Changes**: Existing shared setup continues to work
3. **Automatic Detection**: CI automatically builds what's needed
4. **Clear Organization**: Easy to see which apps use custom code
5. **Gradual Migration**: Move to app-specific code when needed, not all at once

## Next Steps

1. **Test the detection script** to ensure it works correctly
2. **Test CI workflow** to verify dynamic build matrix
3. **Create app-specific code** for test-app as an example
4. **Document** when to use shared vs app-specific code in team guidelines

