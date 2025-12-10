# State Drift Prevention

## Overview

This document explains how state drift is prevented in the CI/CD workflow to ensure Terraform state stays in sync with actual AWS resources.

## Problem

During development, state drift can occur when:
- AWS resources are modified outside of Terraform
- Manual changes are made to resources
- Other processes modify resources
- State file becomes out of sync with reality

This causes Terraform to think resources need to be created/replaced when they already exist, leading to errors like "Service already exists".

## Solution

The workflow now **always refreshes state before plan/apply** to sync with AWS resources.

### Key Changes

1. **Pre-Plan State Refresh**
   - Runs `terraform apply -refresh-only` before every plan/apply
   - Updates state to match actual AWS resources
   - Does NOT make any changes to AWS resources
   - Only updates the Terraform state file

2. **Refresh Step Location**
   - Runs AFTER import step (if needed)
   - Runs BEFORE plan step
   - Ensures state is synced before planning

3. **Refresh-Only Mode**
   - Uses `terraform apply -refresh-only -auto-approve`
   - Updates state without making changes
   - Shows what resources were updated
   - Safe to run repeatedly

## Workflow Flow

```
1. Import Existing Services (if needed)
   ↓
2. Refresh State (sync with AWS) ← NEW: Always runs
   ↓
3. Plan (with synced state)
   ↓
4. Apply (if plan succeeds)
```

## Benefits

- ✅ Prevents "Resource already exists" errors
- ✅ State always matches AWS reality
- ✅ More accurate plans
- ✅ Fewer surprises during apply
- ✅ Better for development workflows

## When Refresh Runs

- ✅ Before every plan
- ✅ Before every apply
- ✅ When services exist in state
- ✅ When services don't exist in state
- ❌ Only skipped if no state file exists (fresh deployment)

## Example Output

```
🔄 Refreshing Terraform state to sync with AWS (preventing state drift)...
✓ State refreshed - updated to match AWS resources
Resources updated in state:
  module.ecs_fargate.aws_service_discovery_service.services["legacy::api"]
  module.ecs_fargate.aws_lb_target_group.services["app_shared::legacy::api"]
```

## Manual Refresh

If you need to refresh state manually:

```bash
cd DEVOPS/live/dev/04-ecs-fargate
terraform apply -refresh-only -auto-approve
```

This updates state without making any changes to AWS resources.

## Troubleshooting

### State Still Out of Sync

If refresh doesn't fix the issue:
1. Check if resources exist in AWS but not in state → Use import step
2. Check if resources exist in state but not in AWS → Remove from state
3. Check for configuration mismatches → Review plan output

### Refresh Takes Too Long

- Refresh has a 5-minute timeout
- If it times out, it continues with plan (non-blocking)
- Large infrastructures may need longer timeouts

### Refresh Fails

- Refresh failures are non-blocking (continue-on-error: true)
- Workflow continues with plan
- Check refresh output for details

