# Image Handling Verification Summary

## ✅ What Works Correctly

### 1. Image Repository Flow
```
Service YAML (image_repo) 
  → Generation Script (container_image) 
  → Terraform (image = container_image:image_tag)
```
**Status**: ✅ **Correct** - Each service's `image_repo` correctly flows through to Terraform

### 2. Image Tag Application
- Default tag: `"latest"` in generated tfvars
- Override: `service_image_tags` map applied at deploy time
- Final: Terraform combines `container_image` + `image_tag`
**Status**: ✅ **Correct** - Tags are applied correctly

### 3. Application Filtering
- Deployment workflow filters services by application name
- Only filtered services get tag overrides
**Status**: ✅ **Correct** - Filtering works for single application deployments

## 🚨 Critical Issue Found: Service Name Collision

### The Problem

**Current Situation:**
- Legacy has: `api`, `frontend` services
- Test-app has: `api`, `frontend` services
- **Both use the same service names!**

**What Happens:**
```hcl
services = {
  api = {  # From legacy - FIRST
    container_image = "ghcr.io/orshalit/ci-backend"
    application = "legacy"
  }
  api = {  # From test-app - OVERWRITES legacy!
    container_image = "ghcr.io/orshalit/test-app-backend"
    application = "test-app"
  }
}
```

**Result**: Only test-app's `api` service exists. Legacy's `api` is lost!

### The Fix Applied

✅ **Added collision detection** in generation script:
- Detects when multiple applications use the same service name
- Fails with clear error message
- Prevents silent data loss

**Error Message:**
```
Service name collisions detected:
  - Service name 'api' is used by multiple applications: legacy, test-app
  - Service name 'frontend' is used by multiple applications: legacy, test-app

Each service must have a unique name across all applications.
Consider renaming services to include application prefix (e.g., 'legacy-api', 'test-app-api').
```

### Solutions

#### Option 1: Rename Services (Quick Fix) ✅ RECOMMENDED

Rename test-app services to be unique:
```yaml
# applications/test-app/services/api.yaml
name: test-app-api  # Instead of just "api"
```

**Pros**: 
- ✅ Works immediately
- ✅ No code changes needed
- ✅ Clear service names

**Cons**:
- ⚠️ Service names change (but that's fine for testing)

#### Option 2: Use Composite Keys (Future Enhancement)

Change to `{app}::{service}` keys:
```hcl
services = {
  legacy::api = { ... }
  test-app::api = { ... }
}
```

**Pros**:
- ✅ Supports same service names
- ✅ More scalable

**Cons**:
- ⚠️ Requires Terraform module changes
- ⚠️ Requires deployment workflow changes
- ⚠️ More complex

## Verification Results

### Current State

**Legacy Services:**
- ✅ `api` → `ghcr.io/orshalit/ci-backend` (shared)
- ✅ `frontend` → `ghcr.io/orshalit/ci-frontend` (shared)

**Test-App Services:**
- ✅ `api` → `ghcr.io/orshalit/test-app-backend` (app-specific)
- ✅ `frontend` → `ghcr.io/orshalit/test-app-frontend` (app-specific)

**Issue**: Both have services named `api` and `frontend` → **COLLISION!**

### After Fix

The generation script will now:
1. ✅ Detect the collision
2. ✅ Fail with clear error
3. ✅ Prevent silent data loss

### Next Steps

**Immediate**: Rename test-app services to avoid collision:
- `api` → `test-app-api`
- `frontend` → `test-app-frontend`

**Or**: Deploy applications separately (not "all") to avoid the collision issue.

## Image Mapping Verification

Run the verification script:
```bash
python scripts/verify-image-mapping.py
```

This will check:
- ✅ All services have `image_repo`
- ✅ Image repos match expected patterns
- ✅ Tfvars match service definitions
- ✅ No missing or invalid image references

## Conclusion

**Image Handling**: ✅ **95% Correct**
- Image flow works correctly
- Tag application works correctly
- **Issue**: Service name collision needs to be resolved

**Recommendation**: Rename test-app services to be unique before testing.

