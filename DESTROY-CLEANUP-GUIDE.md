# Destroy Cleanup Guide

## Issue

The destroy operation partially succeeded but failed on IAM roles due to missing permissions. Some resources remain in AWS even though they've been removed from Terraform state.

## Remaining Resources

Based on the destroy logs and AWS checks:

1. **IAM Roles** (Failed to destroy):
   - `dev-ecs-task-execution-role`
   - `dev-ecs-task-role`

2. **IAM Policies** (May still exist):
   - `dev-ecs-task-execution-secrets-policy`

3. **ECS Cluster** (May still exist):
   - `dev-ecs-cluster`

## Root Cause

The destroy failed because the GitHub Actions IAM role was missing:
- `iam:ListInstanceProfilesForRole`
- `iam:ListInstanceProfiles`

These permissions are required by Terraform when destroying IAM roles to check for attached instance profiles.

## Solution

### Step 1: Update IAM Permissions (Already Fixed)

The fix has been committed to `DEVOPS/modules/backend/github-oidc/main.tf`. You need to apply it:

```bash
cd DEVOPS/live/dev/03-github-oidc
terraform apply
```

This updates the GitHub Actions IAM policy with the missing permissions.

### Step 2: Clean Up Remaining Resources

#### Option A: Re-import and Destroy (Recommended)

1. **Re-import remaining resources into state:**
   ```bash
   cd DEVOPS/live/dev/04-ecs-fargate
   
   # Import IAM roles
   terraform import module.ecs_fargate.aws_iam_role.ecs_task_execution_role dev-ecs-task-execution-role
   terraform import module.ecs_fargate.aws_iam_role.ecs_task_role dev-ecs-task-role
   
   # Import IAM policy (if it exists)
   terraform import module.ecs_fargate.aws_iam_policy.ecs_task_execution_secrets arn:aws:iam::ACCOUNT_ID:policy/dev-ecs-task-execution-secrets-policy
   
   # Import ECS cluster (if it exists)
   terraform import module.ecs_fargate.aws_ecs_cluster.this arn:aws:ecs:REGION:ACCOUNT_ID:cluster/dev-ecs-cluster
   ```

2. **Destroy again:**
   ```bash
   terraform destroy -auto-approve
   ```

#### Option B: Manual Cleanup via AWS CLI

If re-import is not feasible, manually delete the resources:

```bash
# Delete IAM roles (must detach policies first)
aws iam list-attached-role-policies --role-name dev-ecs-task-execution-role
aws iam detach-role-policy --role-name dev-ecs-task-execution-role --policy-arn <policy-arn>
aws iam delete-role --role-name dev-ecs-task-execution-role

aws iam list-attached-role-policies --role-name dev-ecs-task-role
aws iam detach-role-policy --role-name dev-ecs-task-role --policy-arn <policy-arn>
aws iam delete-role --role-name dev-ecs-task-role

# Delete IAM policy
aws iam delete-policy --policy-arn arn:aws:iam::ACCOUNT_ID:policy/dev-ecs-task-execution-secrets-policy

# Delete ECS cluster (if empty)
aws ecs delete-cluster --cluster dev-ecs-cluster
```

#### Option C: Use GitHub Actions Workflow (After Permissions Update)

1. Apply the IAM policy update (`03-github-oidc`)
2. Re-run the destroy workflow with the updated permissions
3. The destroy should now complete successfully

## Prevention

The IAM permissions have been added to prevent this issue in the future. The fix includes:
- `iam:ListInstanceProfilesForRole` - Required for role deletion
- `iam:ListInstanceProfiles` - Additional safety check

## Verification

After cleanup, verify all resources are gone:

```bash
# Check IAM roles
aws iam list-roles --query "Roles[?contains(RoleName, 'dev-ecs-task')].RoleName" --output text

# Check IAM policies
aws iam list-policies --scope Local --query "Policies[?contains(PolicyName, 'dev-ecs-task')].PolicyName" --output text

# Check ECS cluster
aws ecs describe-clusters --clusters dev-ecs-cluster --query 'clusters[0].clusterName' --output text

# Check Terraform state
cd DEVOPS/live/dev/04-ecs-fargate
terraform state list
```

All should return empty or "not found" if cleanup is complete.

