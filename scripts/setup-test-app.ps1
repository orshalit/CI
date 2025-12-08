# PowerShell script to set up test-app with existing code
# Run from CI repository root

Write-Host "Setting up test-app application structure..." -ForegroundColor Green

# Create directories
$backendDir = "applications\test-app\backend"
$frontendDir = "applications\test-app\frontend"

New-Item -ItemType Directory -Force -Path $backendDir | Out-Null
New-Item -ItemType Directory -Force -Path $frontendDir | Out-Null

Write-Host "Copying backend files..." -ForegroundColor Yellow
Copy-Item -Path "backend\*" -Destination $backendDir -Recurse -Force -Exclude "venv","__pycache__",".pytest_cache"

Write-Host "Copying frontend files..." -ForegroundColor Yellow
Copy-Item -Path "frontend\*" -Destination $frontendDir -Recurse -Force -Exclude "node_modules",".vite","dist"

Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "Backend: $backendDir" -ForegroundColor Cyan
Write-Host "Frontend: $frontendDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "Service definitions are already configured to use:" -ForegroundColor Yellow
Write-Host "  - ghcr.io/orshalit/test-app-backend" -ForegroundColor Cyan
Write-Host "  - ghcr.io/orshalit/test-app-frontend" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next: CI will automatically detect and build these images on next run." -ForegroundColor Green

