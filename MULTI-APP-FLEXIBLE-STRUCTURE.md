# Flexible Multi-Application Structure

## Vision

Support multiple applications where:
- Some applications share code (use shared images)
- Some applications have their own code (use app-specific images)
- Applications can mix: shared backend + custom frontend, or vice versa
- Clear organization and easy to understand

## Proposed Structure

```
CI/
├── backend/                    # Shared backend (default)
│   └── ...
├── frontend/                   # Shared frontend (default)
│   └── ...
├── applications/
│   ├── legacy/
│   │   ├── services/          # Infrastructure definitions
│   │   │   ├── api.yaml       # Uses: image_repo: ghcr.io/owner/ci-backend (shared)
│   │   │   └── frontend.yaml   # Uses: image_repo: ghcr.io/owner/ci-frontend (shared)
│   │   ├── backend/            # OPTIONAL: App-specific backend (if needed)
│   │   ├── frontend/           # OPTIONAL: App-specific frontend (if needed)
│   │   └── docker-compose.yml  # OPTIONAL: App-specific local dev
│   └── test-app/
│       ├── services/
│       │   ├── api.yaml         # Uses: image_repo: ghcr.io/owner/test-app-backend (custom)
│       │   └── frontend.yaml   # Uses: image_repo: ghcr.io/owner/ci-frontend (shared)
│       ├── backend/             # Custom backend for test-app
│       └── docker-compose.yml
└── docker-compose.yml          # Root-level for shared apps
```

## Key Changes

### 1. Service Definitions Support Custom Image Repos

```yaml
# applications/legacy/services/api.yaml
name: api
application: legacy
image_repo: ghcr.io/orshalit/ci-backend  # Shared image
# OR
image_repo: ghcr.io/orshalit/legacy-backend  # App-specific image
```

### 2. Build Process Detects App-Specific Code

- If `applications/{app}/backend/` exists → build app-specific backend image
- If `applications/{app}/frontend/` exists → build app-specific frontend image
- Otherwise → use shared images from root `backend/` and `frontend/`

### 3. Image Naming Convention

- **Shared images**: `ghcr.io/owner/ci-backend`, `ghcr.io/owner/ci-frontend`
- **App-specific images**: `ghcr.io/owner/{app-name}-backend`, `ghcr.io/owner/{app-name}-frontend`

### 4. CI/CD Build Matrix

Build all images (shared + app-specific) based on what exists:
- Always build: `ci-backend`, `ci-frontend` (shared)
- Conditionally build: `{app}-backend`, `{app}-frontend` (if directories exist)

## Implementation Plan

### Phase 1: Update Service Definition Schema
- Add validation for `image_repo` field
- Support both shared and app-specific image repos
- Default to shared images if not specified

### Phase 2: Update Build Process
- Detect application-specific code directories
- Build app-specific images when directories exist
- Update CI workflow to handle dynamic build matrix

### Phase 3: Update Generation Script
- Ensure `image_repo` is properly passed through to Terraform
- Validate image repo naming conventions

### Phase 4: Documentation
- Document when to use shared vs app-specific code
- Examples for both patterns

