# Target Group Health Check Path - Everlasting Fix

## Problem Summary

Target groups were experiencing state drift where:
- Terraform state thought health check paths were `/health`
- AWS actually had health check paths as `/`
- This caused tasks to fail health checks (404 errors)
- Terraform plan didn't detect the mismatch

## Root Cause

State drift occurred because:
1. Terraform state wasn't being refreshed before planning
2. No validation to detect state drift
3. No post-apply verification to ensure changes were applied correctly

## Everlasting Fix Implementation

### 1. **State Drift Detection Script** (`scripts/verify-target-group-health-checks.sh`)

This script:
- Compares Terraform state with actual AWS target groups
- Detects mismatches in health check paths
- Provides clear error messages and fix instructions
- Can be run manually or as part of CI/CD

**Usage:**
```bash
export TERRAFORM_DIR="DEVOPS/live/dev/04-ecs-fargate"
export ENVIRONMENT="dev"
./scripts/verify-target-group-health-checks.sh
```

### 2. **State Sync Script** (`scripts/sync-target-group-state.sh`)

This script:
- Forces Terraform state refresh
- Syncs state with AWS reality
- Can be used to fix state drift manually

**Usage:**
```bash
export TERRAFORM_DIR="DEVOPS/live/dev/04-ecs-fargate"
./scripts/sync-target-group-state.sh
```

### 3. **Enhanced Workflow Steps**

#### Pre-Plan State Refresh
- Always runs `terraform refresh` before planning
- Uses same var files as plan
- Provides clear output and error handling

#### State Drift Detection (Pre-Plan)
- Automatically detects state drift before planning
- Only runs for ECS Fargate module
- Non-blocking (continues even if drift detected)
- Provides warnings if drift is found

#### Post-Apply Verification
- Verifies target group health check paths after apply
- Ensures changes were applied correctly
- Detects any remaining state drift
- Provides clear success/failure messages

## How It Works

### Workflow Flow

1. **Terraform Refresh State**
   - Syncs Terraform state with AWS
   - Updates state to match actual resources

2. **Detect State Drift**
   - Compares Terraform state with AWS
   - Warns if mismatches are found
   - Provides fix instructions

3. **Terraform Plan**
   - Creates plan based on refreshed state
   - Should now detect health check path changes

4. **Terraform Apply**
   - Applies changes
   - Updates target groups

5. **Post-Apply Verification**
   - Verifies target groups match configuration
   - Detects any remaining drift
   - Provides success/failure feedback

## Benefits

1. **Prevents State Drift**
   - Always refreshes state before planning
   - Detects drift early

2. **Early Detection**
   - Catches issues before they cause problems
   - Provides clear warnings

3. **Post-Apply Verification**
   - Ensures changes were applied correctly
   - Detects any remaining issues

4. **Manual Tools**
   - Scripts can be run manually to fix issues
   - Useful for troubleshooting

5. **Non-Blocking**
   - Detection steps are non-blocking
   - Workflow continues even if drift detected
   - Provides warnings instead of failures

## Manual Fixes

If state drift is detected, you can fix it manually:

### Option 1: Use the sync script
```bash
cd DEVOPS/live/dev/04-ecs-fargate
export TERRAFORM_DIR=$(pwd)
./CI/scripts/sync-target-group-state.sh
```

### Option 2: Manual refresh
```bash
cd DEVOPS/live/dev/04-ecs-fargate
terraform refresh -var-file=terraform.tfvars -var-file=services.generated.tfvars
```

### Option 3: Force update via Terraform
```bash
cd DEVOPS/live/dev/04-ecs-fargate
terraform apply -var-file=terraform.tfvars -var-file=services.generated.tfvars
```

## Monitoring

The workflow will now:
- Show refresh step output
- Warn if state drift is detected
- Verify health check paths after apply
- Provide clear success/failure messages

## Future Prevention

This fix ensures:
1. State is always refreshed before planning
2. State drift is detected early
3. Changes are verified after apply
4. Manual tools are available for troubleshooting

The combination of automatic refresh, drift detection, and post-apply verification creates a robust system that prevents and detects state drift issues.

