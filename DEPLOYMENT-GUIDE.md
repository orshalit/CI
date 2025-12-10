# Deployment Guide

## Overview

To deploy your application, you need to:
1. **Deploy Infrastructure** (if not already deployed) - Creates ECS cluster, VPC, etc.
2. **Deploy Application** - Deploys your application containers to the ECS cluster

## ⚠️ IMPORTANT: Deployment Order

**Before deploying infrastructure, you MUST generate services configuration:**

1. **First:** Run "Create / Update ECS Service" workflow → Generates `services.generated.tfvars`
2. **Then:** Run "Deploy Infrastructure" workflow → Deploys infrastructure and services

**Why?** If `services.generated.tfvars` is empty (`services = {}`) but you have existing services in Terraform state, Terraform will **DESTROY all your services**!

The workflow will now detect this and fail with a clear error message if you try to deploy with empty services when state has services.

## Step 0: Generate Services Configuration (REQUIRED FIRST)

### Workflow: `Create / Update ECS Service (generate DEVOPS PR)`

**Location:** GitHub Actions → Create / Update ECS Service (generate DEVOPS PR)

**Steps:**
1. Go to GitHub Actions in your repository
2. Select "Create / Update ECS Service (generate DEVOPS PR)" from the workflow list
3. Click "Run workflow"
4. Fill in the inputs:
   - **Environment:** `dev` (or `staging`/`production`)
5. Review the generated PR in the DEVOPS repository
6. Merge the PR to update `services.generated.tfvars`

**This generates `DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars` from your YAML service definitions.**

## Step 1: Deploy Infrastructure (ECS Cluster)

If you don't have an ECS cluster deployed yet, use the **Deploy Infrastructure** workflow.

### Workflow: `Deploy Infrastructure (deploy-infra)`

**Location:** GitHub Actions → Deploy Infrastructure (deploy-infra)

**⚠️ Prerequisites:**
- `services.generated.tfvars` must exist and have services defined (not empty)
- If you see an error about empty services, run "Create / Update ECS Service" first

**Steps:**
1. Go to GitHub Actions in your repository
2. Select "Deploy Infrastructure (deploy-infra)" from the workflow list
3. Click "Run workflow"
4. Fill in the inputs:
   - **Environment:** `dev` (or `staging`/`production`)
   - **Module path:** `04-ecs-fargate` (this creates the ECS cluster)
   - **Action:** `plan` (first run to see what will be created)
5. Review the plan output
6. Run again with **Action:** `apply` to actually create the infrastructure

### Deployment Order (if deploying from scratch)

Deploy modules in this order:
1. `00-dns-acm` - DNS and SSL certificates
2. `01-vpc` - Virtual Private Cloud (networking)
3. `03-github-oidc` - GitHub OIDC for authentication (if needed)
4. `04-ecs-fargate` - **ECS Cluster** (required for applications)
5. `05-database` - Database (optional, if your app needs it)

**Note:** You can check which modules are already deployed by looking at `DEVOPS/live/dev/*/terraform.tfstate` files.

## Step 2: Deploy Application

Once the ECS cluster is deployed, use the **Deploy Application to ECS** workflow.

### Workflow: `Deploy Application to ECS (app-deploy-ecs)`

**Location:** GitHub Actions → Deploy Application to ECS (app-deploy-ecs)

**This workflow:**
- Automatically triggers after successful CI builds on `main` branch
- Can also be manually triggered via `workflow_dispatch`

**Manual Deployment Steps:**
1. Go to GitHub Actions → Deploy Application to ECS (app-deploy-ecs)
2. Click "Run workflow"
3. Fill in the inputs:
   - **Application:** `all` (or specific app like `legacy`, `test-app`)
   - **Environment:** `dev` (or `staging`/`production`)
   - **Image tag:** Leave empty to use latest from CI build, or specify a tag
   - **Skip verification:** `true` (faster) or `false` (full verification)

**What it does:**
- Downloads the build version from the CI workflow
- Filters services by application
- Generates service image tag overrides
- Runs Terraform plan to see changes
- Runs Terraform apply to deploy
- Verifies deployment (if not skipped)

## Quick Start: Deploy ECS Cluster Now

If you just need to deploy the ECS cluster:

1. **Go to:** GitHub Actions → Deploy Infrastructure (deploy-infra)
2. **Click:** "Run workflow"
3. **Set:**
   - Environment: `dev`
   - Module path: `04-ecs-fargate`
   - Action: `plan` (first time to review)
4. **Review the plan**, then run again with Action: `apply`

## Troubleshooting

### "Artifact not found" error
- The workflow will fall back to using the commit SHA as the image tag
- This is fine for deployment, but you may want to specify an image tag manually

### "Can't find action.yml" error
- This was fixed in the latest commit
- Make sure you've pulled the latest changes

### Infrastructure already exists
- Check `DEVOPS/live/dev/04-ecs-fargate/terraform.tfstate`
- If it exists, you can skip infrastructure deployment and go straight to application deployment

## Summary

**For first-time deployment:**
1. Deploy Infrastructure → `04-ecs-fargate` → `apply`
2. Deploy Application → `all` → (auto or manual)

**For subsequent deployments:**
- Just use "Deploy Application to ECS" workflow (auto-triggers on CI success)

