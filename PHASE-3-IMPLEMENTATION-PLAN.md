# Phase 3 Implementation Plan: Deployment Workflow Updates

## Overview

Phase 3 updates the deployment workflow to support application-level filtering, allowing deployments of specific applications or all applications.

## Goals

1. ✅ Add `application` parameter to `app-deploy-ecs.yml` workflow
2. ✅ Filter services by application during deployment
3. ✅ Support "all" option to deploy all applications (backward compatible)
4. ✅ Update service_image_tags generation to only include services from selected application
5. ✅ Ensure no dead code - all paths are used

## Changes Required

### 1. Workflow Input Updates

**Current:**
```yaml
workflow_dispatch:
  inputs:
    environment: ...
    image_tag: ...
    skip_verification: ...
```

**New:**
```yaml
workflow_dispatch:
  inputs:
    application:
      description: 'Application to deploy (or "all" for all applications)'
      required: true
      default: 'all'
      type: choice
      options: [all, legacy]  # Will expand as new apps are added
    environment: ...
    image_tag: ...
    skip_verification: ...
```

### 2. Service Filtering Logic

**Current:**
- Hardcodes service names: `api_single`, `api`, `frontend`
- Generates tags for all services

**New:**
- Read services from `services.generated.tfvars` or Terraform state
- Filter by application
- Generate tags only for filtered services

### 3. Service Image Tags Generation

**Current:**
```bash
service_image_tags = {
  api_single = "..."
  api        = "..."
  frontend   = "..."
}
```

**New:**
- Read services from Terraform
- Filter by application
- Generate tags dynamically

### 4. Path Filtering (for workflow_run trigger)

**Current:**
- Checks for `backend/**` and `frontend/**` changes

**New:**
- Optionally filter by application directory changes
- Or keep as-is (deploy all when code changes)

## Implementation Strategy

### Step 1: Add Application Input

Add application parameter to workflow inputs with:
- Default: "all" (backward compatible)
- Options: "all", "legacy" (expandable)
- Type: choice

### Step 2: Create Service Filtering Step

Create a step that:
1. Reads services from Terraform state or tfvars
2. Filters by application if not "all"
3. Outputs list of service names for that application

### Step 3: Update Service Tags Generation

Update the `Generate service image tag overrides` step to:
1. Use filtered service list
2. Generate tags only for services in selected application
3. Handle "all" case (include all services)

### Step 4: Update Path Filtering (Optional)

For workflow_run trigger:
- Keep current behavior (deploy all when backend/frontend changes)
- Or add application-specific path filtering

## Backward Compatibility

- Default to "all" - existing behavior maintained
- "all" option deploys all services (current behavior)
- No breaking changes to existing workflows

## Testing Plan

1. ✅ Test with application="all" (should work as before)
2. ✅ Test with application="legacy" (should only deploy legacy services)
3. ✅ Test with workflow_run trigger (should still work)
4. ✅ Verify service_image_tags only includes selected application
5. ✅ Verify Terraform plan only includes selected application services

## Files to Modify

1. `CI/.github/workflows/app-deploy-ecs.yml` - Add application input and filtering
2. Potentially create a composite action for service filtering (optional)

## Rollback Plan

If issues arise:
1. Can revert to hardcoded service names
2. Can remove application parameter (defaults to "all")
3. Application filtering is additive - can be disabled

