# Deployment Testing Checklist

## Pre-Deployment Steps

### 1. ✅ Verify CI Workflow Passes
- [ ] Push latest changes to trigger CI workflow
- [ ] Wait for CI workflow to complete successfully
- [ ] Verify Docker images are built and pushed to GHCR
- [ ] Note the build version (e.g., `main-<commit-sha>`)

### 2. ✅ Verify Dhall Validation Passes
- [ ] Check `generate-service-config.yml` workflow passes
- [ ] Verify all service definitions are valid
- [ ] Ensure no type errors in Dhall files

### 3. ✅ Check Prerequisites
- [ ] **Dhall binaries cache**: Empty is OK (will download from GitHub)
- [ ] **Docker images**: Must exist in GHCR (built by CI workflow)
- [ ] **DEVOPS repo**: Will be checked out automatically by workflow
- [ ] **AWS credentials**: Configured in GitHub Secrets

### 4. ✅ Manual Deployment (Recommended First)

**Option A: Manual Workflow Dispatch (Recommended for Testing)**
1. Go to GitHub Actions → "Unified Deployment Pipeline (deploy)"
2. Click "Run workflow"
3. Fill in:
   - **Environment**: `dev`
   - **Module path**: `04-ecs-fargate`
   - **Action**: `plan` (test first, then `apply`)
   - **Image tag**: Leave empty (uses build version from CI)
   - **Application**: `all` or specific app name
4. Click "Run workflow"

**Option B: Automatic (After CI Completes)**
- Deployment will trigger automatically after CI workflow succeeds
- Uses build version from CI workflow artifact

### 5. ✅ Monitor Deployment

**Watch for:**
- ✅ Dhall installation succeeds (may show warnings if GitHub download fails, but cache fallback should work)
- ✅ Terraform Setup completes
- ✅ Services JSON/tfvars generated successfully
- ✅ Terraform plan shows expected changes
- ✅ No critical validation errors

**Common Issues:**
- **Dhall-json download fails**: Check error messages - improved diagnostics should show what went wrong
- **Terraform Setup fails**: Check if DEVOPS repo checkout succeeds
- **Image not found**: Ensure CI workflow built images before deploying

### 6. ✅ Post-Deployment Verification

After successful `apply`:
- [ ] Check ECS services are running
- [ ] Verify ALB target groups are healthy
- [ ] Test application endpoints
- [ ] Check CloudWatch logs for errors

## Quick Start Command

```bash
# 1. Push latest changes
git push

# 2. Wait for CI to complete, then manually trigger deployment:
# Go to: https://github.com/orshalit/CI/actions/workflows/deploy.yml
# Click "Run workflow" → Fill in details → Run
```

## Troubleshooting

### If dhall-json installation fails:
- Check GitHub API response in logs
- Verify dhall-json release exists for version 1.41.2
- Cache fallback should work if GitHub fails

### If Terraform Setup fails:
- Verify DEVOPS repo secrets are configured
- Check SSH key has access to DEVOPS repo

### If deployment fails:
- Check build version artifact exists from CI workflow
- Verify Docker images exist in GHCR
- Check Terraform state is accessible

