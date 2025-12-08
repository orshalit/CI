# Test-App Setup

This directory should contain copies of the backend and frontend code from the root directories.

## Quick Setup

Run this from the CI repository root:

```bash
# Windows PowerShell
Copy-Item -Path backend\* -Destination applications\test-app\backend\ -Recurse -Force
Copy-Item -Path frontend\* -Destination applications\test-app\frontend\ -Recurse -Force

# Or manually copy the directories
```

## What's Needed

The following files/directories need to be copied:

### Backend
- All Python files (`.py`)
- `requirements.txt`
- `Dockerfile`
- `pyproject.toml` (if exists)
- Any other config files

### Frontend  
- All source files (`src/`)
- `package.json`
- `package-lock.json`
- `Dockerfile`
- `vite.config.js`
- `nginx.conf.template` (if exists)
- `docker-entrypoint.sh` (if exists)
- Any other config files

## After Copying

Once files are copied, the CI workflow will automatically:
1. Detect `applications/test-app/backend/` and `applications/test-app/frontend/`
2. Build images: `test-app-backend` and `test-app-frontend`
3. Deploy using the service definitions in `services/`

## Service Definitions

The service definitions are already updated to use:
- `image_repo: ghcr.io/orshalit/test-app-backend`
- `image_repo: ghcr.io/orshalit/test-app-frontend`

