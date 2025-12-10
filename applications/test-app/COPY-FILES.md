# Copy Files to test-app

The directories `backend/` and `frontend/` have been created with Dockerfiles.

## Next Step: Copy Source Files

You need to copy the actual source code files. Here are the commands:

### Windows PowerShell (Run from CI repository root):

```powershell
# Copy backend files (exclude venv and cache)
Get-ChildItem -Path backend -File -Recurse | Where-Object { 
    $_.FullName -notmatch 'venv|__pycache__|\.pytest_cache' 
} | Copy-Item -Destination { $_.FullName -replace '\\backend\\', '\applications\test-app\backend\' } -Force

# Or simpler - copy everything then clean up
Copy-Item -Path backend\* -Destination applications\test-app\backend\ -Recurse -Force
Remove-Item -Path applications\test-app\backend\venv -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path applications\test-app\backend\__pycache__ -Recurse -Force -ErrorAction SilentlyContinue

# Copy frontend files (exclude node_modules and build artifacts)
Copy-Item -Path frontend\* -Destination applications\test-app\frontend\ -Recurse -Force
Remove-Item -Path applications\test-app\frontend\node_modules -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path applications\test-app\frontend\dist -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path applications\test-app\frontend\.vite -Recurse -Force -ErrorAction SilentlyContinue
```

### Essential Files to Copy:

**Backend:**
- All `.py` files (main.py, config.py, database.py, etc.)
- requirements.txt
- pyproject.toml
- ruff.toml
- Any other config files

**Frontend:**
- src/ directory (all source files)
- package.json
- package-lock.json
- vite.config.js
- nginx.conf.template
- docker-entrypoint.sh
- Any other config files

## After Copying

Once files are copied, the structure should be:

```
applications/test-app/
├── backend/
│   ├── Dockerfile ✅ (already created)
│   ├── main.py
│   ├── requirements.txt
│   └── ... (all other backend files)
├── frontend/
│   ├── Dockerfile ✅ (already created)
│   ├── package.json
│   ├── src/
│   └── ... (all other frontend files)
└── services/
    ├── api.yaml ✅ (already configured)
    └── frontend.yaml ✅ (already configured)
```

Then CI will automatically detect and build:
- `ghcr.io/orshalit/test-app-backend`
- `ghcr.io/orshalit/test-app-frontend`

