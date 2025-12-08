# Services Migration Analysis: Old State vs New Config

## The Scenario

**Question:** When we generate `services.generated.tfvars` from YAML, what happens if:
- **State has:** Old services (e.g., `api`, `frontend`, `api_single`)
- **New config has:** New services (e.g., `legacy::api`, `legacy::frontend`, `test-app::test-app-api`)

## What Terraform Will Do

### Scenario 1: Service Name Changed (Old → New Format)

**Old State:**
```
aws_ecs_service.services["api"]
aws_ecs_service.services["frontend"]
```

**New Config:**
```
services = {
  "legacy::api" = {...}
  "legacy::frontend" = {...}
}
```

**Terraform Plan Result:**
```
Plan: 2 to add, 0 to change, 2 to destroy

+ aws_ecs_service.services["legacy::api"]     # CREATE
+ aws_ecs_service.services["legacy::frontend"] # CREATE
- aws_ecs_service.services["api"]              # DESTROY
- aws_ecs_service.services["frontend"]        # DESTROY
```

**⚠️ This will DESTROY old services and CREATE new ones!**

**Impact:**
- **Downtime:** Services will be destroyed before new ones are created
- **Data loss:** Any service-specific data (logs, metrics) will be lost
- **DNS/ALB:** May have brief interruption

### Scenario 2: Service Removed from YAML

**Old State:**
```
aws_ecs_service.services["api"]
aws_ecs_service.services["api_single"]  # This service was removed
aws_ecs_service.services["frontend"]
```

**New Config (YAML no longer has `api_single`):**
```
services = {
  "legacy::api" = {...}
  "legacy::frontend" = {...}
  # api_single is missing
}
```

**Terraform Plan Result:**
```
Plan: 2 to add, 0 to change, 3 to destroy

+ aws_ecs_service.services["legacy::api"]     # CREATE
+ aws_ecs_service.services["legacy::frontend"] # CREATE
- aws_ecs_service.services["api"]              # DESTROY
- aws_ecs_service.services["api_single"]      # DESTROY (removed from YAML)
- aws_ecs_service.services["frontend"]        # DESTROY
```

**⚠️ Services removed from YAML will be DESTROYED!**

### Scenario 3: Service Added (New Service)

**Old State:**
```
aws_ecs_service.services["legacy::api"]
aws_ecs_service.services["legacy::frontend"]
```

**New Config:**
```
services = {
  "legacy::api" = {...}
  "legacy::frontend" = {...}
  "test-app::test-app-api" = {...}  # NEW
}
```

**Terraform Plan Result:**
```
Plan: 1 to add, 0 to change, 0 to destroy

+ aws_ecs_service.services["test-app::test-app-api"] # CREATE
```

**✅ Safe - only creates new service**

### Scenario 4: Service Updated (Same Key, Different Config)

**Old State:**
```
aws_ecs_service.services["legacy::api"]  # cpu: 256, memory: 512
```

**New Config:**
```
services = {
  "legacy::api" = {
    cpu: 512      # Changed
    memory: 1024  # Changed
    ...
  }
}
```

**Terraform Plan Result:**
```
Plan: 0 to add, 1 to change, 0 to destroy

~ aws_ecs_service.services["legacy::api"]  # UPDATE (may require replacement)
```

**⚠️ May cause service replacement if immutable attributes changed**

## The Key Issue: Service Key Mismatch

**Problem:** Old services use simple keys (`api`, `frontend`), new services use composite keys (`legacy::api`, `legacy::frontend`).

**Terraform sees these as DIFFERENT services:**
- `services["api"]` ≠ `services["legacy::api"]`
- Old service will be destroyed
- New service will be created

## Solutions

### Option 1: State Migration (Recommended for Production)

**Manually update Terraform state to use new keys:**

```bash
# Move old service to new key
terraform state mv \
  'aws_ecs_service.services["api"]' \
  'aws_ecs_service.services["legacy::api"]'

terraform state mv \
  'aws_ecs_service.services["frontend"]' \
  'aws_ecs_service.services["legacy::frontend"]'
```

**Pros:**
- No downtime
- Preserves service history
- No data loss

**Cons:**
- Manual step
- Must be done before deployment
- Requires careful execution

### Option 2: Accept Replacement (For Dev/Test)

**Let Terraform destroy and recreate:**

**Pros:**
- Simple
- Clean state
- No manual steps

**Cons:**
- Downtime
- Data loss
- Service interruption

### Option 3: Gradual Migration

**Add new services alongside old ones, then remove old ones:**

1. Generate config with BOTH old and new keys
2. Deploy (creates new services)
3. Verify new services work
4. Remove old services from YAML
5. Regenerate and deploy (destroys old services)

**Pros:**
- Zero downtime
- Can test new services first
- Rollback possible

**Cons:**
- Temporary duplicate services
- More complex

## Recommended Approach

### For Fresh Deployments (No Existing Services)
✅ **Just generate and deploy** - No issues

### For Existing Deployments (Services in State)

**Step 1: Check Current State**
```bash
terraform state list | grep aws_ecs_service.services
```

**Step 2: Generate services.generated.tfvars**
- Run "Create / Update ECS Service" workflow
- Review the generated file

**Step 3: Compare State vs Config**
- Check if service keys match
- Identify services that will be destroyed/created

**Step 4: Choose Migration Strategy**
- **Production:** Use state migration (Option 1)
- **Dev/Test:** Accept replacement (Option 2)
- **Zero-downtime:** Use gradual migration (Option 3)

**Step 5: Deploy**
- Run "Deploy Infrastructure" workflow
- Review plan carefully
- Apply if plan looks correct

## Detection in Workflow

The workflow should:
1. ✅ Detect empty services (already done)
2. ⚠️ **TODO:** Show plan preview before apply
3. ⚠️ **TODO:** Warn about service key changes
4. ⚠️ **TODO:** List services that will be destroyed/created

