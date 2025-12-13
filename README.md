# Full-Stack Application with CI/CD

[![CI/CD Pipeline](https://github.com/orshalit/CI/actions/workflows/ci.yml/badge.svg)](https://github.com/orshalit/CI/actions/workflows/ci.yml)
[![CodeQL](https://github.com/orshalit/CI/actions/workflows/codeql.yml/badge.svg)](https://github.com/orshalit/CI/actions/workflows/codeql.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.11+](https://img.shields.io/badge/python-3.11+-blue.svg)](https://www.python.org/downloads/)
[![Node 20+](https://img.shields.io/badge/node-20+-green.svg)](https://nodejs.org/)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://www.docker.com/)

**Production-grade full-stack application** with enterprise CI/CD, comprehensive testing, security scanning, and automated versioning.

<!-- Test deployment trigger -->

## 🚀 Features

- ✅ **FastAPI Backend** with async support, rate limiting, and structured logging
- ✅ **React Frontend** with modern hooks, service layer, and error boundaries  
- ✅ **PostgreSQL Database** with connection pooling and health checks
- ✅ **Docker Multi-stage Builds** with non-root users and OCI labels
- ✅ **Comprehensive Testing** (unit, integration, E2E) with 90%+ coverage
- ✅ **Modern Linting** - Ruff (⚡ 10-100x faster), Black, ESLint, Prettier
- ✅ **Security Scanning** - Nightly scans with Bandit, Safety, Trivy, TruffleHog, CodeQL
- ✅ **Automated Versioning** with Git metadata and build timestamps
- ✅ **CI/CD Pipeline** with GitHub Actions and automated releases
- ✅ **Secure Deployment** - OIDC-based AWS deployment (no access keys)
- ✅ **Production-ready** configuration with all best practices

## 🚀 Deployment

This project includes a secure, automated deployment pipeline to AWS EC2 using GitHub Actions with OIDC authentication (no AWS access keys required).

### Deployment Features

- ✅ **OIDC Authentication**: Secure authentication to AWS without long-lived credentials
- ✅ **Automated Deployments**: Automatically deploys on successful CI for main branch
- ✅ **SSM-Based**: Uses AWS Systems Manager for secure command execution
- ✅ **Zero-Downtime**: Graceful container shutdown and health check verification
- ✅ **Automatic Rollback**: Rolls back to previous version on deployment failure
- ✅ **Branch Protection**: Enforces PR requirements and CI checks before deployment

### Quick Deployment Setup

1. **Apply Terraform Infrastructure** (creates OIDC provider and IAM role):
   ```bash
   cd ../DEVOPS/live/dev/03-github-oidc
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your GitHub org/repo
   terraform init && terraform apply
   ```

2. **Configure GitHub Secrets**:
   - `AWS_ROLE_ARN`: From Terraform output `github_actions_role_arn`
   - `AWS_REGION`: Your AWS region (e.g., `us-east-1`)

3. **EC2 Instance**:
   - Only requires SSM agent (already configured in Terraform)
   - Docker, Docker Compose, and deployment files are automatically installed/copied during deployment
   - No manual setup required!

4. **Deploy**:
   - Merge a PR to `main` → Automatic deployment after CI passes
   - Or manually trigger: Actions → Deploy to AWS → Run workflow

### Deployment Flow

```
PR Merged to main → CI Tests Pass → OIDC Auth → Find EC2 by Tags → 
SSM Run Command → Pull GHCR Images → Docker Compose Up → Health Checks → 
✅ Success (or Rollback on Failure)
```

### Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete deployment guide with setup instructions
- **[DEVOPS/live/dev/03-github-oidc/](../DEVOPS/live/dev/03-github-oidc/)** - Terraform configuration for OIDC infrastructure

## Project Structure

```
CI/
├── backend/          # Python FastAPI backend
│   ├── main.py      # FastAPI application
│   ├── database.py  # Database models and connection
│   ├── pyproject.toml  # Project definition and dependencies
│   ├── uv.lock      # Lockfile for reproducible builds
│   ├── .python-version  # Python version specification (3.11)
│   ├── Dockerfile   # Multistage Docker build
│   └── tests/       # Unit and integration tests
├── frontend/        # React frontend
│   ├── src/         # React source code
│   ├── package.json
│   ├── Dockerfile   # Multistage Docker build (Node + nginx)
│   └── tests/       # Jest tests
├── docker-compose.yml  # Service orchestration (backend, frontend, database)
└── .github/workflows/ci.yml  # GitHub Actions CI pipeline
```

## Services

The application consists of three containers:
- **Backend**: FastAPI application running on port 8000
- **Frontend**: React application served via nginx on port 3000
- **Database**: PostgreSQL 15 database on port 5432

## 📡 Backend API Endpoints

### Health & Info
- `GET /health` - Health check with database connectivity status
- `GET /version` - Build version, commit SHA, and metadata
- `GET /docs` - Interactive Swagger UI documentation
- `GET /redoc` - ReDoc API documentation

### Greetings API
- `GET /api/hello` - Simple hello endpoint
- `GET /api/greet/{user}` - Create personalized greeting (stored in database)
- `GET /api/greetings` - List all greetings with pagination (`?skip=0&limit=10`)
- `GET /api/greetings/{user}` - Get greetings for specific user

**Features:**
- Input validation and sanitization
- Rate limiting (configurable)
- Structured logging
- Error handling middleware
- CORS configuration
- Security headers

## Local Development

### Prerequisites

- Docker and Docker Compose
- Python 3.11+ (specified in `.python-version` and `pyproject.toml` - uv/pyenv/asdf will auto-detect)
- Node.js 20 (exact version required for consistency)
- Make (optional, for convenience commands)

**Note**: The `.python-version` file ensures consistent Python version across environments. uv, pyenv, and asdf automatically respect this file, making version management dynamic and resilient.

### Quick Setup

```bash
# Install all dependencies
make install

# Or manually:
# Backend (using uv - 10-100x faster than pip)
cd backend && uv venv && source .venv/bin/activate && uv sync
# Frontend  
cd frontend && npm ci
```

**Note:** This project uses [uv](https://docs.astral.sh/uv/) for Python package management, which provides 10-100x faster dependency resolution and installation compared to pip. The `uv.lock` file ensures reproducible builds across all environments.

### Ensuring CI Consistency

To avoid "works locally but fails in CI" issues:

1. **Install pre-commit hooks** (recommended):
   ```bash
   uv tool install pre-commit
   pre-commit install
   ```
   Or: `uv pip install pre-commit && pre-commit install`
   
   This automatically runs linters before each commit.

2. **Run local CI checks before pushing**:
   ```bash
   make ci-local
   ```
   Or use the script:
   ```bash
   bash scripts/test-local.sh
   ```

3. **Use Makefile commands** for consistency:
   ```bash
   make lint      # Run all linters
   make format    # Format all code
   make test      # Run all tests
   make ci-local  # Run full CI simulation
   ```

4. **Verify versions match CI**:
   ```bash
   make check-versions
   ```

**Important:** Always run `make ci-local` before pushing to ensure your code passes CI checks!

### Running with Docker Compose

```bash
cd CI
docker compose up --build
```

The services will be available at:
- Frontend: http://localhost:3000
- Backend: http://localhost:8000
- Database: localhost:5432 (user: appuser, password: apppassword, database: appdb)

All three containers (frontend, backend, database) will start automatically with proper health checks and dependencies.

### Check Version Information

```bash
# Backend version
curl http://localhost:8000/version | jq .

# Frontend version
curl http://localhost:3000/version.json | jq .

# Docker image labels
docker inspect ci-backend:dev --format='{{json .Config.Labels}}' | jq .
```

## 🧪 Testing

### Backend Tests

```bash
cd backend

# Run all tests
pytest

# Run unit tests only
pytest -m unit

# Run integration tests only
pytest -m integration

# Run with coverage
pytest --cov=. --cov-report=html

# Fast tests (exclude slow)
pytest -m "not slow"

# Using Makefile
make test-unit
make test-integration
make test-cov
```

**Test Structure:**
- `tests/conftest.py` - Shared fixtures and configuration
- `tests/test_main.py` - 40+ unit tests organized by endpoint
- `tests/test_integration.py` - 16+ integration tests with real services

**Coverage:** Target 90%+

### Quick Reference

```bash
# Install everything
make install

# Run CI checks locally (recommended before pushing)
make ci-local

# Individual commands
make lint          # Run all linters
make format        # Format all code  
make test          # Run all tests
make check-versions # Verify tool versions

# Backend only
make lint-backend
make format-backend
make test-backend

# Frontend only
make lint-frontend
make format-frontend
make test-frontend
```

### Frontend Tests

```bash
cd frontend

# Run tests
npm test

# Run with coverage
npm test -- --coverage

# CI mode (no watch)
npm test -- --watchAll=false --ci

# Fast tests
npm test:ci
```

**Test Structure:**
- `src/__tests__/App.test.js` - Component tests with React Testing Library
- `src/test-setup.js` - Global test setup
- Mocked services for isolation

**Coverage:** Target 80%+

### End-to-End Tests

```bash
# Start full stack
docker compose up -d

# Run integration tests against running services
cd backend
pytest -m integration --verbose

# Or use the API
curl http://localhost:8000/health
curl http://localhost:8000/api/hello
curl http://localhost:8000/api/greet/TestUser
```

## 🔍 Code Quality & Linting

### Backend (Python)

```bash
cd backend

# Run fast linters (< 1 second) ⚡
make lint

# Auto-fix issues
make format

# Security scans (runs nightly in CI)
make lint-security
```

**Tools:**
- **uv** ⚡ - Ultra-fast Python package manager (10-100x faster than pip)
- **Ruff** ⚡ - Lightning-fast linter (replaces Flake8, Pylint, isort)
- **Black** - Code formatting (100 char lines)
- **Bandit** - Security scanning (nightly in CI)
- **uv pip audit** - Built-in dependency security auditing (replaces Safety)

**Why uv?** 10-100x faster dependency resolution, universal lockfiles for reproducible builds, built-in security auditing, and replaces multiple tools (pip, pip-tools, pipx, poetry, pyenv, virtualenv) with a single unified tool.

**Why Ruff?** 10-100x faster than traditional linters, written in Rust, modern Python best practices.

### Frontend (JavaScript/React)

```bash
cd frontend

# Run linters
npm run lint          # ESLint
npm run format:check  # Prettier

# Auto-fix issues
npm run lint:fix      # Fix ESLint issues
npm run format        # Format with Prettier
```

**Tools:**
- **ESLint** - JavaScript/React linting
- **Prettier** - Code formatting

### Configuration Files

- Backend: `ruff.toml`, `pyproject.toml`
- Frontend: `.eslintrc.cjs`, `.prettierrc`

**Linting:** Ruff (Python) and ESLint (JavaScript) run automatically in CI and via pre-commit hooks.

## 🐳 Docker & Versioning

### Building Images with Versioning

```bash
# Using the build script (recommended)
chmod +x scripts/build.sh
./scripts/build.sh

# With specific version
./scripts/build.sh --version v1.2.3

# Build and push to registry
./scripts/build.sh --version v1.2.3 --registry ghcr.io/username --push

# Build specific service
./scripts/build.sh --backend-only
./scripts/build.sh --frontend-only
```

### Manual Docker Build

```bash
docker build \
  --build-arg BUILD_VERSION=v1.2.3 \
  --build-arg GIT_COMMIT=$(git rev-parse --short HEAD) \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  -t myapp-backend:v1.2.3 \
  backend/
```

### Version Information

Every Docker image includes:
- Application version (from git tag or auto-generated)
- Git commit SHA
- Build timestamp
- Runtime versions (Python/Node)
- OCI-compliant labels

**Versioning:** Images are tagged with semantic versions and Git commit SHAs automatically in CI.

## ⚙️ CI/CD Pipeline

The project uses GitHub Actions for automated CI/CD:

### Workflows

1. **`ci.yml`** - Main CI/CD pipeline
   - Code quality checks
   - Unit & integration tests (parallel)
   - Docker image building with versioning
   - End-to-end validation
   - Security scanning
   - Automated releases

2. **`pr-validation.yml`** - Fast PR feedback
   - Quick unit tests
   - Build verification
   - < 5 minutes for fast feedback

3. **`codeql.yml`** - Security analysis
   - Weekly security scans
   - Code quality analysis
   - Vulnerability detection

4. **`app-deploy-ec2.yml`** - Deploy to EC2 via SSM
   - Manual deployment to EC2 instances
   - OIDC authentication
   - Docker Compose orchestration

5. **`app-deploy-ecs.yml`** - Deploy to ECS Fargate
   - Automatic deployment after CI success
   - Terraform-based infrastructure updates
   - ECS service updates with new image tags

6. **`deploy-infra.yml`** - Infrastructure deployment
   - Manual Terraform operations (plan/apply/destroy)
   - VPC, OIDC, DNS/ACM, ECS Fargate management

### Pipeline Features

- ✅ Parallel job execution
- ✅ Test coverage reporting
- ✅ Automated versioning
- ✅ Docker layer caching
- ✅ Security scanning (Trivy, TruffleHog, CodeQL)
- ✅ Artifact publishing
- ✅ Automated changelog generation
- ✅ GitHub Container Registry integration

**Typical Run Time:** 10-15 minutes

**CI/CD:** Automated testing, building, and deployment via GitHub Actions workflows.

## 📚 Documentation

- **[applications/README.md](applications/README.md)** - Application structure and docker-compose usage
- **[DEVOPS/live/dev/03-github-oidc/](../DEVOPS/live/dev/03-github-oidc/)** - Terraform OIDC infrastructure

### Running Backend Locally

**Recommended: Using uv (Fast Python Package Manager)**

```bash
cd backend

# Quick setup (automated) - uses uv for 10-100x faster installs
./setup-venv.sh    # or: make venv

# Activate virtual environment (uv uses .venv by default)
source .venv/bin/activate

# Start the server
uvicorn main:app --reload
```

**Why uv?**
- ⚡ **10-100x faster** dependency resolution and installation
- 🔒 **Reproducible builds** with `uv.lock` file
- 🛡️ **Built-in security** auditing with `uv pip audit`
- 📦 **Single tool** replaces pip, pip-tools, pipx, poetry, pyenv, and virtualenv
- 🐍 **Python version management** - Automatically uses `.python-version` file (works with pyenv, asdf)

**Alternative: Direct Installation** (not recommended)

```bash
cd backend
uv sync  # Uses pyproject.toml and uv.lock for reproducible installs
uvicorn main:app --reload
```

> 📘 See [backend/VENV-SETUP.md](backend/VENV-SETUP.md) for detailed virtual environment documentation

### Running Frontend Locally

```bash
cd frontend
npm install
npm run dev
```

## Testing

### Backend Tests

```bash
cd backend
source .venv/bin/activate  # Activate virtual environment first (uv uses .venv)

# Run tests
pytest tests/test_main.py -v          # Unit tests
pytest tests/test_integration.py -v   # Integration tests (requires running services)

# Or use make commands
make test              # Run all tests
make test-unit         # Unit tests only
make test-integration  # Integration tests only
make test-cov          # Tests with coverage report
make install-frozen    # Install with frozen lockfile (for CI/reproducible builds)
make update            # Update dependencies and regenerate lockfile
```

### Frontend Tests

```bash
cd frontend
npm test
```

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) follows CI best practices:

1. **Backend Unit Tests** (runs first, in parallel with frontend tests)
   - Runs pytest unit tests with in-memory SQLite database
   - Uses uv with lockfile caching for faster builds (10-100x faster than pip)
   
2. **Frontend Unit Tests** (runs in parallel with backend tests)
   - Runs Jest tests with React Testing Library
   - Uses npm caching for faster builds

3. **Build Docker Images** (runs only after both test jobs pass)
   - Builds backend Docker image with caching
   - Builds frontend Docker image with caching
   - Uses GitHub Actions cache for Docker layer caching

4. **Start Docker Compose Services** (runs after build succeeds)
   - Builds and starts all three services (database, backend, frontend)
   - Waits for database to be healthy
   - Waits for backend to be healthy (depends on database)
   - Waits for frontend to be healthy (depends on backend)

5. **Integration Tests** (runs only after services are healthy)
   - Runs integration tests against the running Docker Compose environment
   - Tests all API endpoints including database operations
   - Verifies database connectivity and data persistence
   - Cleans up services after tests complete (even on failure)

## Docker Best Practices

- **Multistage builds**: Minimize image size by separating build and runtime stages
- **Minimal base images**: Uses `python:3.11-slim`, `nginx:alpine`, and `postgres:15-alpine`
- **Non-root users**: All containers run as non-root users for security
- **Health checks**: All services include health check configurations
- **Layer caching**: Optimized for Docker layer caching in CI/CD
- **Service dependencies**: Proper dependency ordering with health check conditions
- **Data persistence**: PostgreSQL data is persisted in a Docker volume

## Environment Variables

### Backend
- `DATABASE_URL`: PostgreSQL connection string (defaults to `postgresql://appuser:apppassword@localhost:5432/appdb`)
  - In Docker Compose: `postgresql://appuser:apppassword@database:5432/appdb`

### Frontend
- `VITE_BACKEND_URL`: Frontend environment variable for backend URL (defaults to `http://localhost:8000`)

### Testing
- `BACKEND_URL`: Backend URL for integration tests (defaults to `http://localhost:8000`)

