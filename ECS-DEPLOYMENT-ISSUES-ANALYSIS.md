# ECS Deployment Issues Analysis

## Current Issues Identified

### 1. Target Groups Not Associated with Load Balancers
**Symptom:** Target groups show "None associated" in AWS Console

**Root Cause Analysis:**
- Target groups ARE created by Terraform
- Listener rules ARE created that forward to target groups
- However, target groups may appear unassociated if:
  - No healthy targets are registered (tasks aren't running)
  - Listener rules failed to create
  - Tasks are failing health checks

**Status:** This is likely a symptom, not the root cause. Target groups are associated via listener rules, but they appear unassociated because there are no healthy targets.

### 2. ECS Service Deployment Failures
**Symptom:** 
- `dev-api-service`: Failed deployment, 0/2 tasks running
- `dev-api_single-service`: Failed deployment, 0/1 tasks running  
- `dev-frontend-service`: Completed, 2/2 tasks running

**Potential Root Causes:**
1. **Container Image Issues:**
   - Image doesn't exist in GHCR
   - Image pull authentication failures
   - Wrong image tag used

2. **Container Startup Failures:**
   - Application crashes on startup
   - Missing environment variables
   - Database connection failures
   - Health check endpoint not responding

3. **Network/Security Issues:**
   - Security group misconfiguration
   - Subnet routing issues
   - NAT Gateway connectivity problems

4. **Resource Constraints:**
   - Insufficient CPU/memory
   - Task definition misconfiguration

### 3. HTTPS/HTTP Listener Mismatch
**Symptom:** Services configured for HTTPS but ALBs only have HTTP listeners

**Current Configuration:**
- `terraform.tfvars`: `enable_https = false` for both ALBs
- `services.generated.tfvars`: Services use `listener_protocol = "HTTPS"` and `listener_port = 443`

**Terraform Logic:**
The listener rule creation (line 290-291 in `main.tf`) should fall back to HTTP listener when HTTPS doesn't exist:
```hcl
listener_arn = (
  each.value.config.listener_protocol == "HTTPS" && contains(keys(aws_lb_listener.https), each.value.alb_id)
) ? aws_lb_listener.https[each.value.alb_id].arn : aws_lb_listener.http[each.value.alb_id].arn
```

**Status:** This should work correctly, but it's a configuration inconsistency that could cause confusion.

## Diagnostic Enhancements Added

### 1. Enhanced ECS Service Diagnostics
Added a new step `Diagnose ECS Services Before Verification` that:
- Checks service status (desired/running/pending counts)
- Shows recent service events
- Lists stopped tasks with stop codes and reasons
- Checks target group health status
- Identifies unhealthy targets

### 2. Enhanced CloudWatch Log Verification
Enhanced the log verification step to:
- Check for error messages in logs
- Display recent log entries
- Show timestamps in human-readable format
- Identify patterns (errors, exceptions, fatal, failed, panic)

## Recommended Fixes

### Immediate Actions

1. **Run the Enhanced Diagnostics**
   - The next deployment will automatically run comprehensive diagnostics
   - Review the output to identify the specific failure reason

2. **Check Stopped Tasks**
   ```bash
   aws ecs describe-services \
     --cluster dev-ecs-cluster \
     --services dev-api-service dev-api_single-service \
     --region us-east-1 \
     --query 'services[*].events[:5]' \
     --output json
   ```

3. **Check CloudWatch Logs**
   ```bash
   aws logs tail /ecs/dev/api --follow --region us-east-1
   aws logs tail /ecs/dev/api_single --follow --region us-east-1
   ```

### Configuration Fixes

1. **Fix Service Configuration Mismatch**
   - Option A: Update `services.generated.tfvars` to use HTTP when HTTPS is disabled
   - Option B: Enable HTTPS in `terraform.tfvars` and provide ACM certificates
   - **Recommendation:** Use Option A for dev environment

2. **Verify Image Tags**
   - Ensure the image tags used in deployment actually exist in GHCR
   - Check if images are public or require authentication
   - If private, ensure ECS task execution role has GHCR access

3. **Check Health Check Configuration**
   - Verify health check paths are correct (`/health` for backend, `/` for frontend)
   - Ensure applications are listening on the correct ports
   - Check health check timeouts and intervals

### Long-term Improvements

1. **Add Pre-deployment Validation**
   - Verify Docker images exist before deployment
   - Check ACM certificates if HTTPS is enabled
   - Validate service configuration matches ALB configuration

2. **Improve Error Messages**
   - Add more descriptive error messages in workflow
   - Include links to CloudWatch logs
   - Provide rollback instructions

3. **Add Health Check Verification**
   - Test health check endpoints before marking services as stable
   - Verify target group health before completing deployment

## Next Steps

1. **Review Diagnostic Output**
   - Run the next deployment and review the diagnostic output
   - Identify the specific error causing task failures

2. **Fix Root Cause**
   - Based on diagnostic output, fix the identified issue
   - Common fixes:
     - Update image tags
     - Fix environment variables
     - Adjust health check configuration
     - Fix security group rules

3. **Re-deploy**
   - After fixes, re-run the deployment
   - Verify all services become stable
   - Confirm target groups have healthy targets

## Diagnostic Script

A comprehensive diagnostic script has been created at:
- `CI/scripts/diagnose-ecs-deployment.sh`

This script can be run manually to investigate issues:
```bash
export CLUSTER_NAME=dev-ecs-cluster
export AWS_REGION=us-east-1
./scripts/diagnose-ecs-deployment.sh
```

