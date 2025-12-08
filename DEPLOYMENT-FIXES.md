# Deployment Implementation - Alignment Fixes

This document summarizes the fixes applied to ensure consistency across the deployment pipeline.

## Issues Fixed

### 1. Docker Compose Image References
**Problem**: `docker-compose.prod.yml` was using `build:` context, which doesn't work for deployment with pre-built images from GHCR.

**Fix**: Changed to use `image:` with environment variable references:
```yaml
backend:
  image: ${BACKEND_IMAGE:-ghcr.io/changeme/ci-backend:latest}
  
frontend:
  image: ${FRONTEND_IMAGE:-ghcr.io/changeme/ci-frontend:latest}
```

**Impact**: Now docker-compose will pull pre-built images from GHCR instead of trying to build them on the EC2 instance.

### 2. Deployment Script Environment Variables
**Problem**: The `deploy.sh` script wasn't properly setting the `BACKEND_IMAGE` and `FRONTEND_IMAGE` environment variables for docker-compose.

**Fix**: Updated `deploy_containers()` function to properly export image variables:
```bash
export BACKEND_IMAGE="${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-backend:${DEPLOY_VERSION}"
export FRONTEND_IMAGE="${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-frontend:${DEPLOY_VERSION}"
```

**Impact**: Docker Compose now correctly uses the specific image versions that were pulled.

### 3. Environment File Generation
**Problem**: The `.env` file generation in `create_docker_compose_env()` wasn't comprehensive enough and had variable name mismatches.

**Fix**: Enhanced the `.env` file to include all necessary variables:
- `BACKEND_IMAGE` and `FRONTEND_IMAGE` (for docker-compose)
- Complete database configuration
- Application ports
- All required environment variables matching `docker-compose.prod.yml`

**Impact**: Docker Compose has all required environment variables properly configured.

### 4. SSM File Copy and Execution
**Problem**: The workflow assumed files were pre-installed on EC2, requiring manual setup.

**Fix**: Added automatic file copying via SSM before deployment:
```bash
# New approach: Copy files via SSM, then execute
1. Base64 encode deploy.sh and docker-compose.prod.yml
2. Send SSM command to decode and write files to /opt/ci-app/
3. Verify files are copied correctly
4. Execute deploy.sh script
```

**Impact**: 
- Fully automated deployment (no manual file copying)
- Files are version-controlled (exact version from git is deployed)
- Follows Infrastructure as Code best practices
- No escaping issues (base64 encoding)

### 5. EC2 Instance Setup Documentation
**Problem**: Documentation didn't clearly specify that `deploy.sh` needs to be pre-installed on the EC2 instance.

**Fix**: Updated `DEPLOYMENT.md` to:
- Clearly list required files in `/opt/ci-app/`:
  - `deploy.sh` (from `CI/scripts/deploy.sh`)
  - `docker-compose.prod.yml` (from `CI/docker-compose.prod.yml`)
- Added instructions for copying files via S3 or SSM

**Impact**: Operators know exactly what files need to be on the EC2 instance before deployment works.

### 6. OIDC Provider Creation Logic
**Problem**: The Terraform code for checking if OIDC provider exists was overly complex and could cause issues.

**Fix**: Simplified to just create the provider:
```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  # ... configuration
}
```

If provider already exists, users can:
1. Import it: `terraform import module.github_oidc.aws_iam_openid_connect_provider.github <arn>`
2. Or use the existing one (documented in module README)

**Impact**: Simpler, more maintainable Terraform code.

### 7. Image Naming Consistency
**Verified**: Image naming is consistent across the pipeline:
- **CI builds**: `ghcr.io/${{ github.repository_owner }}/ci-backend:${{ version }}`
- **Deploy script**: `${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-backend:${DEPLOY_VERSION}`
  - Note: `,,` converts to lowercase, which matches GHCR requirements
- **Docker Compose**: Uses `${BACKEND_IMAGE}` environment variable

**Impact**: Images are correctly referenced throughout the pipeline.

## Variable Mapping

### GitHub Actions → Deployment Script

| GitHub Actions Variable | Deploy Script Variable | Purpose |
|------------------------|----------------------|---------|
| `steps.version.outputs.version` | `DEPLOY_VERSION` | Docker image tag |
| `steps.version.outputs.commit` | `DEPLOY_COMMIT` | Git commit SHA |
| `github.repository_owner` | `GITHUB_OWNER` | GitHub org/user |
| `github.event.repository.name` | `GITHUB_REPO` | Repository name |
| `secrets.GITHUB_TOKEN` | `GITHUB_TOKEN` | GHCR authentication |

### Deployment Script → Docker Compose

| Deploy Script Variable | Docker Compose Variable | Purpose |
|-----------------------|------------------------|---------|
| Built by script | `BACKEND_IMAGE` | Backend container image |
| Built by script | `FRONTEND_IMAGE` | Frontend container image |
| From .env | `POSTGRES_USER` | Database username |
| From .env | `POSTGRES_PASSWORD` | Database password |
| From .env | `POSTGRES_DB` | Database name |
| From .env | `SECRET_KEY` | Application secret key |
| From .env | `CORS_ORIGINS` | CORS configuration |

### Terraform → GitHub Secrets

| Terraform Output | GitHub Secret | Purpose |
|-----------------|---------------|---------|
| `github_actions_role_arn` | `AWS_ROLE_ARN` | IAM role for OIDC |
| `aws_region` | `AWS_REGION` | AWS region |

## Pre-Deployment Checklist

Before deployment will work, ensure:

### EC2 Instance
- [ ] Docker installed and running
- [ ] Docker Compose v2 installed
- [ ] `/opt/ci-app/` directory exists and is writable
- [ ] `/opt/ci-app/deploy.sh` is present and executable
- [ ] `/opt/ci-app/docker-compose.prod.yml` is present
- [ ] SSM agent is running and instance is registered

### GitHub Repository
- [ ] `AWS_ROLE_ARN` secret configured (from Terraform output)
- [ ] `AWS_REGION` secret configured
- [ ] Repository has access to push images to GHCR
- [ ] Branch protection rules configured on `main`

### Terraform
- [ ] `DEVOPS/live/dev/03-github-oidc` applied
- [ ] `github_owner` matches your GitHub organization/username exactly
- [ ] `github_repo` matches your repository name exactly
- [ ] IAM role created successfully

### Images
- [ ] CI pipeline successfully builds and pushes images to GHCR
- [ ] Images are tagged with the version that deployment will use
- [ ] Images are accessible (check permissions in GitHub packages)

## Testing the Fixed Implementation

### 1. Verify EC2 Setup
```bash
# Connect to instance
aws ssm start-session --target i-xxxxxxxxxxxxx

# Verify files exist
ls -la /opt/ci-app/
# Should show: deploy.sh, docker-compose.prod.yml

# Verify deploy.sh is executable
test -x /opt/ci-app/deploy.sh && echo "Executable" || echo "Not executable"

# Verify Docker
docker --version
docker compose version
```

### 2. Test Manual Deployment
```bash
# From GitHub Actions UI
# Actions → Deploy to AWS → Run workflow
# Select: environment=dev, leave image tag empty

# Or via GitHub CLI
gh workflow run app-deploy-ec2.yml
```

### 3. Monitor Deployment
```bash
# Watch GitHub Actions logs in real-time
# https://github.com/<owner>/<repo>/actions

# Or SSH to instance and watch logs
aws ssm start-session --target i-xxxxxxxxxxxxx
tail -f /var/log/ci-deploy.log
```

### 4. Verify Deployment
```bash
# On EC2 instance
docker ps  # Should show 3 containers: database, backend, frontend
docker compose ps  # Should show all healthy

# Test endpoints
curl http://localhost:8000/health
curl http://localhost:8000/version
curl http://localhost:3000/
```

## Rollback Procedure If Issues Arise

If deployment fails after these changes:

1. **Check SSM command output** in GitHub Actions logs
2. **Check deployment logs** on EC2: `tail -100 /var/log/ci-deploy.log`
3. **Verify images exist** in GHCR: `docker pull ghcr.io/<owner>/ci-backend:<version>`
4. **Check docker-compose** syntax: `cd /opt/ci-app && docker compose config`
5. **Manual rollback**: The script should have automatically rolled back, but if not:
   ```bash
   cd /opt/ci-app
   source .last-successful-deployment
   export BACKEND_IMAGE=$BACKEND_IMAGE
   export FRONTEND_IMAGE=$FRONTEND_IMAGE
   docker compose down
   docker compose up -d
   ```

## Summary of Key Changes

1. ✅ Docker Compose now uses pre-built images (not build context)
2. ✅ Deployment script properly exports all image variables
3. ✅ SSM executes pre-installed script (not passed through parameters)
4. ✅ EC2 setup requirements clearly documented
5. ✅ Terraform OIDC provider creation simplified
6. ✅ All variable mappings verified and documented
7. ✅ Complete pre-deployment checklist provided

All changes maintain security best practices:
- No hardcoded credentials
- OIDC authentication only
- Least-privilege IAM permissions
- Automatic rollback on failure
- Comprehensive logging

