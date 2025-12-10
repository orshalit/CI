# Test Execution Guide

## Quick Start

### Run Automated Tests

The comprehensive test script can be run in two ways:

#### Option 1: GitHub Actions (Recommended)

Add a test step to your workflow or run manually:

```yaml
- name: Run Infrastructure Tests
  run: |
    chmod +x scripts/comprehensive-infrastructure-test.sh
    scripts/comprehensive-infrastructure-test.sh dev 04-ecs-fargate
```

#### Option 2: Local (Linux/WSL/Git Bash)

```bash
cd CI
chmod +x scripts/comprehensive-infrastructure-test.sh
./scripts/comprehensive-infrastructure-test.sh dev 04-ecs-fargate
```

## What Gets Tested

The comprehensive test script verifies:

### ✅ Test 1: Terraform State
- State accessibility
- Key resources in state
- Service Discovery services count
- ECS services count

### ✅ Test 2: ECS Cluster
- Cluster exists and is ACTIVE
- Service count matches expected

### ✅ Test 3: ECS Services
- All services exist and are ACTIVE
- Running count matches desired count
- No services in failed state

### ✅ Test 4: ALB and Target Groups
- ALB exists and is active
- HTTPS listener (port 443) configured
- HTTP listener (port 80) configured
- All target groups healthy
- Target count matches expected

### ✅ Test 5: ALB Listener Rules
- HTTPS listener rules exist
- Host patterns configured correctly
- Rules point to correct target groups
- Default rule exists

### ✅ Test 6: Service Discovery
- Namespace exists and is active
- Services registered (may not appear in console)
- Service names match expected

### ✅ Test 7: CloudWatch Logs
- All log groups exist
- Log groups have active streams
- Recent log entries present

### ✅ Test 8: HTTPS Endpoints
- Legacy API responds
- Legacy Frontend responds
- Test-App API responds
- Test-App Frontend responds
- HTTP redirects to HTTPS

## Expected Test Results

### ✅ All Tests Should Pass

```
═══════════════════════════════════════════════════════════════
Test Summary
═══════════════════════════════════════════════════════════════
Passed: 25+
Warnings: 0-3 (acceptable)
Failed: 0

✓ All critical tests passed!
```

### ⚠️ Acceptable Warnings

- Service Discovery services not appearing in console (ECS-registered)
- Self-signed certificate warnings (if using test certs)
- DNS resolution test skipped (if VPC access unavailable)

### ❌ Failures Require Investigation

- ECS services not running → Check service events
- Target groups unhealthy → Check health check configuration
- Endpoints not responding → Check ALB rules and security groups
- Log groups missing → Check CloudWatch permissions

## Manual Test Commands

If you prefer to run tests manually, see `DEVOPS/COMPREHENSIVE-TEST-PLAN.md` for detailed commands.

## Integration with CI/CD

### Add to GitHub Actions Workflow

Add this step after successful deployment:

```yaml
- name: Run Infrastructure Tests
  if: steps.apply.outcome == 'success'
  run: |
    chmod +x scripts/comprehensive-infrastructure-test.sh
    scripts/comprehensive-infrastructure-test.sh ${{ inputs.environment }} ${{ inputs.module_path }}
  continue-on-error: true  # Don't fail deployment if tests fail
```

## Next Steps

1. **Run the test script** to verify current deployment
2. **Review any warnings** (most are informational)
3. **Investigate any failures** using troubleshooting guide
4. **Add to CI/CD pipeline** for automated testing

