# Next Steps: Deploy ECS Infrastructure and Services

Now that you've pushed the multi-application changes, here are the detailed steps to deploy:

---

## 📋 Quick Reference Summary

**Workflow Order:**
1. **Create ECS Service** → Generates `services.generated.tfvars` (creates PR in DEVOPS)
2. **Deploy Infrastructure** → Deploys ECS cluster and services (`plan` then `apply`)
3. **CI Pipeline** → Builds Docker images (automatic or manual trigger)
4. **Deploy Application** → Updates services with image tags

**Expected Timeline:**
- Step 1: ~2-3 minutes (workflow + PR review)
- Step 2: ~5-10 minutes (plan + apply)
- Step 3: ~10-15 minutes (build 4 images in parallel)
- Step 4: ~5-10 minutes (deploy + stabilize)
- **Total: ~25-40 minutes**

**Key Files:**
- Service Definitions: `applications/{app}/services/*.yaml`
- Generated Config: `DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars`
- Image Tags: `DEVOPS/live/dev/04-ecs-fargate/ci-service-tags.auto.tfvars`

---

## Detailed Steps

---

## Step 1: Generate Services Configuration ⭐ (DETAILED)

Generate the `services.generated.tfvars` file that Terraform will use to create ECS services.

### What This Step Does

The "Create / Update ECS Service" workflow:
1. **Reads your service YAML files** from:
   - `applications/legacy/services/*.yaml` (legacy services)
   - `applications/test-app/services/*.yaml` (test-app services)
2. **Validates** all service definitions:
   - Application names (lowercase, alphanumeric, hyphens only)
   - Required fields (`name`, `application`, `image_repo`)
   - ALB routing conflicts (no duplicate path patterns)
3. **Generates** `services.generated.tfvars` with:
   - Composite service keys: `"legacy::api"`, `"test-app::test-app-api"`
   - All service configuration (CPU, memory, ports, env vars, ALB config)
   - Application field for each service
4. **Creates a PR** in the DEVOPS repository with the generated file

### Detailed Workflow Steps

#### Using GitHub Actions (Recommended)

1. **Navigate to Workflow**:
   - Go to your CI repository on GitHub
   - Click **Actions** tab
   - Find **"Create / Update ECS Service (generate DEVOPS PR)"** in the workflow list
   - Click on it

2. **Run the Workflow**:
   - Click the **"Run workflow"** dropdown button (top right)
   - Select:
     - **Environment**: `dev` (only option available)
   - Click the green **"Run workflow"** button

3. **What Happens Behind the Scenes**:
   
   **Step 1: Checkout CI Repository**
   - Checks out your CI repository code
   - Gets access to `applications/` directory and service YAML files
   
   **Step 2: Set up Python**
   - Installs Python 3.11
   - Installs PyYAML for parsing YAML files
   
   **Step 3: Checkout DEVOPS Repository**
   - Checks out the DEVOPS repository (using SSH key from secrets)
   - This is where the generated file will be written
   
   **Step 4: Generate services.generated.tfvars**
   - Runs `generate_ecs_services_tfvars.py` script
   - Script does the following:
     ```
     1. Scans applications/legacy/services/ → finds api.yaml, frontend.yaml
     2. Scans applications/test-app/services/ → finds api.yaml, frontend.yaml
     3. Validates each service:
        - Checks application name format
        - Ensures image_repo is set
        - Validates ALB routing (no conflicts)
     4. Generates Terraform HCL format
     5. Writes to: DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars
     ```
   
   **Step 5: Create Pull Request**
   - Creates a new branch: `ci-generated/ecs-services-dev`
   - Commits the generated file
   - Opens a PR in DEVOPS repository
   - PR title: "chore: Sync ECS services for dev from CI specs"

4. **What to Expect in the Output**:
   
   The workflow will show:
   ```
   ✓ Wrote services map for environment 'dev' to:
     DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars
   
   Generated 4 service(s) across 2 application(s):
     legacy (2 service(s)), test-app (2 service(s))
   ```

5. **Review the Generated PR**:
   - Go to your DEVOPS repository
   - You'll see a new PR from branch `ci-generated/ecs-services-dev`
   - Review the `services.generated.tfvars` file
   - Verify it contains:
     - `legacy::api` service
     - `legacy::frontend` service
     - `test-app::test-app-api` service
     - `test-app::test-app-frontend` service
   - **Merge the PR** to make the file available for Terraform

6. **Verify the Generated File**:
   
   The generated file should look like:
   ```hcl
   services = {
     "legacy::api" = {
       container_image = "ghcr.io/orshalit/ci-backend"
       image_tag       = "latest"
       container_port  = 8000
       cpu             = 256
       memory          = 512
       desired_count   = 2
       application     = "legacy"
       
       environment_variables = {
         LOG_LEVEL = "INFO"
         DATABASE_URL = ""
       }
       
       alb = {
         alb_id            = "app_shared"
         listener_protocol = "HTTPS"
         listener_port     = 443
         path_patterns     = ["/legacy-api/*"]
         host_patterns     = ["app.dev.example.com"]
         health_check_path = "/health"
       }
     }
     
     "test-app::test-app-api" = {
       container_image = "ghcr.io/orshalit/test-app-backend"
       image_tag       = "latest"
       container_port  = 8000
       cpu             = 256
       memory          = 512
       desired_count   = 2
       application     = "test-app"
       
       environment_variables = {
         LOG_LEVEL = "INFO"
         DATABASE_URL = ""
       }
       
       alb = {
         alb_id            = "app_shared"
         listener_protocol = "HTTPS"
         listener_port     = 443
         path_patterns     = ["/test-api/*"]
         host_patterns     = ["app.dev.example.com"]
         health_check_path = "/health"
       }
     }
     
     # ... more services
   }
   ```

### Option B: Run Locally (For Testing)

If you want to test the generation locally before running the workflow:

```bash
# From CI repository root
python scripts/generate_ecs_services_tfvars.py \
  --base-dir . \
  --devops-dir ../DEVOPS \
  --environment dev
```

**What this does:**
- Reads service specs from `applications/` directories
- Generates `DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars`
- Prints summary of generated services
- **Does NOT create a PR** (you'd need to commit manually)

**Expected Output:**
```
✓ Wrote services map for environment 'dev' to:
  DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars

Generated 4 service(s) across 2 application(s):
  legacy (2 service(s)), test-app (2 service(s))
```

### Troubleshooting Step 1

**Error: "No service specs found"**
- ✅ Check that `applications/legacy/services/` exists
- ✅ Check that `applications/test-app/services/` exists
- ✅ Verify YAML files have `.yaml` or `.yml` extension

**Error: "Application name validation failed"**
- ✅ Ensure `application: legacy` and `application: test-app` in YAML files
- ✅ Check for uppercase letters (must be lowercase)
- ✅ Check for underscores or spaces (use hyphens only)

**Error: "ALB routing conflicts detected"**
- ✅ Check that path patterns are unique:
  - Legacy API: `/legacy-api/*` ✅
  - Test-App API: `/test-api/*` ✅
  - These are different, so no conflict

**Error: "Service missing required 'image_repo' field"**
- ✅ Ensure each service YAML has `image_repo: ghcr.io/orshalit/...`
- ✅ Check `applications/test-app/services/api.yaml` and `frontend.yaml`

**PR Not Created:**
- ✅ Check GitHub secrets: `DEVOPS_REPO_NAME`, `DEVOPS_REPO_KEY`
- ✅ Verify DEVOPS repository access permissions
- ✅ Check workflow logs for authentication errors

---

## Step 2: Review Generated Services ✅

After Step 1 completes and you merge the PR, verify the generated file.

### What to Check:

1. **File Location**:
   - In DEVOPS repository: `live/dev/04-ecs-fargate/services.generated.tfvars`
   - File should be committed to the `main` branch (after PR merge)

2. **Verify Services Are Included**:
   
   Open the file and check for:
   - ✅ `"legacy::api"` service block
   - ✅ `"legacy::frontend"` service block
   - ✅ `"test-app::test-app-api"` service block
   - ✅ `"test-app::test-app-frontend"` service block

3. **Verify Service Keys**:
   - Service keys use composite format: `"{application}::{name}"`
   - This prevents collisions between applications
   - Example: `legacy::api` vs `test-app::test-app-api` (different keys)

4. **Verify Application Fields**:
   - Each service should have `application = "legacy"` or `application = "test-app"`
   - This is used for resource naming: `dev-{app}-{service}-service`

5. **Verify Image Repositories**:
   - Legacy services: `ghcr.io/orshalit/ci-backend`, `ghcr.io/orshalit/ci-frontend`
   - Test-app services: `ghcr.io/orshalit/test-app-backend`, `ghcr.io/orshalit/test-app-frontend`

6. **Verify ALB Configuration**:
   - All services should have `alb` blocks
   - Path patterns should be unique:
     - Legacy API: `/legacy-api/*`
     - Legacy Frontend: `/legacy/*`
     - Test-App API: `/test-api/*`
     - Test-App Frontend: `/test/*`

### If Something Is Wrong:

- **Missing services**: Re-run Step 1 workflow
- **Wrong application names**: Fix YAML files, re-run Step 1
- **ALB conflicts**: Fix path patterns in YAML, re-run Step 1

---

## Step 3: Deploy ECS Infrastructure 🏗️ (DETAILED)

Deploy the ECS Fargate infrastructure that will run your services.

### What This Step Does

The "Deploy Infrastructure" workflow:
1. **Sets up Terraform** environment
2. **Initializes** Terraform in the ECS module directory
3. **Plans** or **Applies** infrastructure changes
4. **Creates** ECS resources (cluster, services, target groups, etc.)

### Detailed Workflow Steps

#### Phase 1: Plan (Review Before Deploying)

1. **Navigate to Workflow**:
   - Go to CI repository → **Actions** tab
   - Find **"Deploy Infrastructure (deploy-infra)"**
   - Click **"Run workflow"**

2. **Configure Plan Run**:
   - **Environment**: `dev`
   - **Module path**: `04-ecs-fargate`
   - **Action**: `plan` ⚠️ (Always plan first!)
   - Click **"Run workflow"**

3. **What Happens During Plan**:
   
   **Step 1: Terraform Setup**
   - Checks out DEVOPS repository
   - Sets up AWS authentication (OIDC)
   - Configures Terraform backend
   
   **Step 2: Terraform Init**
   - Downloads Terraform providers
   - Initializes backend (S3, DynamoDB for state)
   - Links to remote state
   
   **Step 3: Terraform Validate**
   - Validates Terraform syntax
   - Checks variable types
   - Verifies module structure
   
   **Step 4: Check for Required Files**
   - Verifies `terraform.tfvars` exists
   - Verifies `services.generated.tfvars` exists (from Step 1)
   
   **Step 5: Terraform Plan**
   - Reads all configuration files
   - Compares with current AWS state
   - Generates execution plan showing:
     - Resources to be created
     - Resources to be modified
     - Resources to be destroyed
   
4. **Review the Plan Output**:
   
   Look for:
   ```
   Plan: X to add, Y to change, Z to destroy
   
   # aws_ecs_cluster.this will be created
   + resource "aws_ecs_cluster" "this" {
       ...
     }
   
   # aws_ecs_service.services["legacy::api"] will be created
   + resource "aws_ecs_service" "services" {
       name = "dev-legacy-api-service"
       ...
     }
   
   # aws_ecs_service.services["test-app::test-app-api"] will be created
   + resource "aws_ecs_service" "services" {
       name = "dev-test-app-test-app-api-service"
       ...
     }
   ```
   
   **Verify:**
   - ✅ ECS cluster will be created (if not exists)
   - ✅ All 4 services will be created
   - ✅ Target groups will be created
   - ✅ CloudWatch log groups will be created
   - ✅ No unexpected destroys

5. **If Plan Looks Good**: Proceed to Phase 2 (Apply)
6. **If Plan Shows Issues**: 
   - Review the errors
   - Fix configuration
   - Re-run plan

#### Phase 2: Apply (Actually Deploy)

1. **Run Workflow Again**:
   - Same workflow: **"Deploy Infrastructure (deploy-infra)"**
   - **Environment**: `dev`
   - **Module path**: `04-ecs-fargate`
   - **Action**: `apply` ⚠️ (This will create/modify resources!)
   - Click **"Run workflow"**

2. **What Happens During Apply**:
   
   **Steps 1-4**: Same as Plan (setup, init, validate, check files)
   
   **Step 5: Terraform Apply**
   - Executes the plan
   - Creates/modifies AWS resources
   - Updates Terraform state
   - Shows progress for each resource
   
3. **Expected Output**:
   ```
   aws_ecs_cluster.this: Creating...
   aws_ecs_cluster.this: Creation complete after 2s
   
   aws_ecs_service.services["legacy::api"]: Creating...
   aws_ecs_service.services["legacy::api"]: Still creating... [10s elapsed]
   aws_ecs_service.services["legacy::api"]: Creation complete after 45s
   
   aws_ecs_service.services["test-app::test-app-api"]: Creating...
   ...
   
   Apply complete! Resources: 15 added, 0 changed, 0 destroyed.
   ```

4. **What Gets Created**:
   
   **ECS Resources:**
   - ✅ ECS Cluster: `dev-ecs-cluster`
   - ✅ 4 ECS Services:
     - `dev-legacy-api-service`
     - `dev-legacy-frontend-service`
     - `dev-test-app-test-app-api-service`
     - `dev-test-app-test-app-frontend-service`
   - ✅ 4 Task Definitions (one per service)
   - ✅ 4 Target Groups (for ALB routing)
   - ✅ 4 CloudWatch Log Groups:
     - `/ecs/dev/legacy/api`
     - `/ecs/dev/legacy/frontend`
     - `/ecs/dev/test-app/test-app-api`
     - `/ecs/dev/test-app/test-app-frontend`
   - ✅ Service Discovery entries (for inter-service communication)
   - ✅ Auto-scaling targets and policies (if configured)

5. **Verify Deployment**:
   
   After apply completes, check:
   - ✅ Workflow shows "Apply complete"
   - ✅ No errors in workflow logs
   - ✅ All services show as created

### Important Notes

⚠️ **First Time Deployment:**
- If ECS cluster doesn't exist, it will be created
- This may take 2-5 minutes
- Services will be created but may fail to start (images not built yet - that's Step 4)

⚠️ **Subsequent Deployments:**
- Only changed services will be updated
- Existing services continue running
- No downtime for unchanged services

### Troubleshooting Step 3

**Error: "services.generated.tfvars not found"**
- ✅ Ensure Step 1 PR was merged
- ✅ Verify file exists in DEVOPS repository
- ✅ Check file path: `live/dev/04-ecs-fargate/services.generated.tfvars`

**Error: "Terraform state locked"**
- ✅ Another deployment is in progress
- ✅ Wait for it to complete
- ✅ Or manually unlock if stuck (use Terraform force-unlock)

**Error: "Image pull error"**
- ✅ This is expected if images aren't built yet
- ✅ Continue to Step 4 to build images
- ✅ Then re-run apply or use Step 5 to update image tags

**Error: "ALB not found"**
- ✅ Ensure ALB infrastructure is deployed first
- ✅ Check that `alb_id: app_shared` exists in your infrastructure
- ✅ Deploy ALB module (`02-alb` or similar) before ECS

---

## Step 4: Build and Push Docker Images 🐳 (DETAILED)

Before services can run, Docker images must be built and pushed to the container registry.

### What This Step Does

The CI pipeline (`ci.yml`) automatically:
1. **Detects** which images need to be built
2. **Builds** Docker images from source code
3. **Tags** images with version (commit SHA or tag)
4. **Pushes** to GitHub Container Registry (GHCR)

### Detailed Process

#### Option A: Automatic (Recommended)

The CI pipeline runs automatically on:
- Push to `main` or `develop` branches
- Pull requests
- Version tags (`v*`)
- Manual workflow dispatch

1. **Trigger CI Pipeline**:
   
   **Method 1: Push a Commit**
   ```bash
   # Make a small change (or just add a comment)
   git commit --allow-empty -m "chore: trigger CI build"
   git push
   ```
   
   **Method 2: Manual Workflow Dispatch**
   - Go to **Actions** → **CI/CD Pipeline**
   - Click **"Run workflow"**
   - Select branch (usually `main`)
   - Click **"Run workflow"**

2. **What Happens During CI Build**:
   
   **Job 1: Detect App Images**
   - Runs `detect-app-images.py`
   - Scans `applications/` directory
   - Detects:
     - ✅ `applications/test-app/backend/` → needs `test-app-backend` image
     - ✅ `applications/test-app/frontend/` → needs `test-app-frontend` image
     - ✅ `backend/` (root) → needs `ci-backend` image (shared)
     - ✅ `frontend/` (root) → needs `ci-frontend` image (shared)
   - Generates build matrix:
     ```json
     {
       "include": [
         {"service": "backend", "type": "shared", "image_name": "ci-backend", ...},
         {"service": "frontend", "type": "shared", "image_name": "ci-frontend", ...},
         {"service": "backend", "type": "app-specific", "app": "test-app", "image_name": "test-app-backend", ...},
         {"service": "frontend", "type": "app-specific", "app": "test-app", "image_name": "test-app-frontend", ...}
       ]
     }
     ```
   
   **Job 2: Build Images (Parallel)**
   - For each image in the matrix:
     - Checks out code
     - Builds Docker image from:
       - `applications/test-app/backend/Dockerfile` → `test-app-backend`
       - `applications/test-app/frontend/Dockerfile` → `test-app-frontend`
       - `backend/Dockerfile` → `ci-backend`
       - `frontend/Dockerfile` → `ci-frontend`
     - Tags image with:
       - Commit SHA: `abc123def456`
       - Branch name: `main`
       - Latest tag (if on main branch)
     - Pushes to GHCR:
       - `ghcr.io/orshalit/test-app-backend:abc123def456`
       - `ghcr.io/orshalit/test-app-backend:latest`
       - `ghcr.io/orshalit/test-app-frontend:abc123def456`
       - `ghcr.io/orshalit/test-app-frontend:latest`
       - (Same for shared images)

3. **Verify Images Are Built**:
   
   Check workflow logs:
   - ✅ All 4 images should build successfully
   - ✅ Images pushed to GHCR
   - ✅ Image tags shown in logs
   
   Or check GHCR:
   - Go to GitHub → Your repository → **Packages**
   - You should see:
     - `test-app-backend`
     - `test-app-frontend`
     - `ci-backend`
     - `ci-frontend`

4. **Note the Image Tag**:
   - For latest builds: Use `latest` tag
   - For specific builds: Use commit SHA (e.g., `abc123def456`)
   - You'll need this for Step 5

#### Option B: Build Locally (For Testing)

If you want to test image builds locally:

```bash
# Build test-app-backend
cd applications/test-app/backend
docker build -t ghcr.io/orshalit/test-app-backend:latest .

# Build test-app-frontend  
cd ../frontend
docker build -t ghcr.io/orshalit/test-app-frontend:latest .

# Login to GHCR (if pushing)
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Push images (optional)
docker push ghcr.io/orshalit/test-app-backend:latest
docker push ghcr.io/orshalit/test-app-frontend:latest
```

### Troubleshooting Step 4

**Error: "No images to build"**
- ✅ Check that `applications/test-app/backend/` and `frontend/` directories exist
- ✅ Verify Dockerfiles exist in those directories
- ✅ Check `detect-app-images.py` output in workflow logs

**Error: "Docker build failed"**
- ✅ Check Dockerfile syntax
- ✅ Verify source files exist in directories
- ✅ Check build logs for specific error

**Error: "Image push failed"**
- ✅ Check GHCR permissions
- ✅ Verify GitHub token has `write:packages` permission
- ✅ Check if package already exists and you have access

---

## Step 5: Deploy Application Services 🚀 (DETAILED)

Deploy the actual application services with the correct Docker image tags.

### What This Step Does

The "Deploy Application to ECS" workflow:
1. **Filters** services by application
2. **Generates** image tag overrides
3. **Updates** ECS services with new image tags
4. **Waits** for services to become stable

### Detailed Workflow Steps

1. **Navigate to Workflow**:
   - Go to CI repository → **Actions** tab
   - Find **"Deploy Application to ECS (app-deploy-ecs)"**
   - Click **"Run workflow"**

2. **Configure Deployment**:
   - **Environment**: `dev`
   - **Application**: 
     - `test-app` (deploy only test-app services)
     - `legacy` (deploy only legacy services)
     - `all` (deploy all services)
   - **Image tag**: 
     - `latest` (use latest images)
     - Or specific tag: `abc123def456` (from CI build)
   - Click **"Run workflow"**

3. **What Happens During Deployment**:
   
   **Step 1: Get Terraform Path**
   - Determines path: `DEVOPS/live/dev/04-ecs-fargate`
   
   **Step 2: Filter Services by Application**
   - Runs `filter-services-by-application.py`
   - Reads `services.generated.tfvars`
   - Filters by application name
   - Example for `application: test-app`:
     - ✅ Includes: `test-app::test-app-api`, `test-app::test-app-frontend`
     - ❌ Excludes: `legacy::api`, `legacy::frontend`
   
   **Step 3: Generate Service Image Tag Overrides**
   - Creates `ci-service-tags.auto.tfvars`:
     ```hcl
     service_image_tags = {
       "test-app::test-app-api" = "latest"
       "test-app::test-app-frontend" = "latest"
     }
     ```
   - This overrides the default `image_tag = "latest"` for selected services
   
   **Step 4: Save ECS State (for rollback)**
   - Saves current image tags
   - Stores in workflow outputs
   - Enables rollback if needed
   
   **Step 5: Terraform Plan**
   - Shows what will change:
     ```
     # aws_ecs_service.services["test-app::test-app-api"] will be updated
       ~ task_definition = "arn:...:dev-test-app-test-app-api:123" -> "arn:...:dev-test-app-test-app-api:124"
     ```
   
   **Step 6: Terraform Apply**
   - Updates ECS services with new image tags
   - Creates new task definitions
   - Starts new tasks with new images
   - Stops old tasks (rolling update)
   
   **Step 7: Verify ECS Stability**
   - Waits for services to become stable
   - Checks that desired tasks are running
   - Verifies health checks pass
   - Timeout: 10 minutes (configurable)

4. **Expected Output**:
   ```
   Filtering services for application: test-app
   Found 2 services: test-app::test-app-api, test-app::test-app-frontend
   
   Generating image tag overrides...
   Created ci-service-tags.auto.tfvars
   
   Terraform Plan:
   Plan: 0 to add, 2 to change, 0 to destroy
   
   Terraform Apply:
   aws_ecs_service.services["test-app::test-app-api"]: Modifying...
   aws_ecs_service.services["test-app::test-app-api"]: Modifications complete after 45s
   
   Waiting for services to stabilize...
   ✅ Services are stable
   ```

5. **What Gets Updated**:
   - ✅ Task definitions (new revision with new image tag)
   - ✅ ECS services (point to new task definition)
   - ✅ Running tasks (gradually replaced with new tasks)
   - ✅ Old tasks (stopped after new ones are healthy)

6. **Rolling Update Process**:
   - ECS performs rolling updates:
     1. Starts new task with new image
     2. Waits for health check to pass
     3. Stops old task
     4. Repeats until all tasks are updated
   - **No downtime** if health checks pass
   - **Service may be unavailable** if health checks fail

### Deploying Multiple Applications

**Deploy All Applications:**
- Set **Application**: `all`
- All 4 services will be updated
- Uses same image tag for all

**Deploy One Application:**
- Set **Application**: `test-app` or `legacy`
- Only that application's services are updated
- Other services continue running unchanged

### Troubleshooting Step 5

**Error: "No services found for application"**
- ✅ Check application name spelling (must match exactly)
- ✅ Verify services exist in `services.generated.tfvars`
- ✅ Check service keys use correct format: `"{app}::{name}"`

**Error: "Services did not stabilize"**
- ✅ Check CloudWatch logs for errors
- ✅ Verify health check endpoint is working
- ✅ Check task definition for correct image
- ✅ Verify image exists in GHCR
- ✅ Check ECS service events for errors

**Error: "Image pull error"**
- ✅ Verify image exists: `ghcr.io/orshalit/test-app-backend:latest`
- ✅ Check GHCR permissions (ECS needs pull access)
- ✅ Verify image tag is correct
- ✅ Check ECS task execution role has permissions

**Services Stuck in "Pending"**
- ✅ Check CloudWatch logs
- ✅ Verify target group health checks
- ✅ Check if tasks are starting but failing health checks
- ✅ Review ECS service events for specific errors

---

## Step 6: Verify Deployment ✅ (DETAILED)

After deployment completes, verify everything is working correctly.

### 6.1: Check Services Are Running

#### Using AWS CLI:

```bash
# List all services in cluster
aws ecs list-services --cluster dev-ecs-cluster --region us-east-1

# Expected output:
# {
#   "serviceArns": [
#     "arn:aws:ecs:us-east-1:...:service/dev-ecs-cluster/dev-legacy-api-service",
#     "arn:aws:ecs:us-east-1:...:service/dev-ecs-cluster/dev-legacy-frontend-service",
#     "arn:aws:ecs:us-east-1:...:service/dev-ecs-cluster/dev-test-app-test-app-api-service",
#     "arn:aws:ecs:us-east-1:...:service/dev-ecs-cluster/dev-test-app-test-app-frontend-service"
#   ]
# }

# Check service status
aws ecs describe-services \
  --cluster dev-ecs-cluster \
  --services dev-legacy-api-service dev-test-app-test-app-api-service \
  --region us-east-1 \
  --query 'services[*].[serviceName,status,runningCount,desiredCount]' \
  --output table
```

**Expected Output:**
```
|  DescribeServices  |
+---------------------+
|  dev-legacy-api-service | ACTIVE |  2  |  2  |
|  dev-test-app-test-app-api-service | ACTIVE |  2  |  2  |
```

#### Using AWS Console:

1. Go to **ECS** → **Clusters** → `dev-ecs-cluster`
2. Click **Services** tab
3. Verify you see 4 services:
   - ✅ `dev-legacy-api-service` - Status: ACTIVE, Running: 2/2
   - ✅ `dev-legacy-frontend-service` - Status: ACTIVE, Running: 2/2
   - ✅ `dev-test-app-test-app-api-service` - Status: ACTIVE, Running: 2/2
   - ✅ `dev-test-app-test-app-frontend-service` - Status: ACTIVE, Running: 2/2

### 6.2: Check Service Health

#### Using Diagnostic Script:

```bash
# From CI repository
./scripts/diagnose-ecs-deployment.sh
```

**What it checks:**
- ✅ Service status (running, desired count)
- ✅ Task status (running, stopped)
- ✅ Target group health
- ✅ ALB listener rules
- ✅ CloudWatch logs

**Expected Output:**
```
=== ECS Deployment Diagnostics ===

Service: dev-legacy-api-service
  Status: ACTIVE
  Running: 2/2
  Target Group: healthy (2/2)
  Log Group: /ecs/dev/legacy/api

Service: dev-test-app-test-app-api-service
  Status: ACTIVE
  Running: 2/2
  Target Group: healthy (2/2)
  Log Group: /ecs/dev/test-app/test-app-api
```

#### Manual Health Checks:

```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region us-east-1

# Should show all targets as "healthy"
```

### 6.3: Check CloudWatch Logs

```bash
# View logs for a service
aws logs tail /ecs/dev/test-app/test-app-api --follow --region us-east-1

# Or in AWS Console:
# CloudWatch → Log groups → /ecs/dev/test-app/test-app-api
```

**What to look for:**
- ✅ Application starting successfully
- ✅ No error messages
- ✅ Health check endpoints responding
- ✅ Database connections (if configured)

### 6.4: Test API Endpoints

#### Test Legacy API:

```bash
# Health check
curl https://app.dev.example.com/legacy-api/health

# Expected: {"status":"healthy","database":"connected"}

# Hello endpoint
curl https://app.dev.example.com/legacy-api/api/hello

# Expected: {"message":"hello from backend"}
```

#### Test Test-App API:

```bash
# Health check
curl https://app.dev.example.com/test-api/health

# Expected: {"status":"healthy","database":"connected"}

# Hello endpoint
curl https://app.dev.example.com/test-api/api/hello

# Expected: {"message":"hello from backend"}
```

**Note**: Replace `app.dev.example.com` with your actual ALB DNS name or domain.

### 6.5: Test Frontend Applications

#### Access in Browser:

- **Legacy Frontend**: `https://app.dev.example.com/legacy/`
- **Test-App Frontend**: `https://app.dev.example.com/test/`

**What to verify:**
- ✅ Page loads without errors
- ✅ Health status shows "healthy"
- ✅ API calls work (hello button, greet functionality)
- ✅ No console errors in browser DevTools

### 6.6: Verify ALB Routing

```bash
# List ALB listeners
aws elbv2 describe-listeners \
  --load-balancer-arn <alb-arn> \
  --region us-east-1

# List listener rules
aws elbv2 describe-rules \
  --listener-arn <listener-arn> \
  --region us-east-1
```

**Verify rules exist for:**
- ✅ `/legacy-api/*` → legacy-api target group
- ✅ `/legacy/*` → legacy-frontend target group
- ✅ `/test-api/*` → test-app-api target group
- ✅ `/test/*` → test-app-frontend target group

### 6.7: Verify Service Discovery

```bash
# Check Cloud Map service discovery
aws servicediscovery list-services --region us-east-1

# Should see entries for each service
```

**Expected:**
- Services discoverable by name
- DNS names resolvable within VPC
- Inter-service communication possible

### Troubleshooting Step 6

**Services Show 0 Running Tasks:**
- ✅ Check CloudWatch logs for errors
- ✅ Verify image exists and is pullable
- ✅ Check task definition for correct image
- ✅ Review ECS service events

**Target Group Shows Unhealthy:**
- ✅ Check health check path is correct
- ✅ Verify application responds to health endpoint
- ✅ Check security groups allow traffic
- ✅ Verify tasks are running

**404 Errors on Endpoints:**
- ✅ Check ALB listener rules exist
- ✅ Verify path patterns match
- ✅ Check host patterns (if configured)
- ✅ Verify target groups are attached to rules

**Frontend Can't Connect to Backend:**
- ✅ Check `BACKEND_API_URL` environment variable
- ✅ Verify backend is accessible
- ✅ Check CORS configuration
- ✅ Review browser console for errors

---

## Troubleshooting

### Issue: Services not appearing in generated tfvars

**Check:**
- Service YAML files are in `applications/{app}/services/`
- `application` field matches directory name
- `image_repo` is specified in service definitions

### Issue: Terraform plan shows no changes

**Check:**
- `services.generated.tfvars` exists in `DEVOPS/live/dev/04-ecs-fargate/`
- File was committed to DEVOPS repository
- Terraform is reading the file (check var files list)

### Issue: Image pull errors

**Check:**
- Images are built and pushed to GHCR
- Image names match `image_repo` in service definitions:
  - `ghcr.io/orshalit/test-app-backend` for test-app backend
  - `ghcr.io/orshalit/test-app-frontend` for test-app frontend
- GHCR permissions allow ECS to pull images

### Issue: ALB routing conflicts

**Check:**
- Path patterns are unique per ALB
- No duplicate `host_pattern + path_pattern` combinations
- Run PR validation to catch conflicts early

---

## Quick Reference

### Workflow Order:

1. **Create ECS Service** → Generates `services.generated.tfvars`
2. **Deploy Infrastructure** → Deploys ECS cluster and services (plan first, then apply)
3. **CI Pipeline** → Builds Docker images
4. **Deploy Application** → Updates services with image tags

### Key Files:

- **Service Definitions**: `applications/{app}/services/*.yaml`
- **Generated Config**: `DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars`
- **Image Tags Override**: `DEVOPS/live/dev/04-ecs-fargate/ci-service-tags.auto.tfvars`

---

## Expected Result

After completing all steps, you should have:

✅ ECS cluster running  
✅ 4 services deployed:
   - `dev-legacy-api-service`
   - `dev-legacy-frontend-service`
   - `dev-test-app-test-app-api-service`
   - `dev-test-app-test-app-frontend-service`  
✅ All services healthy and running  
✅ ALB routing working for all paths  
✅ CloudWatch logs for all services  

---

## Next: Testing

Once deployed, test:
1. Health endpoints for both applications
2. API endpoints
3. Frontend applications
4. Verify logs in CloudWatch
5. Test auto-scaling (if configured)

