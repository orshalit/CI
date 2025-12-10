# Downtime Analysis: New Import/Refresh Behaviors

## Summary

**Good News:** The new import/refresh logic **reduces downtime** by preventing unnecessary replacements. However, there is **one potential downtime scenario** that needs attention.

## New Behaviors

### 1. **Enhanced Import Script** ✅ **REDUCES DOWNTIME**
- **What it does:** Detects when Service Discovery services in state don't match AWS and automatically syncs them
- **Impact:** Prevents unnecessary replacements that would cause downtime
- **Downtime Risk:** **NONE** - This only updates Terraform state, doesn't affect running services

### 2. **State Refresh After Import** ✅ **REDUCES DOWNTIME**
- **What it does:** Refreshes Terraform state to sync configuration attributes (like `health_check_custom_config`)
- **Impact:** Ensures Terraform sees the actual AWS configuration, avoiding replacements when AWS already matches desired state
- **Downtime Risk:** **NONE** - This only updates Terraform state, doesn't affect running services

### 3. **Idempotency Check Fix** ✅ **REDUCES DOWNTIME**
- **What it does:** Properly detects conflicts before apply, blocking deployments that would fail
- **Impact:** Prevents failed deployments that could leave services in inconsistent states
- **Downtime Risk:** **NONE** - This only blocks bad deployments, doesn't affect running services

## Potential Downtime Scenarios

### ⚠️ **Scenario 1: Service Discovery Service Replacement** (Medium Risk)

**When it happens:**
- When `health_check_custom_config {}` is added and AWS service doesn't have it
- Terraform must replace the Service Discovery service
- Service Discovery has `create_before_destroy = false` (must destroy old before creating new)

**What happens:**
1. Terraform destroys old Service Discovery service
2. ECS service's `service_registries { registry_arn = ... }` becomes invalid
3. Terraform creates new Service Discovery service
4. ECS service updates to reference new Service Discovery ARN

**Downtime Impact:**
- **ECS Tasks:** ✅ **NO DOWNTIME** - Tasks continue running
- **Service-to-Service Communication:** ⚠️ **BRIEF INTERRUPTION** - Service Discovery DNS resolution may fail during the gap between destroy and create
- **ALB Traffic:** ✅ **NO DOWNTIME** - ALB routes directly to tasks, not via Service Discovery

**Duration:** Typically 10-30 seconds (time to destroy old service + create new service)

**Mitigation:**
- The new import/refresh logic **reduces** this scenario by syncing state before plan
- If AWS service already has `health_check_custom_config`, no replacement needed
- If replacement is still required, it's a one-time event per service

### ✅ **Scenario 2: New Service Launch** (No Risk)

**When it happens:**
- New application/service is added to configuration
- New Service Discovery service is created
- New ECS service is created

**Downtime Impact:**
- **Existing Services:** ✅ **NO DOWNTIME** - Completely independent
- **New Service:** N/A - Service is being created, not updated

### ✅ **Scenario 3: Configuration Updates to Existing Services** (Low Risk)

**When it happens:**
- Task definition changes (image tag, environment variables, etc.)
- Target group changes (health check paths, etc.)
- ECS service desired count changes

**Downtime Impact:**
- **ECS Rolling Deployment:** ✅ **ZERO DOWNTIME** - ECS performs rolling update:
  - New tasks are started and registered with ALB
  - Health checks pass on new tasks
  - Old tasks drain connections and deregister
  - Old tasks are stopped only after new ones are healthy
- **Service Discovery:** ✅ **NO DOWNTIME** - Only ECS tasks are updated, Service Discovery service unchanged

**Configuration:**
- `deployment_minimum_healthy_percent = 100` ensures old tasks stay running until new ones are healthy
- `deployment_maximum_percent = 200` allows new tasks to start before old ones stop
- `create_before_destroy = true` on ECS services ensures graceful replacement

## Recommendations

### 1. **Monitor Service Discovery Replacements**
- The import script now detects and prevents most unnecessary replacements
- If replacement is still required, it's a one-time event
- Consider adding monitoring/alerts for Service Discovery service replacements

### 2. **Consider Making `health_check_custom_config` Conditional**
If `health_check_custom_config {}` is always empty, consider making it conditional to avoid forcing replacements:

```terraform
dynamic "health_check_custom_config" {
  for_each = var.enable_service_discovery_health_check ? [1] : []
  content {
    # No failure threshold needed for MULTIVALUE routing
  }
}
```

### 3. **Test Service Discovery Replacement in Staging First**
- Test the replacement scenario in a staging environment
- Verify that service-to-service communication recovers quickly
- Measure actual downtime duration

## Conclusion

**Overall Downtime Risk: LOW**

- ✅ New import/refresh logic **reduces** downtime by preventing unnecessary replacements
- ✅ ECS rolling deployments are **zero-downtime** by design
- ⚠️ Service Discovery replacements may cause **brief** (10-30s) interruption to service-to-service communication
- ✅ ALB traffic is **unaffected** (routes directly to tasks)
- ✅ New service launches are **independent** and don't affect existing services

The new behaviors are **net positive** - they prevent more downtime than they could potentially cause.

