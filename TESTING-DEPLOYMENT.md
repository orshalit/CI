# Deployment Testing Guide

This guide walks you through testing the complete deployment pipeline from Terraform to production deployment.

## Pre-Test Checklist

Before testing, ensure you have:
- [ ] AWS credentials configured locally
- [ ] GitHub CLI installed (`gh`) or access to GitHub web UI
- [ ] Terraform installed
- [ ] Access to EC2 instance via SSM
- [ ] Your GitHub organization/username and repository name ready

## Phase 1: Terraform Infrastructure Setup

### Step 1.1: Configure OIDC Infrastructure

```bash
cd E:/DEVOPS/live/dev/03-github-oidc

# Create terraform.tfvars from example
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
# Required changes:
# - github_owner = "your-github-username"
# - github_repo = "CI"
notepad terraform.tfvars
```

**Example `terraform.tfvars`:**
```hcl
aws_region  = "us-east-1"
environment = "dev"
github_owner = "yourusername"  # ← CHANGE THIS
github_repo  = "CI"
allowed_branches = ["refs/heads/main"]
allow_pull_requests = false
```

### Step 1.2: Initialize and Apply Terraform

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (creates OIDC provider and IAM role)
terraform apply
# Type 'yes' when prompted
```

**Expected Output:**
```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

github_actions_role_arn = "arn:aws:iam::123456789012:role/github-actions-CI-dev"
aws_region = "us-east-1"
```

### Step 1.3: Save Terraform Outputs

```bash
# Save for GitHub secrets configuration
terraform output -raw github_actions_role_arn > role_arn.txt
terraform output -raw aws_region > aws_region.txt

# Display for verification
echo "Role ARN: $(cat role_arn.txt)"
echo "AWS Region: $(cat aws_region.txt)"
```

**✅ Verification:**
- [ ] Terraform applied successfully
- [ ] IAM role ARN saved
- [ ] No errors in Terraform output

---

## Phase 2: GitHub Repository Configuration

### Step 2.1: Configure GitHub Secrets

**Via GitHub CLI:**
```bash
cd E:/CI

# Set AWS_ROLE_ARN secret
gh secret set AWS_ROLE_ARN --body "$(cat ../DEVOPS/live/dev/03-github-oidc/role_arn.txt)"

# Set AWS_REGION secret
gh secret set AWS_REGION --body "us-east-1"

# Verify secrets are set
gh secret list
```

**Via GitHub Web UI:**
1. Go to: `https://github.com/YOUR-USERNAME/CI/settings/secrets/actions`
2. Click "New repository secret"
3. Add `AWS_ROLE_ARN` with value from Terraform output
4. Add `AWS_REGION` with value `us-east-1`

**✅ Verification:**
```bash
# Should show both secrets
gh secret list | grep -E "AWS_ROLE_ARN|AWS_REGION"
```

Expected:
```
AWS_REGION      Updated 2024-XX-XX
AWS_ROLE_ARN    Updated 2024-XX-XX
```

---

## Phase 3: EC2 Instance Preparation

### Step 3.1: Verify EC2 Instance Exists

```bash
# Find your EC2 instance
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=dev" \
            "Name=tag:ManagedBy,Values=Terraform" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name,PrivateIpAddress]' \
  --output table
```

**Expected Output:**
```
---------------------------------------------------------
|              DescribeInstances                        |
+----------------+-----------------+---------+-----------+
|  i-0a1b2c3d4e |  app-server-dev | running | 10.0.x.x |
+----------------+-----------------+---------+-----------+
```

**Save Instance ID:**
```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=dev" \
            "Name=tag:ManagedBy,Values=Terraform" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
```

### Step 3.2: Verify SSM Connectivity

```bash
# Check if instance is registered with SSM
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].[InstanceId,PingStatus,PlatformName]' \
  --output table
```

**Expected Output:**
```
----------------------------------------
|  DescribeInstanceInformation        |
+----------------+--------+-------------+
|  i-0a1b2c3d4e | Online | Ubuntu      |
+----------------+--------+-------------+
```

### Step 3.3: Verify EC2 Instance (Optional)

**Note:** Docker, Docker Compose, and deployment files are automatically installed/copied during deployment. Manual setup is optional.

**Optional Verification:**

```bash
# Start SSM session
aws ssm start-session --target $INSTANCE_ID
```

**On EC2 Instance, run these commands (optional):**

```bash
# Check SSM agent (should be running)
sudo systemctl status amazon-ssm-agent
# Expected: active (running)

# Check if Docker is installed (optional - will be installed automatically)
docker --version || echo "Docker will be installed during deployment"
docker compose version || echo "Docker Compose will be installed during deployment"
```

**Note:** All prerequisites (Docker, Docker Compose, deployment files) are automatically handled by the deployment workflow. No manual setup is required.

### Step 3.4: Verify EC2 is Ready for Deployment

**Fully Automated:** Everything is handled automatically during deployment:
- Docker and Docker Compose installation (if needed)
- Deployment directory creation
- File copying

**Optional Verification:**

```bash
# On EC2 instance (optional check)
# Verify SSM agent is running
sudo systemctl status amazon-ssm-agent
# Expected: active (running)

# Docker and Docker Compose will be installed automatically if not present
# No need to check or install manually
```

### Step 3.5: Verify EC2 Setup

```bash
# On EC2 instance
echo "=== Deployment Directory Contents ==="
ls -la /opt/ci-app/

echo -e "\n=== Docker Status ==="
docker ps

echo -e "\n=== Docker Compose Config Check ==="
cd /opt/ci-app
docker compose config --quiet && echo "✓ Config valid" || echo "✗ Config invalid"
```

**✅ Verification Checklist:**
- [ ] Instance is running and accessible via SSM
- [ ] SSM agent is online and running
- [ ] Base64 utility is available (standard on Ubuntu/Amazon Linux)

**Note:** 
- Docker and Docker Compose are automatically installed during deployment if not present
- Deployment files are automatically copied during deployment
- No manual setup needed - everything is fully automated

**Exit SSM Session:**
```bash
exit
```

---

## Phase 4: Test CI Pipeline (Without Deployment)

### Step 4.1: Verify CI Workflow Exists

```bash
cd E:/CI

# Check workflows
ls -la .github/workflows/
# Should show: ci.yml, deploy.yml, and others

# Verify deploy.yml exists
cat .github/workflows/deploy.yml | head -20
```

### Step 4.2: Check Current CI Status

```bash
# View recent workflow runs
gh run list --limit 5
```

### Step 4.3: Trigger CI Manually (Optional)

```bash
# If you want to test CI first without deployment
# Make a small change and push to a feature branch
git checkout -b test-deployment
echo "# Test change" >> README.md
git add README.md
git commit -m "test: trigger CI"
git push origin test-deployment

# Watch CI run
gh run watch
```

**✅ Verification:**
- [ ] CI workflow runs successfully
- [ ] All tests pass
- [ ] Docker images are built and pushed to GHCR

---

## Phase 5: Test Deployment

### Step 5.1: Manual Deployment Test (Recommended First)

```bash
# Trigger deployment manually via GitHub Actions
gh workflow run deploy.yml

# Or via web UI:
# https://github.com/YOUR-USERNAME/CI/actions/workflows/deploy.yml
# Click "Run workflow" → Select branch: main → Run workflow

# Watch deployment
gh run watch
```

**Monitor Deployment Progress:**

In the GitHub Actions UI, you should see:
1. ✅ Checkout code
2. ✅ Configure AWS credentials via OIDC
3. ✅ Find EC2 instance by tags
4. ✅ Verify SSM connectivity
5. ✅ Deploy via SSM Run Command
6. ✅ Wait for deployment completion
7. ✅ Retrieve deployment logs
8. ✅ Verify deployment health

### Step 5.2: Monitor Deployment on EC2

**Open a second terminal and connect to EC2:**

```bash
# In second terminal
INSTANCE_ID="i-xxxxx"  # Your instance ID
aws ssm start-session --target $INSTANCE_ID

# Watch deployment logs in real-time
tail -f /var/log/ci-deploy.log
```

**Expected Log Output:**
```
[2024-XX-XX HH:MM:SS] [INFO] ==========================================
[2024-XX-XX HH:MM:SS] [INFO] Starting deployment
[2024-XX-XX HH:MM:SS] [INFO] Version: main-abc1234
[2024-XX-XX HH:MM:SS] [SUCCESS] Environment validation passed
[2024-XX-XX HH:MM:SS] [SUCCESS] Successfully authenticated to GHCR
[2024-XX-XX HH:MM:SS] [INFO] Pulling Docker images for version: main-abc1234
[2024-XX-XX HH:MM:SS] [SUCCESS] Backend image pulled successfully
[2024-XX-XX HH:MM:SS] [SUCCESS] Frontend image pulled successfully
[2024-XX-XX HH:MM:SS] [INFO] Stopping old containers gracefully...
[2024-XX-XX HH:MM:SS] [INFO] Starting new containers...
[2024-XX-XX HH:MM:SS] [SUCCESS] Containers started successfully
[2024-XX-XX HH:MM:SS] [INFO] Verifying deployment health...
[2024-XX-XX HH:MM:SS] [SUCCESS] Database is healthy
[2024-XX-XX HH:MM:SS] [SUCCESS] Backend is healthy
[2024-XX-XX HH:MM:SS] [SUCCESS] Frontend is healthy
[2024-XX-XX HH:MM:SS] [SUCCESS] All health checks passed
[2024-XX-XX HH:MM:SS] [SUCCESS] Deployment completed successfully!
```

### Step 5.3: Verify Deployment

**On EC2 Instance:**

```bash
# Check running containers
docker ps
# Expected: 3 containers (database, backend, frontend) - all healthy

# Check Docker Compose status
cd /opt/ci-app
docker compose ps
# Expected: All services Up and healthy

# Test endpoints
echo "=== Database ==="
docker exec database pg_isready -U appuser -d appdb

echo -e "\n=== Backend Health ==="
curl -f http://localhost:8000/health | jq .

echo -e "\n=== Backend Version ==="
curl -f http://localhost:8000/version | jq .

echo -e "\n=== Frontend ==="
curl -f http://localhost:3000/ | head -20
```

**Expected Backend Version Output:**
```json
{
  "version": "main-abc1234",
  "commit": "abc1234",
  "environment": "production",
  "status": "healthy"
}
```

### Step 5.4: Check GitHub Actions Output

```bash
# Get the latest deployment run
gh run list --workflow=deploy.yml --limit 1

# View detailed logs
gh run view --log
```

**Expected Summary in GitHub Actions:**
```
## 🚀 Deployment Summary

**Status:** ✅ Success

**Target Instance:**
- Instance ID: `i-0a1b2c3d4e`
- Instance Name: `app-server-dev`

**Deployment Details:**
- Version: `main-abc1234`
- Commit: `abc1234`

**Docker Images:**
- Backend: `ghcr.io/username/ci-backend:main-abc1234`
- Frontend: `ghcr.io/username/ci-frontend:main-abc1234`
```

---

## Phase 6: Test Automatic Deployment

### Step 6.1: Create a Test PR

```bash
# Create a feature branch
git checkout main
git pull
git checkout -b test-auto-deploy

# Make a small change
echo "# Deployment test $(date)" >> TESTING-DEPLOYMENT.md
git add TESTING-DEPLOYMENT.md
git commit -m "test: automatic deployment"
git push origin test-auto-deploy

# Create PR
gh pr create --title "Test: Automatic Deployment" --body "Testing automatic deployment after CI passes"
```

### Step 6.2: Wait for CI to Pass

```bash
# Watch PR checks
gh pr checks

# Expected: All checks passing ✅
```

### Step 6.3: Merge PR

```bash
# Merge the PR
gh pr merge --merge --delete-branch

# Or via web UI: Click "Merge pull request"
```

### Step 6.4: Verify Automatic Deployment Triggers

```bash
# Watch for deployment workflow to trigger
gh run watch

# Should see:
# 1. CI workflow completes on main
# 2. Deploy workflow triggers automatically
# 3. Deployment completes successfully
```

---

## Phase 7: Test Rollback

### Step 7.1: Simulate Failed Deployment

**On EC2, temporarily break the deployment:**

```bash
# Connect to EC2
aws ssm start-session --target $INSTANCE_ID

# Rename docker-compose file to simulate failure
cd /opt/ci-app
mv docker-compose.prod.yml docker-compose.prod.yml.backup

# Try to trigger deployment (it will fail and rollback)
```

**Trigger deployment from GitHub Actions** - it should fail and automatically rollback.

### Step 7.2: Verify Rollback Works

**Check deployment logs:**
```bash
tail -100 /var/log/ci-deploy.log | grep -A 10 "rollback"
```

**Expected:**
```
[ERROR] Deployment failed
[ERROR] Initiating rollback to previous version...
[INFO] Rolling back to: backend=..., frontend=...
[INFO] Rollback complete. Please verify manually.
```

### Step 7.3: Restore and Re-deploy

```bash
# Restore docker-compose file
mv docker-compose.prod.yml.backup docker-compose.prod.yml

# Trigger deployment again - should succeed
# Exit EC2
exit
```

---

## Troubleshooting Common Issues

### Issue 1: OIDC Authentication Fails

**Error:** "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Fix:**
```bash
# Verify Terraform outputs match GitHub secrets
cd E:/DEVOPS/live/dev/03-github-oidc
terraform output github_actions_role_arn

# Compare with GitHub secret
gh secret list

# Re-set if needed
gh secret set AWS_ROLE_ARN --body "$(terraform output -raw github_actions_role_arn)"
```

### Issue 2: EC2 Instance Not Found

**Error:** "No running EC2 instance found"

**Fix:**
```bash
# Check instance tags
aws ec2 describe-tags \
  --filters "Name=resource-id,Values=$INSTANCE_ID" \
  --query 'Tags[*].[Key,Value]' \
  --output table

# Add missing tags if needed
aws ec2 create-tags \
  --resources $INSTANCE_ID \
  --tags Key=Environment,Value=dev Key=ManagedBy,Value=Terraform
```

### Issue 3: SSM Agent Not Online

**Error:** "Instance is not online in SSM"

**Fix:**
```bash
# On EC2 (after connecting via alternative method)
sudo systemctl status amazon-ssm-agent
sudo systemctl restart amazon-ssm-agent

# Wait 2-3 minutes, then verify
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID"
```

### Issue 4: Docker Images Not Found

**Error:** "Failed to pull backend/frontend image"

**Fix:**
```bash
# Verify images exist in GHCR
gh api /users/YOUR-USERNAME/packages

# Check specific package
gh api /users/YOUR-USERNAME/packages/container/ci-backend/versions

# Ensure CI completed successfully and pushed images
gh run list --workflow=ci.yml --limit 1
```

### Issue 5: Health Checks Fail

**Error:** "Health checks failed"

**Fix:**
```bash
# On EC2, check container logs
cd /opt/ci-app
docker compose logs backend
docker compose logs frontend
docker compose logs database

# Check if containers are running
docker compose ps

# Check if ports are accessible
curl http://localhost:8000/health
curl http://localhost:3000/
```

---

## Success Criteria

Your deployment is fully working when:

- [x] ✅ Terraform creates OIDC infrastructure
- [x] ✅ GitHub secrets are configured
- [x] ✅ EC2 instance is accessible via SSM
- [x] ✅ Deployment files are on EC2
- [x] ✅ Manual deployment succeeds
- [x] ✅ Automatic deployment triggers after CI passes
- [x] ✅ All health checks pass
- [x] ✅ Services are accessible on EC2
- [x] ✅ Rollback works when deployment fails

---

## Next Steps After Successful Test

Once everything works:

1. **Configure Branch Protection:**
   - Go to: `https://github.com/YOUR-USERNAME/CI/settings/branches`
   - Add branch protection rule for `main`
   - Enable: Require PR, require status checks, no force push

2. **Document Your Setup:**
   - Save your `terraform.tfvars` (without committing)
   - Document any custom configurations
   - Save EC2 instance ID for reference

3. **Monitor Production:**
   - Set up CloudWatch alarms
   - Configure log aggregation
   - Set up alerts for failed deployments

4. **Plan for Scale:**
   - Consider moving to RDS when ready
   - Plan for multiple EC2 instances
   - Consider adding load balancer

---

## Quick Reference Commands

```bash
# Deploy manually
gh workflow run deploy.yml

# Watch deployment
gh run watch

# Check EC2 logs
aws ssm start-session --target $INSTANCE_ID
tail -f /var/log/ci-deploy.log

# Check container status
docker compose ps

# View recent deployments
gh run list --workflow=deploy.yml --limit 5

# Rollback manually
cd /opt/ci-app
source .last-successful-deployment
export BACKEND_IMAGE=$BACKEND_IMAGE
export FRONTEND_IMAGE=$FRONTEND_IMAGE
docker compose down && docker compose up -d
```

Good luck with your testing! 🚀

