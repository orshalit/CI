# Critical Image Handling Issues Found

## 🚨 CRITICAL: Service Name Collision

### Problem

When multiple applications have services with the same name, they collide in the generated tfvars:

**Current Behavior:**
```hcl
services = {
  api = {  # From legacy
    container_image = "ghcr.io/orshalit/ci-backend"
    application = "legacy"
  }
  api = {  # From test-app - OVERWRITES legacy!
    container_image = "ghcr.io/orshalit/test-app-backend"
    application = "test-app"
  }
}
```

**Result**: Only the last service definition is kept. Legacy's "api" service is lost!

### Impact

1. **Service Loss**: Services from earlier applications are overwritten
2. **Wrong Images**: Services may get wrong image repositories
3. **Deployment Failures**: Missing services won't deploy
4. **Silent Failures**: No error - just missing services

### Root Cause

The generation script uses service `name` as the key:
```python
lines.append(f"  {name} = {{")  # Uses just 'name', not '{app}::{name}'
```

### Solution Options

#### Option A: Use Composite Keys (Recommended)
Change service keys to `{app}::{service}`:
```hcl
services = {
  legacy::api = {
    container_image = "ghcr.io/orshalit/ci-backend"
    application = "legacy"
  }
  test-app::api = {
    container_image = "ghcr.io/orshalit/test-app-backend"
    application = "test-app"
  }
}
```

**Pros**: 
- ✅ No collisions
- ✅ Clear which app each service belongs to
- ✅ Supports same service names across apps

**Cons**:
- ⚠️ Requires Terraform module changes
- ⚠️ Requires deployment workflow changes

#### Option B: Enforce Unique Service Names
Require service names to be unique across all applications:
- `legacy-api`, `test-app-api` instead of just `api`

**Pros**:
- ✅ Minimal code changes
- ✅ Works with current Terraform structure

**Cons**:
- ❌ Less flexible
- ❌ Requires renaming existing services
- ❌ Doesn't scale well

#### Option C: Separate Service Maps Per Application
Generate separate service maps:
```hcl
services_legacy = { ... }
services_test_app = { ... }
```

**Pros**:
- ✅ Complete isolation

**Cons**:
- ❌ Major Terraform refactoring
- ❌ Complex deployment logic

## 🔍 Verification Needed

### Check 1: Current tfvars Generation

Run generation and check for duplicate keys:
```bash
python scripts/generate_ecs_services_tfvars.py \
  --base-dir . \
  --devops-dir ../DEVOPS \
  --environment dev
```

Then check if both `legacy` and `test-app` services appear in tfvars.

### Check 2: Service Name Uniqueness

Verify if current services have unique names:
- Legacy: `api`, `frontend`
- Test-app: `api`, `frontend` ← **COLLISION!**

### Check 3: Deployment Workflow

Check if deployment workflow handles collisions:
- Does it filter correctly?
- Does it apply tags to the right services?

## Immediate Action Required

**Before deploying test-app**, we need to fix the service name collision issue.

**Recommended Fix**: Use composite keys (`{app}::{service}`)

This requires:
1. Update generation script to use composite keys
2. Update Terraform module to handle composite keys
3. Update deployment workflow to use composite keys
4. Update all references to service keys

