# Phase 2 Implementation Plan: Infrastructure Updates

## Overview

Phase 2 updates the Terraform module to use the `application` field for resource naming and tagging, enabling proper multi-application support while maintaining backward compatibility.

## Goals

1. ✅ Update resource naming to include application: `{env}-{app}-{service}-{resource-type}`
2. ✅ Add `Application = {app}` tag to all resources
3. ✅ Update CloudWatch log group paths: `/ecs/{env}/{app}/{service}`
4. ✅ Ensure backward compatibility (defaults to "legacy" if not specified)
5. ✅ Update all references to maintain consistency

## Resources to Update

### 1. ECS Service
**Current:** `{env}-{service}-service`  
**New:** `{env}-{app}-{service}-service`

**Location:** `main.tf` line 527
**Tags:** Add `Application = each.value.application`

### 2. Task Definition
**Current:** `{env}-{service}` (family)  
**New:** `{env}-{app}-{service}` (family)

**Location:** `main.tf` line 454
**Tags:** Add `Application = each.value.application`

### 3. CloudWatch Log Group
**Current:** `/ecs/{env}/{service}`  
**New:** `/ecs/{env}/{app}/{service}`

**Location:** `main.tf` line 436
**Tags:** Add `Application = each.value.application`

### 4. Target Group
**Current:** `{env}-{service}-tg`  
**New:** `{env}-{app}-{service}-tg`

**Location:** `main.tf` line 278
**Note:** Uses `service_bindings`, need to get application from original service
**Tags:** Add `Application = var.services[each.value.service_name].application`

### 5. Autoscaling Policies
**Current:** `{env}-{service}-cpu`, `{env}-{service}-memory`  
**New:** `{env}-{app}-{service}-cpu`, `{env}-{app}-{service}-memory`

**Location:** `main.tf` lines 602, 626

### 6. Service Discovery
**Current:** Uses service name only  
**New:** Keep as-is (service discovery names are simple, no change needed)
**Tags:** Add `Application = each.value.application`

## Implementation Strategy

### Step 1: Create Helper Local for Application
Add a local value to safely get application with default:

```hcl
locals {
  # ... existing locals ...
  
  # Get application for each service, defaulting to "legacy" for backward compatibility
  service_applications = {
    for k, v in local.services :
    k => coalesce(v.application, "legacy")
  }
}
```

### Step 2: Update Resource Naming
Update all resource names to include application using the helper local.

### Step 3: Update Tags
Add `Application` tag to all resources using the helper local.

### Step 4: Update References
Ensure all references to resource names are updated (outputs, autoscaling, etc.).

## Backward Compatibility

- Application field defaults to "legacy" if not specified
- Existing resources will be replaced (this is expected for naming changes)
- All outputs will continue to work (they reference by key, not name)

## Testing Plan

1. ✅ Verify Terraform validates successfully
2. ✅ Verify plan shows expected name changes
3. ✅ Verify tags include Application field
4. ✅ Verify outputs still work correctly
5. ✅ Test with existing services (application: legacy)
6. ✅ Test with new application (if available)

## Files to Modify

1. `DEVOPS/modules/compute/ecs-fargate/main.tf` - Update all resource definitions
2. Verify outputs.tf doesn't need changes (should work as-is since outputs use keys)

## Rollback Plan

If issues arise:
1. Application field is optional with default - can revert to not using it
2. Can revert naming changes if needed
3. Tags are additive - removing Application tag is safe

