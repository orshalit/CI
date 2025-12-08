# Health Check Failure Analysis and Fixes

## Root Cause Identified

Based on the diagnostic script output, the issue is clear:

**Tasks are failing ELB health checks**

### Symptoms:
- ✅ Tasks start successfully (Exit Code: 0)
- ❌ Tasks fail health checks and are stopped
- ❌ Both `dev-api-service` and `dev-api_single-service` affected
- ✅ `dev-frontend-service` is working correctly

### Error Pattern:
```
Stop Code: ServiceSchedulerInitiated
Stop Reason: Task failed ELB health checks in (target-group ...)
Exit Code: 0
```

## Common Causes and Solutions

### 1. Health Check Path Incorrect

**Problem:** The health check path doesn't match what the application serves.

**Check:**
```bash
# Check current health check configuration
aws elbv2 describe-target-groups \
  --target-group-arns <TG_ARN> \
  --region us-east-1 \
  --query 'TargetGroups[0].HealthCheckPath'
```

**Fix:**
- Verify your backend application has a `/health` endpoint (or whatever path is configured)
- Test locally: `curl http://localhost:8000/health`
- Update health check path in Terraform if needed

### 2. Application Not Listening on Expected Port

**Problem:** Application is listening on a different port than configured.

**Check:**
```bash
# Check what port the container is configured to use
aws ecs describe-task-definition \
  --task-definition <TASK_DEF> \
  --region us-east-1 \
  --query 'taskDefinition.containerDefinitions[0].portMappings'
```

**Fix:**
- Ensure `container_port` in `services.generated.tfvars` matches the application's listening port
- Backend should listen on port 8000
- Frontend should listen on port 3000

### 3. Application Takes Too Long to Start

**Problem:** Health checks start before the application is ready.

**Check:**
- Review CloudWatch logs for startup time
- Check if application needs database connections or other dependencies

**Fix:**
- Increase `health_check_grace_period_seconds` in Terraform
- Add a startup probe or readiness check in the application
- Ensure application starts quickly

### 4. Security Group Rules Blocking Health Checks

**Problem:** ALB security group can't reach ECS tasks.

**Check:**
```bash
# Verify security group rules
aws ec2 describe-security-groups \
  --group-ids <ECS_TASKS_SG_ID> \
  --region us-east-1 \
  --query 'SecurityGroups[0].IpPermissions'
```

**Fix:**
- Ensure ECS tasks security group allows inbound traffic from ALB security group
- Port should match the container port (8000 for backend, 3000 for frontend)

### 5. Application Health Endpoint Returns Non-200 Status

**Problem:** Health endpoint exists but returns error status codes.

**Check:**
- Review application logs in CloudWatch
- Test health endpoint manually if possible

**Fix:**
- Ensure `/health` endpoint returns HTTP 200
- Check if database connection or other dependencies are causing failures

## Immediate Actions

### 1. Check Current Health Check Configuration

Run this to see the exact health check settings:

```bash
aws elbv2 describe-target-groups \
  --target-group-names dev-api-tg dev-api-single-tg \
  --region us-east-1 \
  --query 'TargetGroups[*].[TargetGroupName,HealthCheckPath,HealthCheckPort,HealthCheckProtocol,HealthCheckIntervalSeconds,HealthCheckTimeoutSeconds,HealthyThresholdCount,UnhealthyThresholdCount]' \
  --output table
```

### 2. Check CloudWatch Logs

```bash
# Check backend API logs for errors
aws logs tail /ecs/dev/api --follow --region us-east-1

# Check API single logs
aws logs tail /ecs/dev/api_single --follow --region us-east-1
```

Look for:
- Application startup errors
- Database connection failures
- Health endpoint errors
- Port binding issues

### 3. Test Health Endpoint Manually

If you can access the tasks (via VPN, bastion, etc.):

```bash
# From within VPC, test health endpoint
curl http://<TASK_IP>:8000/health
```

### 4. Verify Application Configuration

Check if the backend application:
- Has a `/health` endpoint
- Listens on port 8000
- Starts quickly (< 30 seconds)
- Doesn't require external dependencies to respond to health checks

## Recommended Fixes

### Option 1: Fix Health Check Path (if wrong)

Update `services.generated.tfvars`:

```hcl
alb = {
  alb_id            = "app_shared"
  listener_protocol = "HTTPS"
  listener_port     = 443
  path_patterns = ["/api/*"]
  host_patterns = ["app.dev.example.com"]
  
  # Add or update health check
  health_check_path = "/health"  # or "/api/health" if that's your endpoint
}
```

### Option 2: Increase Health Check Grace Period

Update Terraform module or add to variables:

```hcl
health_check_grace_period_seconds = 60  # Give app more time to start
```

### Option 3: Fix Application Health Endpoint

Ensure your backend application:
1. Has a `/health` endpoint that returns 200 OK
2. Doesn't require database connection for health check
3. Responds quickly (< 5 seconds)

Example health endpoint:
```python
@app.get("/health")
async def health_check():
    return {"status": "healthy"}
```

## Next Steps

1. **Run the fixed diagnostic script** to see detailed health check configuration
2. **Check CloudWatch logs** for application errors
3. **Verify health endpoint** exists and works
4. **Update configuration** based on findings
5. **Re-deploy** and monitor

## Why Frontend Works But Backend Doesn't

Frontend is working because:
- It likely has a simpler health check (just serving static files)
- It doesn't require database connections
- It starts faster

Backend is failing because:
- It may require database connection for health checks
- It may take longer to start
- Health endpoint may not exist or return errors

