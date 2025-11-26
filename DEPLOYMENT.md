# Deployment Guide

This guide explains how to set up and use the secure deployment pipeline for deploying the application to AWS EC2 instances using GitHub Actions with OIDC authentication.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Setup Instructions](#setup-instructions)
4. [Deployment Flow](#deployment-flow)
5. [Branch Protection Rules](#branch-protection-rules)
6. [Manual Deployment](#manual-deployment)
7. [Troubleshooting](#troubleshooting)
8. [Rollback Procedures](#rollback-procedures)

## Overview

The deployment pipeline provides:
- ✅ **Secure Authentication**: OIDC-based authentication (no AWS access keys)
- ✅ **Automated Deployments**: Automatic deployment after successful CI on `main` branch
- ✅ **Zero-Downtime**: Graceful container shutdown and health check verification
- ✅ **Automatic Rollback**: Rollback to previous version on deployment failure
- ✅ **SSM-Based**: Uses AWS Systems Manager for secure command execution

### Architecture

```
┌─────────────────────┐
│  GitHub Actions     │
│  (merge to main)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  CI Pipeline        │
│  (tests pass)       │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  OIDC Authentication│
│  (assume IAM role)  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Find EC2 Instance  │
│  (by tags)          │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  SSM Run Command    │
│  (deploy script)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Pull GHCR Images   │
│  Docker Compose Up  │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Health Checks      │
│  (verify deployment)│
└─────────────────────┘
```

## Prerequisites

### 1. Infrastructure Setup (Terraform)

The AWS infrastructure must be set up using Terraform:

```bash
cd DEVOPS/live/dev/03-github-oidc

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GitHub org/repo

# Apply Terraform
terraform init
terraform apply

# Get the outputs
terraform output github_actions_role_arn
terraform output aws_region
```

### 2. EC2 Instance Requirements

The EC2 instance must have:
- ✅ **SSM Agent**: Installed and running (already configured in `02-app-server`)
- ✅ **Base64 utility**: Available for file decoding (standard on Ubuntu/Amazon Linux)

**Note:** 
- Docker and Docker Compose are automatically installed during deployment if not present
- Deployment files (`deploy.sh` and `docker-compose.prod.yml`) are automatically copied to EC2 via SSM during deployment
- No manual setup is required - the deployment workflow handles everything automatically

#### EC2 Instance Setup (Optional - Automatic Installation Available)

**Fully Automated:** Docker, Docker Compose, and deployment files are automatically installed/copied during deployment. No manual setup is required.

**Optional Manual Setup (if you prefer):**

If you want to pre-install Docker and Docker Compose manually, you can run:

```bash
#!/bin/bash
# Run as the SSM user (ssm-user or ec2-user)

# Install Docker (if not already installed)
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installations
docker --version
docker compose version
```

**Note:** 
- The deployment workflow automatically installs Docker and Docker Compose if they're not present
- Deployment files (`deploy.sh` and `docker-compose.prod.yml`) are automatically copied to `/opt/ci-app/` during each deployment via SSM
- The `/opt/ci-app/` directory is created automatically during deployment
- No manual setup is required - everything is handled automatically by the workflow

### 3. GitHub Repository Secrets

Configure these secrets in your GitHub repository:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Value | Source |
|-------------|-------|--------|
| `AWS_ROLE_ARN` | `arn:aws:iam::123456789012:role/github-actions-...` | Terraform output `github_actions_role_arn` |
| `AWS_REGION` | `us-east-1` | Your AWS region |

**GitHub Secret Configuration URL:**
```
https://github.com/<owner>/<repo>/settings/secrets/actions
```

## Setup Instructions

### Step 1: Apply Terraform Infrastructure

```bash
# Navigate to the OIDC configuration directory
cd DEVOPS/live/dev/03-github-oidc

# Configure your values
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Edit with your GitHub org/repo

# Apply
terraform init
terraform plan
terraform apply

# Save the outputs
terraform output > terraform-outputs.txt
```

### Step 2: Configure GitHub Secrets

```bash
# Get the role ARN
ROLE_ARN=$(cd DEVOPS/live/dev/03-github-oidc && terraform output -raw github_actions_role_arn)

# Add to GitHub (do this via the web UI or GitHub CLI)
gh secret set AWS_ROLE_ARN --body "$ROLE_ARN"
gh secret set AWS_REGION --body "us-east-1"
```

### Step 3: Verify EC2 Instance (Optional)

**Fully Automated:** The deployment workflow automatically:
- Installs Docker and Docker Compose if not present
- Copies deployment files to EC2
- Creates necessary directories
- No manual setup required!

**Optional Verification:**

If you want to verify your EC2 instance is ready:

```bash
# Connect to instance
aws ssm start-session --target i-xxxxxxxxxxxxx

# Check SSM agent (should already be running)
sudo systemctl status amazon-ssm-agent

# Check if Docker is installed (optional - will be installed automatically if missing)
docker --version || echo "Docker will be installed during deployment"
```

**Note:** Everything is automated. The workflow will install Docker/Docker Compose and copy files automatically during the first deployment.

### Step 4: Test Deployment

Trigger a manual deployment to test the setup:

1. Go to: `https://github.com/<owner>/<repo>/actions/workflows/deploy.yml`
2. Click "Run workflow"
3. Select environment: `dev`
4. Leave image tag empty (uses latest from main)
5. Click "Run workflow"

Monitor the workflow execution and verify:
- ✅ OIDC authentication succeeds
- ✅ EC2 instance is found
- ✅ SSM command executes successfully
- ✅ Containers are deployed
- ✅ Health checks pass

### Step 5: Enable Automatic Deployments

Once manual testing succeeds, deployments will automatically trigger after successful CI runs on the `main` branch.

### Step 6: Configure Branch Protection

See [Branch Protection Rules](#branch-protection-rules) section below.

## Deployment Flow

### Automatic Deployment (Main Branch)

1. **Developer creates PR** → branch with changes
2. **CI runs on PR** → all tests must pass
3. **PR is merged to main** → CI runs again on main
4. **CI completes successfully** → deployment workflow triggers automatically
5. **Deployment workflow**:
   - Authenticates to AWS via OIDC
   - Finds target EC2 instance by tags
   - Sends deployment script via SSM
   - Monitors deployment progress
   - Verifies health checks
   - Reports success/failure

### Deployment Steps (Executed on EC2)

The `scripts/deploy.sh` script performs the following:

1. **Validate Environment**
   - Check required environment variables
   - Verify Docker and Docker Compose are installed
   - Create deployment directory if needed

2. **Authenticate to GHCR**
   - Login to GitHub Container Registry using GitHub token

3. **Save Current State**
   - Record currently running versions for rollback

4. **Pull New Images**
   - Pull backend image: `ghcr.io/<owner>/ci-backend:<version>`
   - Pull frontend image: `ghcr.io/<owner>/ci-frontend:<version>`

5. **Deploy Containers**
   - Stop old containers gracefully (30s timeout)
   - Start new containers with docker-compose

6. **Verify Deployment**
   - Wait for database to be ready
   - Health check backend `/health` endpoint (120s timeout)
   - Health check frontend root endpoint (120s timeout)
   - Verify deployed version matches expected version

7. **Rollback on Failure**
   - If health checks fail, automatically rollback to previous version

8. **Cleanup**
   - Remove dangling images
   - Keep only last 3 versions

## Branch Protection Rules

Configure these rules for the `main` branch to ensure secure deployments:

### Required Settings

Navigate to: `https://github.com/<owner>/<repo>/settings/branches`

Click "Add branch protection rule" for `main`:

#### General

- ✅ **Require a pull request before merging**
  - Required approving reviews: `1` (or more)
  - Dismiss stale pull request approvals when new commits are pushed: ✅
  - Require review from Code Owners: ✅ (if using CODEOWNERS)

#### Status Checks

- ✅ **Require status checks to pass before merging**
  - ✅ Require branches to be up to date before merging
  - **Required status checks**:
    - `Code Quality & Security`
    - `Backend Tests / unit`
    - `Backend Tests / integration`
    - `Frontend Tests`
    - `End-to-End Tests`
    - `Build Docker Images / backend`
    - `Build Docker Images / frontend`

#### Additional Rules

- ✅ **Require conversation resolution before merging**
- ✅ **Do not allow bypassing the above settings**
- ✅ **Restrict who can push to matching branches** (optional)
  - Add teams/users who can directly push (usually none)

#### Prevent Destructive Actions

- ✅ **Do not allow force pushes**
- ✅ **Allow deletions**: ❌ (unchecked)

### Verification

After configuring, verify the rules work:

1. Try to push directly to `main`:
   ```bash
   git push origin main
   ```
   **Expected**: Push should be rejected

2. Create a PR and try to merge without CI passing:
   **Expected**: Merge button should be disabled

3. Create a PR, wait for CI to pass, then merge:
   **Expected**: Merge should succeed, deployment should trigger

## Manual Deployment

You can manually trigger deployments for testing or emergency releases.

### Via GitHub UI

1. Go to: `https://github.com/<owner>/<repo>/actions/workflows/deploy.yml`
2. Click "Run workflow"
3. Configure:
   - **Branch**: Choose branch to deploy from
   - **Environment**: Choose target environment (dev/staging/production)
   - **Image tag**: Specify a version or leave empty for latest
4. Click "Run workflow"

### Via GitHub CLI

```bash
# Deploy latest version to dev
gh workflow run deploy.yml

# Deploy specific version
gh workflow run deploy.yml -f image_tag=v1.2.3 -f environment=production
```

### Via AWS SSM (Direct)

If GitHub Actions is unavailable, you can deploy directly via SSM:

```bash
# Set variables
INSTANCE_ID="i-xxxxxxxxxxxxx"
VERSION="v1.2.3"
GITHUB_OWNER="your-org"
GITHUB_REPO="CI"
GITHUB_TOKEN="ghp_xxxx"  # Your GitHub PAT

# Send command
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters commands="[
    \"export DEPLOY_VERSION='${VERSION}'\",
    \"export GITHUB_OWNER='${GITHUB_OWNER}'\",
    \"export GITHUB_REPO='${GITHUB_REPO}'\",
    \"export GITHUB_TOKEN='${GITHUB_TOKEN}'\",
    \"$(cat scripts/deploy.sh)\"
  ]"
```

## Troubleshooting

### Deployment Fails: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause**: OIDC trust policy or GitHub secrets are misconfigured.

**Fix**:
1. Verify GitHub secrets are correct:
   ```bash
   # Check if secrets are set
   gh secret list
   ```

2. Verify Terraform configuration matches your repo:
   ```bash
   cd DEVOPS/live/dev/03-github-oidc
   grep github_owner terraform.tfvars
   grep github_repo terraform.tfvars
   ```

3. Re-apply Terraform if needed:
   ```bash
   terraform apply
   ```

### Deployment Fails: "No running EC2 instance found"

**Cause**: EC2 instance is not running or not tagged correctly.

**Fix**:
1. Verify instance is running:
   ```bash
   aws ec2 describe-instances \
     --filters "Name=tag:Environment,Values=dev" \
               "Name=tag:ManagedBy,Values=Terraform" \
               "Name=instance-state-name,Values=running" \
     --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags]'
   ```

2. If missing tags, add them via AWS Console or CLI:
   ```bash
   aws ec2 create-tags \
     --resources i-xxxxxxxxxxxxx \
     --tags Key=Environment,Value=dev Key=ManagedBy,Value=Terraform
   ```

### Deployment Fails: "Instance is not online in SSM"

**Cause**: SSM agent is not running or not configured correctly.

**Fix**:
1. Connect to instance and check SSM agent:
   ```bash
   aws ssm start-session --target i-xxxxxxxxxxxxx
   
   # On instance
   sudo systemctl status amazon-ssm-agent
   sudo systemctl start amazon-ssm-agent
   ```

2. Verify IAM role has SSM permissions:
   ```bash
   aws iam list-attached-role-policies --role-name <instance-role-name>
   # Should include AmazonSSMManagedInstanceCore
   ```

### Deployment Fails: "Failed to pull backend/frontend image"

**Cause**: Images don't exist or GitHub token is invalid.

**Fix**:
1. Verify images exist in GHCR:
   ```bash
   gh api "/users/<owner>/packages/container/ci-backend/versions"
   ```

2. Verify the version/tag exists:
   ```bash
   gh api "/users/<owner>/packages/container/ci-backend/versions" \
     | jq '.[] | select(.metadata.container.tags[] | contains("main-abc1234"))'
   ```

3. Check `GITHUB_TOKEN` permissions in workflow:
   - Should have `packages: read` permission

### Health Checks Fail

**Cause**: Services didn't start correctly or are unhealthy.

**Fix**:
1. Check SSM command output in GitHub Actions logs

2. SSH to instance and check container logs:
   ```bash
   cd /opt/ci-app
   docker compose logs backend
   docker compose logs frontend
   docker compose logs database
   ```

3. Check container status:
   ```bash
   docker compose ps
   docker ps -a
   ```

4. Manually test health endpoints:
   ```bash
   curl http://localhost:8000/health
   curl http://localhost:3000/
   ```

### Deployment Logs

View deployment logs on the EC2 instance:

```bash
# Connect to instance
aws ssm start-session --target i-xxxxxxxxxxxxx

# View deployment logs
tail -f /var/log/ci-deploy.log

# View last deployment
tail -100 /var/log/ci-deploy.log
```

## Rollback Procedures

### Automatic Rollback

If deployment health checks fail, the deployment script automatically rolls back to the previous version.

### Manual Rollback via GitHub Actions

1. Find the previous successful deployment:
   ```bash
   gh run list --workflow=deploy.yml --status=success --limit=5
   ```

2. Get the commit SHA from that deployment

3. Trigger deployment with that version:
   ```bash
   gh workflow run deploy.yml -f image_tag=main-abc1234
   ```

### Manual Rollback via SSM

```bash
# Connect to instance
aws ssm start-session --target i-xxxxxxxxxxxxx

# Check rollback state
cat /opt/ci-app/.last-successful-deployment

# Load previous versions
source /opt/ci-app/.last-successful-deployment

# Rollback
cd /opt/ci-app
export BACKEND_IMAGE=$BACKEND_IMAGE
export FRONTEND_IMAGE=$FRONTEND_IMAGE
docker compose down
docker compose up -d
```

### Emergency Rollback (Complete)

If all else fails, redeploy the entire stack from scratch:

```bash
# Connect to instance
aws ssm start-session --target i-xxxxxxxxxxxxx

# Stop all containers
cd /opt/ci-app
docker compose down -v  # WARNING: This removes volumes (database data)

# Pull a known good version
docker pull ghcr.io/<owner>/ci-backend:v1.0.0
docker pull ghcr.io/<owner>/ci-frontend:v1.0.0

# Deploy
export BACKEND_IMAGE=ghcr.io/<owner>/ci-backend:v1.0.0
export FRONTEND_IMAGE=ghcr.io/<owner>/ci-frontend:v1.0.0
docker compose up -d
```

## Security Considerations

### OIDC Authentication
- ✅ No long-lived AWS access keys
- ✅ Temporary credentials with limited scope
- ✅ Role can only be assumed by specific GitHub repo and branches

### Least-Privilege IAM Permissions
- ✅ Only EC2 read and SSM command permissions
- ✅ No permissions to modify infrastructure
- ✅ Cannot access other AWS services

### Branch Protection
- ✅ Only approved PRs can be merged
- ✅ All CI checks must pass before merge
- ✅ No direct pushes to main

### Audit Trail
- ✅ All deployments logged to `/var/log/ci-deploy.log`
- ✅ SSM commands logged to CloudWatch
- ✅ IAM role assumptions logged to CloudTrail
- ✅ GitHub Actions workflow logs preserved

## Monitoring

### GitHub Actions

View deployment history:
```
https://github.com/<owner>/<repo>/actions/workflows/deploy.yml
```

### AWS CloudWatch

View SSM command logs:
```bash
aws logs tail /aws/ssm/AWS-RunShellScript --follow
```

### EC2 Instance

View deployment logs:
```bash
tail -f /var/log/ci-deploy.log
```

View Docker logs:
```bash
cd /opt/ci-app
docker compose logs -f
```

## References

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS Systems Manager Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/execute-remote-commands.html)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Branch Protection Rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)

## Support

For issues with:
- **Terraform infrastructure**: See `DEVOPS/live/dev/03-github-oidc/README.md`
- **CI pipeline**: See `CI-CD-GUIDE.md`
- **Docker configuration**: See `docker-compose.prod.yml` comments
- **EC2 instance setup**: See `DEVOPS/live/dev/02-app-server/README.md`

