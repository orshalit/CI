# Workflows and Actions Behavior with Multi-Application Structure

This document explains what each workflow and action will do now that we have:
1. Multi-application support (`applications/legacy/`, `applications/test-app/`)
2. App-specific code directories (`applications/test-app/backend/`, `applications/test-app/frontend/`)
3. Updated workflows that detect and handle these structures

---

## 🔄 CI/CD Pipeline (`ci.yml`)

### What It Does Now:

1. **Change Detection**:
   - Triggers on changes to `backend/**`, `frontend/**`, or `applications/**`
   - Detects when app-specific code changes (e.g., `applications/test-app/backend/main.py`)

2. **Dynamic Image Detection** (`detect-app-images` job):
   - Scans `applications/` directory for app-specific code
   - Detects `applications/test-app/backend/` → builds `test-app-backend` image
   - Detects `applications/test-app/frontend/` → builds `test-app-frontend` image
   - Always includes shared images (`ci-backend`, `ci-frontend`) if root directories exist

3. **Build Matrix**:
   - **Before**: Only built `ci-backend` and `ci-frontend`
   - **Now**: Builds:
     - `ghcr.io/orshalit/ci-backend` (shared)
     - `ghcr.io/orshalit/ci-frontend` (shared)
     - `ghcr.io/orshalit/test-app-backend` (app-specific)
     - `ghcr.io/orshalit/test-app-frontend` (app-specific)

4. **Code Quality & Testing**:
   - Runs linting, formatting, and tests on all changed code
   - Tests both shared and app-specific code

### Example Scenario:
- **Change**: `applications/test-app/backend/main.py` is modified
- **Result**: 
  - CI triggers
  - Only `test-app-backend` image is built (not shared backend)
  - Tests run on `applications/test-app/backend/`

---

## 🚀 Application Deployment (`app-deploy-ecs.yml`)

### What It Does Now:

1. **Change Detection**:
   - **Before**: Only detected changes in `backend/**` or `frontend/**`
   - **Now**: Also detects changes in:
     - `applications/**/backend/**` (app-specific backend changes)
     - `applications/**/frontend/**` (app-specific frontend changes)

2. **Application Filtering**:
   - Accepts `application` input parameter (e.g., `legacy`, `test-app`, `all`)
   - Uses `filter-services-by-application.py` to filter services
   - Only updates services for the specified application

3. **Service Image Tag Overrides**:
   - Generates `service_image_tags` map with composite keys: `"legacy::api"`, `"test-app::test-app-api"`
   - Only includes services for the selected application

### Example Scenarios:

**Scenario 1: Deploy test-app only**
- **Input**: `application: test-app`
- **Result**: 
  - Only `test-app::test-app-api` and `test-app::test-app-frontend` services updated
  - Uses images: `ghcr.io/orshalit/test-app-backend:latest`, `ghcr.io/orshalit/test-app-frontend:latest`

**Scenario 2: Change in test-app backend code**
- **Change**: `applications/test-app/backend/main.py` modified
- **Workflow Run**: Triggers `app-deploy-ecs.yml`
- **Result**: 
  - Detects change in `applications/**/backend/**`
  - Deploys only test-app services (if workflow_run triggered)

**Scenario 3: Deploy all applications**
- **Input**: `application: all`
- **Result**: 
  - All services updated: `legacy::api`, `legacy::frontend`, `test-app::test-app-api`, `test-app::test-app-frontend`

---

## 🔍 CodeQL Analysis (`codeql.yml`)

### What It Does Now:

1. **Path Filtering**:
   - **Before**: Only scanned `backend/**` and `frontend/**`
   - **Now**: Also scans `applications/**` for security vulnerabilities

2. **Code Scanning**:
   - Scans shared code: `backend/`, `frontend/`
   - Scans app-specific code: `applications/test-app/backend/`, `applications/test-app/frontend/`
   - Detects security issues in all application code

### Example Scenario:
- **Change**: `applications/test-app/backend/main.py` added
- **Result**: CodeQL scans the new file for security vulnerabilities

---

## 🔒 Security Scan (`security-scan.yml`)

### What It Does Now:

1. **Multi-Directory Scanning**:
   - **Before**: Only scanned `backend/` and `frontend/`
   - **Now**: Scans:
     - Shared: `backend/`, `frontend/`
     - App-specific: `applications/*/backend/`, `applications/*/frontend/`

2. **Separate Reports**:
   - Generates separate artifacts for shared vs app-specific code
   - `bandit-security-report-shared` and `bandit-security-report-apps`
   - `safety-security-report-shared` and `safety-security-report-apps`
   - `npm-audit-report-shared` and `npm-audit-report-apps`

3. **Bandit Scanning**:
   - Scans `backend/` for Python security issues
   - Scans all `applications/*/backend/` directories
   - Reports issues per application

4. **Safety Scanning**:
   - Checks `backend/requirements.txt` for vulnerabilities
   - Checks all `applications/*/backend/requirements.txt` files
   - Reports per application

5. **NPM Audit**:
   - Scans `frontend/package.json` for vulnerabilities
   - Scans all `applications/*/frontend/package.json` files
   - Reports per application

### Example Scenario:
- **Nightly Run**: Security scan workflow runs
- **Result**: 
  - Scans `backend/` → shared report
  - Scans `applications/test-app/backend/` → app-specific report
  - Scans `frontend/` → shared report
  - Scans `applications/test-app/frontend/` → app-specific report
  - All reports uploaded as separate artifacts

---

## ✅ PR Validation (`pr-validation.yml`)

### What It Does Now:

1. **Service Spec Validation**:
   - Detects changes in `services/` or `applications/` directories
   - Runs `generate_ecs_services_tfvars.py` to validate:
     - Application naming (lowercase, alphanumeric, hyphens only)
     - ALB routing conflicts (no duplicate path patterns)
     - Required fields (`name`, `application`, `image_repo`)
     - Service name collisions across applications

2. **Early Error Detection**:
   - Catches configuration errors before merge
   - Prevents invalid service definitions from being deployed

### Example Scenario:
- **PR**: Adds new service with duplicate path pattern
- **Result**: 
  - Validation fails with error: "Path pattern '/test-api/*' is used by multiple services"
  - PR cannot be merged until fixed

---

## 🏗️ Create ECS Service (`create-ecs-service.yml`)

### What It Does Now:

1. **Service Generation**:
   - Loads services from both `services/` (legacy) and `applications/*/services/`
   - Generates `services.generated.tfvars` with composite keys: `"legacy::api"`, `"test-app::test-app-api"`
   - Validates all service definitions

2. **Multi-Application Support**:
   - Handles any number of applications
   - Ensures no service name collisions
   - Validates ALB routing conflicts

### Example Scenario:
- **Change**: New service added to `applications/test-app/services/api.yaml`
- **Result**: 
  - Service included in generated tfvars as `"test-app::test-app-api"`
  - Terraform can deploy it alongside legacy services

---

## 🔄 Actions (All Dynamic)

### `ecs-rollback`
- **Behavior**: Uses Terraform outputs to get all service keys dynamically
- **Works With**: Any number of applications
- **Example**: Rolls back all services (legacy and test-app) to previous image tag

### `ecs-diagnostics`
- **Behavior**: Iterates through all services from Terraform outputs
- **Works With**: Any number of applications
- **Example**: Diagnoses issues in all services across all applications

### `verify-ecs-stability`
- **Behavior**: Waits for all services to become stable
- **Works With**: Any number of applications
- **Example**: Verifies both legacy and test-app services are stable

### `verify-load-balancer`
- **Behavior**: Checks all ALBs and their target groups
- **Works With**: Any number of applications
- **Example**: Verifies ALB routing for all services (legacy and test-app)

### `save-ecs-state`
- **Behavior**: Saves current image tags for all services
- **Works With**: Any number of applications
- **Example**: Saves state for all services before deployment

---

## 📊 Complete Flow Example

### Scenario: Developer adds new feature to test-app backend

1. **Developer commits**: `applications/test-app/backend/main.py` modified

2. **CI Pipeline (`ci.yml`)**:
   - ✅ Detects change in `applications/**`
   - ✅ Runs `detect-app-images.py`
   - ✅ Builds only `test-app-backend` image (not shared backend)
   - ✅ Runs tests on `applications/test-app/backend/`
   - ✅ Pushes image: `ghcr.io/orshalit/test-app-backend:abc123`

3. **PR Validation (`pr-validation.yml`)**:
   - ✅ Validates service definitions
   - ✅ Checks for ALB routing conflicts
   - ✅ Ensures `image_repo` is set correctly

4. **After Merge - Deployment (`app-deploy-ecs.yml`)**:
   - ✅ Detects change in `applications/**/backend/**`
   - ✅ Developer selects `application: test-app`
   - ✅ Filters services: only `test-app::test-app-api` and `test-app::test-app-frontend`
   - ✅ Updates `service_image_tags` with new image tag
   - ✅ Terraform applies changes
   - ✅ Only test-app services updated (legacy services unchanged)

5. **Security Scan (Nightly)**:
   - ✅ Scans `applications/test-app/backend/` for vulnerabilities
   - ✅ Generates separate report for test-app
   - ✅ Uploads as artifact: `bandit-security-report-apps`

---

## 🎯 Key Benefits

1. **Isolation**: Changes to one application don't affect others
2. **Efficiency**: Only builds/deploys what changed
3. **Scalability**: Can add unlimited applications without workflow changes
4. **Safety**: Validation prevents configuration errors
5. **Flexibility**: Applications can use shared or app-specific code

---

## 🔍 Verification

To verify everything works:

1. **Check CI builds**: Look for `test-app-backend` and `test-app-frontend` in build matrix
2. **Check deployments**: Verify `application: test-app` only updates test-app services
3. **Check security scans**: Verify separate reports for app-specific code
4. **Check PR validation**: Try adding a duplicate path pattern and see it fail

---

## 📝 Summary

All workflows and actions are now:
- ✅ **Dynamic**: No hardcoded application names
- ✅ **Multi-Application Aware**: Handle any number of applications
- ✅ **Efficient**: Only process what changed
- ✅ **Safe**: Validate configurations before deployment
- ✅ **Scalable**: Add new applications without modifying workflows

