# Image Handling Verification

## Image Flow Analysis

### 1. Service Definition (YAML) → Terraform Variables

**Service YAML:**
```yaml
# applications/legacy/services/api.yaml
name: api
application: legacy
image_repo: ghcr.io/orshalit/ci-backend  # Shared image
```

**Generated tfvars:**
```hcl
services = {
  api = {
    container_image = "ghcr.io/orshalit/ci-backend"  # From image_repo
    image_tag       = "latest"  # Default, overridden at deploy time
    # ...
  }
}
```

**Status**: ✅ Correct - `image_repo` → `container_image` conversion works

### 2. Image Tag Override (Deployment Time)

**Deployment Workflow:**
1. Filters services by application
2. Generates `service_image_tags` override file:
```hcl
service_image_tags = {
  api = "v1.2.3"  # Tag from CI build
}
```

**Terraform Logic:**
```hcl
locals {
  services = {
    for k, v in var.services :
    k => merge(v, {
      image_tag = lookup(var.service_image_tags, k, v.image_tag)
    })
  }
}
```

**Final Image:**
```hcl
image = "${container_image}:${image_tag}"
# Example: "ghcr.io/orshalit/ci-backend:v1.2.3"
```

**Status**: ✅ Correct - Tag override mechanism works

## Potential Issues to Check

### Issue 1: Application Filtering vs Image Selection

**Scenario**: Deploying "legacy" application
- Legacy uses: `ghcr.io/orshalit/ci-backend` (shared)
- Test-app uses: `ghcr.io/orshalit/test-app-backend` (app-specific)

**Question**: Does filtering by application correctly identify which services need which images?

**Current Flow:**
1. Filter services by application name
2. Apply same image tag to all filtered services

**Potential Problem**: 
- If deploying "legacy", it correctly filters to legacy services
- But what if we deploy "all"? Does it apply the same tag to both shared and app-specific images?

**Verification Needed**: Check if deployment workflow handles mixed image repositories correctly.

### Issue 2: Image Tag Consistency

**Scenario**: 
- Legacy API uses `ci-backend:latest`
- Test-app API uses `test-app-backend:latest`

**Question**: When deploying "all", do both get the same tag or different tags?

**Current Behavior**:
- CI builds all images with same version tag
- Deployment applies same tag to all services
- ✅ This is correct IF all images are built with same version

**Potential Problem**:
- If `test-app-backend` image doesn't exist with that tag, deployment fails
- Need to ensure all required images are built before deployment

### Issue 3: Image Repository Validation

**Question**: Does the system validate that the image repository exists before deployment?

**Current Status**: ❌ No validation - Terraform will fail at runtime if image doesn't exist

**Recommendation**: Add pre-deployment validation to check image existence

## Verification Checklist

- [ ] Service definitions have correct `image_repo` for their application type
- [ ] Generation script correctly converts `image_repo` → `container_image`
- [ ] Deployment workflow filters services correctly by application
- [ ] Image tags are applied correctly to filtered services
- [ ] Terraform correctly combines `container_image` + `image_tag`
- [ ] Mixed deployments (shared + app-specific) work correctly
- [ ] Error handling when image doesn't exist

