# Edge Cases and Mitigations

## Overview

This document identifies edge cases that could cause deployment failures and provides mitigation strategies.

## 🔴 Critical Edge Cases

### 1. **State Locking Not Enabled** ⚠️ **HIGH PRIORITY**

**Issue:**
- Backend uses S3 but **no DynamoDB locking** is configured
- Concurrent deployments can corrupt state
- Two workflows running simultaneously can cause data loss

**Current State:**
```terraform
# DEVOPS/live/dev/04-ecs-fargate/backend.tf
backend "s3" {
  # No dynamodb_table configured
}
```

**Mitigation:**
1. ✅ **Immediate:** Add workflow-level concurrency control
2. 🔄 **Short-term:** Enable DynamoDB locking in backend
3. ✅ **Current:** Workflow uses `workflow_dispatch` (manual trigger reduces concurrency risk)

**Recommendation:**
```yaml
# Add to workflow
concurrency:
  group: deploy-${{ inputs.environment }}-${{ inputs.module_path }}
  cancel-in-progress: false  # Wait for current run to finish
```

### 2. **Plan File Staleness**

**Issue:**
- Plan is created, but state changes before apply
- Apply uses stale plan, causing conflicts
- State refresh happens before plan, but what if state changes between plan and apply?

**Current Protection:**
- ✅ State refresh before plan
- ✅ Plan file invalidated if state updated
- ❌ No check if state changed between plan and apply

**Mitigation:**
```yaml
# Add before apply
- name: Verify Plan is Still Valid
  run: |
    # Check if state has changed since plan was created
    # If changed, fail with clear message
```

### 3. **Service Discovery Namespace Replacement**

**Issue:**
- If namespace itself needs replacement, all services will fail
- Services depend on namespace ID
- Namespace replacement is rare but catastrophic

**Current Protection:**
- ✅ Namespace is a single resource (not in `for_each`)
- ❌ No validation if namespace is being replaced

**Mitigation:**
```yaml
# Add to pre-plan validation
- name: Check for Namespace Replacement
  run: |
    # If namespace is being replaced, warn and block
    # Namespace replacement requires manual intervention
```

## 🟡 Medium Priority Edge Cases

### 4. **ALB Listener Rule Priority Conflicts**

**Issue:**
- Priorities are auto-generated: `100 + index(keys(local.service_bindings), each.key)`
- If services are added/removed, priorities can shift
- If two rules have the same priority, apply will fail

**Current Protection:**
- ✅ Priority is auto-calculated based on service key order
- ❌ No validation for priority conflicts
- ❌ No check if priority already exists in AWS

**Mitigation:**
```yaml
# Add to idempotency check
- Check if listener rule priority conflicts with existing rules
- Warn if priorities will change due to service order changes
```

### 5. **Target Group Health Check Misconfiguration**

**Issue:**
- Health check path might not exist in application
- Health check port might be wrong
- Health check matcher might be incorrect

**Current Protection:**
- ✅ Post-apply verification script exists
- ❌ No pre-apply validation

**Mitigation:**
- Add pre-apply validation for health check paths
- Document expected health check endpoints

### 6. **ECS Service Desired Count Drift**

**Issue:**
- Someone manually scales service in AWS console
- Terraform will reset it back to desired count
- Could cause unexpected scaling events

**Current Protection:**
- ✅ Refresh step syncs state
- ❌ No warning if desired count differs significantly

**Mitigation:**
```yaml
# Add to pre-plan check
- Compare desired count in config vs AWS
- Warn if significant difference (e.g., 0 vs 2+)
```

### 7. **Task Definition Revision Accumulation**

**Issue:**
- Old task definition revisions accumulate
- AWS has a limit (default: keep last 10)
- Could cause issues if limit is reached

**Current Protection:**
- ✅ Task definitions use `skip_destroy = false` (default)
- ❌ No explicit cleanup of old revisions

**Mitigation:**
- Add lifecycle rule to skip destroy for old revisions
- Or add cleanup script to remove old revisions

### 8. **Route53 Record Conflicts**

**Issue:**
- If Route53 records are enabled, conflicts can occur
- Records might already exist from manual creation
- DNS propagation delays can cause issues

**Current Protection:**
- ✅ Route53 records are currently disabled (`route53_record_name = null`)
- ✅ Records are optional

**Mitigation:**
- When enabling Route53, add validation for existing records
- Check if record exists before creating

### 9. **ACM Certificate Expiration**

**Issue:**
- ACM certificate might expire
- HTTPS will fail if certificate is invalid
- No automatic renewal in current setup

**Current Protection:**
- ✅ Certificate is managed in separate module (00-dns-acm)
- ✅ Remote state is used to get certificate ARN
- ❌ No validation if certificate is expired or expiring soon

**Mitigation:**
```yaml
# Add to pre-apply validation
- Check certificate expiration date
- Warn if certificate expires within 30 days
```

### 10. **CloudWatch Log Group Retention Drift**

**Issue:**
- Log group retention might be changed manually
- Terraform will reset it back
- Could cause unexpected log retention changes

**Current Protection:**
- ✅ Refresh step syncs state
- ✅ Terraform enforces desired state

**Mitigation:**
- Current behavior is correct (Terraform enforces desired state)
- No additional protection needed

## 🟢 Low Priority Edge Cases

### 11. **IAM Role Policy Drift**

**Issue:**
- IAM policies might be modified outside Terraform
- Terraform will update them back
- Could cause temporary permission issues

**Current Protection:**
- ✅ Refresh step syncs state
- ✅ Terraform enforces desired state

**Mitigation:**
- Current behavior is correct
- Consider adding IAM policy validation if needed

### 12. **Tag Conflicts**

**Issue:**
- Tags might be modified manually
- Terraform will update them back
- Generally harmless

**Current Protection:**
- ✅ Refresh step syncs state
- ✅ Terraform enforces desired state

**Mitigation:**
- Current behavior is correct
- No additional protection needed

### 13. **Resource Naming Conflicts**

**Issue:**
- Resource names might conflict if services are renamed
- AWS has naming constraints
- Conflicts cause apply failures

**Current Protection:**
- ✅ Names are sanitized
- ✅ Names use unique service keys
- ❌ No validation for naming conflicts

**Mitigation:**
- Current naming scheme is robust
- Consider adding validation if issues arise

### 14. **Provider Version Mismatches**

**Issue:**
- Different provider versions might behave differently
- Could cause unexpected behavior
- Version pinning helps but doesn't prevent all issues

**Current Protection:**
- ✅ Terraform version is pinned (`1.6.0`)
- ❌ Provider versions not explicitly pinned

**Mitigation:**
- Add `required_providers` with version constraints
- Document expected provider versions

### 15. **VPC/Subnet Changes**

**Issue:**
- If VPC or subnets change, ECS services will fail
- Network infrastructure is managed separately
- Changes require coordination

**Current Protection:**
- ✅ VPC is managed in separate module (01-vpc)
- ✅ Remote state is used
- ❌ No validation if VPC/subnets changed

**Mitigation:**
- Add validation to check if VPC/subnets changed
- Warn if network infrastructure changed

## 📋 Implementation Status

### ✅ High Priority - COMPLETED
1. ✅ **Workflow concurrency control** - Prevents concurrent runs
2. ✅ **Plan staleness check** - Verifies plan is still valid before apply
3. ✅ **Namespace replacement check** - Blocks catastrophic namespace replacements

### ✅ Medium Priority - COMPLETED
4. ✅ **ALB listener rule priority conflict detection** - Detects conflicts before apply
5. ✅ **ECS service desired count drift warning** - Warns on significant drift
6. ✅ **Task definition revision accumulation check** - Monitors revision count
7. ✅ **Route53 record conflict detection** - Warns when records will be created
8. ⏸️ **ACM certificate expiration check** - Deferred (certificate ready to use)

### ✅ Low Priority - COMPLETED
9. ✅ **Resource naming conflict validation** - Detects duplicate sanitized names
10. ✅ **Provider version validation** - Checks Terraform version matches expected
11. ✅ **VPC/subnet change detection** - Warns about network infrastructure changes

### ⏸️ Deferred (As Requested)
- **DynamoDB state locking** - Will be added after core issues resolved
- **ACM certificate expiration** - Certificate ready to use, check not needed

## Implementation Priority

1. **Workflow Concurrency** - Prevents state corruption (Critical)
2. **Plan Staleness Check** - Prevents apply failures (High)
3. **Priority Conflict Detection** - Prevents ALB rule failures (Medium)
4. **Certificate Expiration Check** - Prevents HTTPS failures (Medium)
5. **Desired Count Drift Warning** - Improves visibility (Low)

## Testing Recommendations

1. **Test concurrent deployments:**
   - Run two workflows simultaneously
   - Verify state locking or concurrency control works

2. **Test plan staleness:**
   - Create plan, modify state manually, try to apply
   - Verify staleness check catches it

3. **Test priority conflicts:**
   - Create two services with same priority
   - Verify conflict detection works

4. **Test certificate expiration:**
   - Use a test certificate near expiration
   - Verify expiration check works

