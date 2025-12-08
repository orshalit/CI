# Image Handling Analysis - Complete Flow Verification

## Image Flow Diagram

```
Service YAML                    Generation Script              Terraform
─────────────────              ───────────────────            ──────────
image_repo:                    container_image =              image =
ghcr.io/.../ci-backend    →    "ghcr.io/.../ci-backend"  →   "${container_image}:${image_tag}"
                                                              "ghcr.io/.../ci-backend:v1.2.3"
```

## Step-by-Step Verification

### Step 1: Service Definition (YAML)

**Location**: `applications/{app}/services/{service}.yaml`

**Example - Legacy (Shared Image):**
```yaml
name: api
application: legacy
image_repo: ghcr.io/orshalit/ci-backend  # ✅ Shared backend
```

**Example - Test-App (App-Specific Image):**
```yaml
name: api
application: test-app
image_repo: ghcr.io/orshalit/test-app-backend  # ✅ App-specific backend
```

**Status**: ✅ Correct - Each service explicitly specifies its image repository

### Step 2: Generation Script

**Script**: `generate_ecs_services_tfvars.py`

**Process**:
1. Reads `image_repo` from YAML
2. Converts to `container_image` in tfvars
3. Sets default `image_tag = "latest"` (overridden at deploy time)

**Generated Output**:
```hcl
services = {
  api = {
    container_image = "ghcr.io/orshalit/ci-backend"  # From image_repo
    image_tag       = "latest"  # Default, overridden by service_image_tags
    application     = "legacy"
    # ...
  }
}
```

**Status**: ✅ Correct - `image_repo` → `container_image` conversion works

### Step 3: Deployment Workflow

**Workflow**: `app-deploy-ecs.yml`

**Process**:
1. Filters services by application name
2. Generates `service_image_tags` override file
3. Applies same tag to all filtered services

**Example - Deploying "legacy":**
```hcl
service_image_tags = {
  api = "v1.2.3"      # Legacy API service
  frontend = "v1.2.3"  # Legacy frontend service
}
```

**Example - Deploying "test-app":**
```hcl
service_image_tags = {
  api = "v1.2.3"      # Test-app API service
  frontend = "v1.2.3" # Test-app frontend service
}
```

**Example - Deploying "all":**
```hcl
service_image_tags = {
  api = "v1.2.3"           # Legacy API (uses ci-backend)
  frontend = "v1.2.3"       # Legacy frontend (uses ci-frontend)
  api = "v1.2.3"           # ⚠️ WAIT - This is a problem!
}
```

**⚠️ ISSUE FOUND**: When deploying "all", if multiple applications have services with the same name (e.g., both have "api"), the `service_image_tags` map will have duplicate keys, and only the last one will be used!

**Status**: ⚠️ **NEEDS FIX** - Service name collision when deploying "all"

### Step 4: Terraform Image Resolution

**Location**: `DEVOPS/modules/compute/ecs-fargate/main.tf`

**Process**:
```hcl
locals {
  services = {
    for k, v in var.services :
    k => merge(v, {
      image_tag = lookup(var.service_image_tags, k, v.image_tag)
    })
  }
}

# Later in task definition:
image = "${each.value.container_image}:${each.value.image_tag}"
```

**Example**:
- Service: `api` (legacy)
- `container_image`: `ghcr.io/orshalit/ci-backend`
- `image_tag`: `v1.2.3` (from service_image_tags)
- **Final image**: `ghcr.io/orshalit/ci-backend:v1.2.3` ✅

**Status**: ✅ Correct - Terraform correctly combines image + tag

## Issues Found

### Issue 1: Service Name Collision ⚠️ CRITICAL

**Problem**: When deploying "all", if multiple applications have services with the same name, the `service_image_tags` map will overwrite values.

**Example**:
```hcl
# Both legacy and test-app have "api" service
service_image_tags = {
  api = "v1.2.3"  # Which one? Last one wins!
}
```

**Impact**: 
- One application's services won't get the correct tag
- Deployment may use wrong image tag

**Solution Needed**: 
- Use service key format: `{app}::{service}` or similar
- OR: Ensure service names are unique across applications
- OR: Generate separate tag files per application

### Issue 2: Image Existence Validation ❌ MISSING

**Problem**: No validation that Docker images exist before deployment.

**Impact**:
- Deployment fails at ECS task start (not at plan time)
- Harder to debug
- Wastes time on failed deployments

**Solution Needed**: 
- Add pre-deployment check to verify images exist in registry
- Fail fast with clear error message

### Issue 3: Mixed Image Repositories ⚠️ POTENTIAL ISSUE

**Scenario**: Deploying "all" when:
- Legacy uses: `ci-backend:v1.2.3` (shared)
- Test-app uses: `test-app-backend:v1.2.3` (app-specific)

**Question**: Are both images built with the same tag?

**Current Behavior**:
- CI builds all images with same version tag ✅
- Deployment applies same tag to all services ✅
- **IF** both images exist with that tag, it works ✅
- **IF** one image doesn't exist, deployment fails ❌

**Status**: ⚠️ Works IF all required images are built, but no validation

## Verification Results

### ✅ What Works Correctly

1. **Service Definition → tfvars**: `image_repo` correctly converted to `container_image`
2. **Image Repository Selection**: Services correctly specify shared vs app-specific images
3. **Tag Application**: Terraform correctly applies tags to images
4. **Single Application Deployment**: Works correctly when deploying one application

### ⚠️ What Needs Attention

1. **Service Name Collision**: When deploying "all", duplicate service names cause tag overwrites
2. **Image Existence**: No validation that required images exist
3. **Error Messages**: Could be clearer when image doesn't exist

## Recommendations

### High Priority

1. **Fix Service Name Collision**
   - Option A: Use composite keys in service_image_tags: `{app}::{service}`
   - Option B: Ensure service names are unique (add app prefix: `legacy-api`, `test-app-api`)
   - Option C: Deploy applications separately (don't use "all")

2. **Add Image Existence Validation**
   - Check Docker registry before deployment
   - List required images and verify they exist
   - Fail fast with clear error

### Medium Priority

3. **Improve Error Messages**
   - Show which image is missing
   - Suggest which images need to be built
   - Provide links to build workflows

### Low Priority

4. **Add Image Tag Validation**
   - Verify tag format
   - Check tag exists in registry
   - Warn about using "latest"

