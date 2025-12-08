# Multi-Application Code Organization Plan

## Current State

```
CI/
├── backend/              # Single backend codebase
├── frontend/             # Single frontend codebase
├── docker-compose.yml    # Single compose file
├── docker-compose.prod.yml
└── applications/
    ├── legacy/
    │   └── services/     # Infrastructure definitions
    └── test-app/
        └── services/     # Infrastructure definitions
```

**Current Docker Images:**
- `ghcr.io/owner/ci-backend:tag`
- `ghcr.io/owner/ci-frontend:tag`

**Current Build Process:**
- CI workflow builds both images on every change
- Images are tagged with version
- ECS services reference these images

## Options for Multi-Application Organization

### Option A: Application-Specific Code Directories (Full Isolation)

**Structure:**
```
CI/
├── applications/
│   ├── legacy/
│   │   ├── backend/          # Legacy-specific backend
│   │   ├── frontend/          # Legacy-specific frontend
│   │   ├── docker-compose.yml # Legacy local dev
│   │   └── services/         # Infrastructure
│   └── test-app/
│       ├── backend/          # Test-app-specific backend
│       ├── frontend/         # Test-app-specific frontend
│       ├── docker-compose.yml
│       └── services/         # Infrastructure
├── shared/                    # Shared libraries/utilities (optional)
│   ├── common/
│   └── libs/
└── docker-compose.yml         # Root-level for all apps (optional)
```

**Docker Images:**
- `ghcr.io/owner/legacy-backend:tag`
- `ghcr.io/owner/legacy-frontend:tag`
- `ghcr.io/owner/test-app-backend:tag`
- `ghcr.io/owner/test-app-frontend:tag`

**Pros:**
- ✅ Complete isolation between applications
- ✅ Independent versioning and deployment
- ✅ Clear ownership and boundaries
- ✅ Easy to extract applications later
- ✅ Different tech stacks per application possible

**Cons:**
- ❌ Code duplication if apps are similar
- ❌ More complex CI/CD (build per application)
- ❌ Shared changes require updates in multiple places
- ❌ Larger repository size

**Best For:**
- Applications with different requirements
- Different teams owning different applications
- Applications that may be split into separate repos later

---

### Option B: Shared Codebase with Application Configuration (Recommended for Similar Apps)

**Structure:**
```
CI/
├── backend/                  # Shared backend codebase
│   ├── apps/                # Application-specific modules
│   │   ├── legacy/
│   │   │   ├── routes.py
│   │   │   ├── config.py
│   │   │   └── models.py
│   │   └── test_app/
│   │       ├── routes.py
│   │       ├── config.py
│   │       └── models.py
│   ├── shared/              # Shared utilities
│   └── main.py             # Entry point (routes to app modules)
├── frontend/                # Shared frontend codebase
│   ├── apps/                # Application-specific modules
│   │   ├── legacy/
│   │   │   ├── pages/
│   │   │   ├── components/
│   │   │   └── config.js
│   │   └── testApp/
│   │       ├── pages/
│   │       ├── components/
│   │       └── config.js
│   └── shared/              # Shared components
├── applications/
│   ├── legacy/
│   │   ├── docker-compose.yml
│   │   ├── .env.example
│   │   └── services/
│   └── test-app/
│       ├── docker-compose.yml
│       ├── .env.example
│       └── services/
└── docker-compose.yml       # Root-level for all apps
```

**Docker Images:**
- `ghcr.io/owner/ci-backend:tag` (same image, different config)
- `ghcr.io/owner/ci-frontend:tag` (same image, different config)

**Build Process:**
- Build once, deploy with different environment variables
- Application determined by `APPLICATION_NAME` env var
- Routes/features enabled based on configuration

**Pros:**
- ✅ Single codebase to maintain
- ✅ Shared code changes benefit all applications
- ✅ Simpler CI/CD (build once)
- ✅ Consistent behavior across applications
- ✅ Easier to share utilities and components

**Cons:**
- ❌ Tight coupling between applications
- ❌ Harder to have completely different features
- ❌ Configuration complexity
- ❌ All apps deploy together (unless filtered)

**Best For:**
- Applications with similar functionality
- Single team managing all applications
- Applications that share most code/logic

---

### Option C: Hybrid Approach (Shared Base + App Extensions)

**Structure:**
```
CI/
├── backend/
│   ├── core/                # Shared core functionality
│   │   ├── database.py
│   │   ├── auth.py
│   │   └── middleware.py
│   ├── apps/                # Application-specific code
│   │   ├── legacy/
│   │   │   ├── routes.py
│   │   │   └── business_logic.py
│   │   └── test_app/
│   │       ├── routes.py
│   │       └── business_logic.py
│   └── main.py
├── frontend/
│   ├── core/                # Shared core (UI components, utils)
│   ├── apps/                # Application-specific
│   └── shared/
├── applications/
│   ├── legacy/
│   │   ├── Dockerfile.backend    # Extends base, adds app code
│   │   ├── Dockerfile.frontend
│   │   ├── docker-compose.yml
│   │   └── services/
│   └── test-app/
│       ├── Dockerfile.backend
│       ├── Dockerfile.frontend
│       ├── docker-compose.yml
│       └── services/
└── docker-compose.yml
```

**Docker Images:**
- Base images: `ghcr.io/owner/backend-base:tag`, `ghcr.io/owner/frontend-base:tag`
- Application images: `ghcr.io/owner/legacy-backend:tag`, `ghcr.io/owner/test-app-backend:tag`

**Build Process:**
1. Build base images (shared code)
2. Build application images (extend base, add app-specific code)
3. Deploy application-specific images

**Pros:**
- ✅ Balance between shared code and isolation
- ✅ Applications can extend/customize as needed
- ✅ Shared utilities and core functionality
- ✅ Independent deployment per application

**Cons:**
- ❌ More complex build process
- ❌ Multi-stage Dockerfiles
- ❌ Need to manage base image versions

**Best For:**
- Applications with shared core but different features
- Gradual migration from shared to isolated
- Teams that want flexibility

---

### Option D: Keep Current Structure (Simplest - Recommended for Now)

**Structure:**
```
CI/
├── backend/                # Shared backend (current)
├── frontend/               # Shared frontend (current)
├── docker-compose.yml      # Current (works for all apps)
├── docker-compose.prod.yml
└── applications/
    ├── legacy/
    │   └── services/       # Infrastructure only
    └── test-app/
        └── services/       # Infrastructure only
```

**Docker Images:**
- `ghcr.io/owner/ci-backend:tag` (shared)
- `ghcr.io/owner/ci-frontend:tag` (shared)

**How It Works:**
- Same codebase serves all applications
- Application differentiation via:
  - Environment variables (`APPLICATION_NAME`, `APP_CONFIG`)
  - Different API routes/paths (`/legacy-api/*`, `/test-api/*`)
  - Different frontend builds (if needed) via build args
  - Service discovery names

**Pros:**
- ✅ No migration needed (current structure works)
- ✅ Simplest to maintain
- ✅ Single build process
- ✅ All applications benefit from improvements
- ✅ Infrastructure already supports it

**Cons:**
- ❌ All applications must be compatible
- ❌ Can't have completely different features easily
- ❌ Deploying one app deploys the same code to all

**Best For:**
- **Current situation** - applications are similar
- Single team
- Want to keep things simple
- Applications share most functionality

---

## Recommendation

### Phase 1: Keep Current Structure (Option D) ✅

**Why:**
1. Your infrastructure already supports multiple applications
2. Current code structure works for shared applications
3. No migration needed - just use environment variables to differentiate
4. Simplest path forward

**What to Do:**
1. **Keep `backend/` and `frontend/` at root** - they serve all applications
2. **Use environment variables** to differentiate applications:
   ```yaml
   # applications/legacy/services/api.yaml
   env:
     APPLICATION_NAME: legacy
     APP_CONFIG_PATH: /legacy-api
   ```
3. **Update docker-compose files** to support application selection:
   ```yaml
   # docker-compose.yml
   services:
     backend:
       environment:
         APPLICATION_NAME: ${APPLICATION_NAME:-legacy}
   ```
4. **CI/CD already works** - builds once, deploys to multiple services
5. **Service definitions** already reference the same images with different configs

### Phase 2: Add Application-Specific Configuration (If Needed)

If applications need different behavior:
1. Add application-specific config files:
   ```
   applications/
   ├── legacy/
   │   ├── config/
   │   │   ├── backend.env
   │   │   └── frontend.env
   │   └── services/
   ```
2. Load config based on `APPLICATION_NAME` env var
3. Use feature flags or routing to enable/disable features

### Phase 3: Migrate to Option A or C (If Needed Later)

Only if:
- Applications diverge significantly
- Different teams need ownership
- Different tech requirements emerge

---

## Implementation Plan for Option D (Recommended)

### 1. Update Service Definitions

Add application-specific environment variables:

```yaml
# applications/legacy/services/api.yaml
env:
  APPLICATION_NAME: legacy
  API_PREFIX: /legacy-api
  # ... other app-specific vars
```

### 2. Update Docker Compose for Local Development

```yaml
# docker-compose.yml
services:
  backend:
    environment:
      APPLICATION_NAME: ${APPLICATION_NAME:-legacy}
      # ... other vars
```

Create application-specific compose overrides:
```yaml
# applications/legacy/docker-compose.override.yml
services:
  backend:
    environment:
      APPLICATION_NAME: legacy
      API_PREFIX: /legacy-api
```

### 3. Update Backend Code (If Needed)

```python
# backend/main.py
import os

APPLICATION_NAME = os.getenv("APPLICATION_NAME", "legacy")
API_PREFIX = os.getenv("API_PREFIX", "/api")

# Route based on application
if APPLICATION_NAME == "legacy":
    app.include_router(legacy_routes, prefix=f"{API_PREFIX}")
elif APPLICATION_NAME == "test-app":
    app.include_router(test_app_routes, prefix=f"{API_PREFIX}")
```

### 4. Update CI/CD (Minimal Changes)

The current CI/CD already works! Just ensure:
- Build process creates images: `ci-backend`, `ci-frontend`
- Service definitions reference these images
- Environment variables differentiate applications

### 5. Documentation

Update docs to explain:
- How applications share codebase
- How to add application-specific features
- How local development works per application

---

## Decision Matrix

| Factor | Option A | Option B | Option C | Option D (Current) |
|--------|----------|----------|----------|-------------------|
| **Complexity** | High | Medium | Medium-High | Low |
| **Code Duplication** | High | Low | Medium | Low |
| **Isolation** | High | Low | Medium | Low |
| **Maintenance** | Hard | Easy | Medium | Easy |
| **Migration Effort** | High | Medium | High | None |
| **Best For** | Different apps | Similar apps | Hybrid needs | Current situation |

---

## Next Steps

1. **Decide on approach** (recommend Option D for now)
2. **Update service definitions** with application-specific env vars
3. **Update docker-compose** for local dev per application
4. **Update backend/frontend** to handle multiple applications (if needed)
5. **Test with legacy and test-app**
6. **Document the approach**

Would you like me to implement Option D (keep current structure) or do you prefer a different approach?

