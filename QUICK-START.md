# Quick Start Guide

Fast reference for common operations.

## 🚀 First Time Setup

```bash
# Clone repository
git clone https://github.com/orshalit/CI.git
cd CI

# Start everything with Docker
docker compose up --build

# Access services
# - Frontend: http://localhost:3000
# - Backend API: http://localhost:8000
# - API Docs: http://localhost:8000/docs
```

## 🧪 Running Tests

```bash
# Backend (in WSL/Linux)
cd backend
pytest                    # All tests
pytest -m unit            # Unit tests only
pytest -m integration     # Integration tests only
make test-cov             # With coverage report

# Frontend (in WSL/Linux)
cd frontend
npm test                  # Interactive mode
npm test -- --coverage    # With coverage
npm run test:ci           # CI mode (no watch)
```

## 🐳 Docker Operations

```bash
# Build images with versioning
./scripts/build.sh

# Build specific version
./scripts/build.sh --version v1.2.3

# Start services
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down

# Clean everything
docker compose down -v
docker system prune -af
```

## 🔍 Check Status

```bash
# Service health
curl http://localhost:8000/health
curl http://localhost:3000/

# Version information
curl http://localhost:8000/version | jq .
curl http://localhost:3000/version.json | jq .

# Docker container status
docker compose ps

# View logs
docker compose logs backend --tail=50
docker compose logs frontend --tail=50
```

## 🛠️ Development

```bash
# Backend local development
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000

# Frontend local development
cd frontend
npm install
npm run dev  # Runs on port 5173 by default

# Database access
docker compose exec database psql -U appuser -d appdb
```

## 📊 View Coverage

```bash
# Backend
cd backend
pytest --cov=. --cov-report=html
# Open: htmlcov/index.html

# Frontend
cd frontend
npm test -- --coverage
# Open: coverage/lcov-report/index.html
```

## 🔐 Check Security

```bash
# Run security scans locally (if tools installed)
cd backend
bandit -r . -f json -o bandit-report.json
safety check

# Scan Docker images
docker scan ci-backend:latest
```

## 📦 Build & Release

```bash
# Tag a new version
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3

# Build and push to registry
./scripts/build.sh \
  --version v1.2.3 \
  --registry ghcr.io/username \
  --push
```

## 🐛 Troubleshooting

```bash
# View all container logs
docker compose logs

# Restart a specific service
docker compose restart backend

# Rebuild from scratch
docker compose down -v
docker compose build --no-cache
docker compose up

# Check database connection
docker compose exec database pg_isready -U appuser -d appdb

# Enter container shell
docker compose exec backend bash
docker compose exec frontend sh

# View Docker image labels
docker inspect ci-backend:latest \
  --format='{{json .Config.Labels}}' | jq .
```

## 🎯 Common Tasks

### Add a New API Endpoint

1. Add endpoint to `backend/main.py`
2. Add Pydantic schema to `backend/schemas.py`
3. Add tests to `backend/tests/test_main.py`
4. Run tests: `pytest -m unit`
5. Check coverage: `pytest --cov=.`

### Add a New Frontend Component

1. Create component in `frontend/src/components/`
2. Add tests in `frontend/src/__tests__/`
3. Run tests: `npm test`
4. Check coverage: `npm test -- --coverage`

### Update Dependencies

```bash
# Backend
cd backend
pip install --upgrade package-name
pip freeze > requirements.txt

# Frontend
cd frontend
npm update package-name
npm audit fix
```

### Clean Build Artifacts

```bash
# Backend
cd backend
find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null
find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null
rm -rf htmlcov .coverage

# Frontend
cd frontend
rm -rf node_modules coverage .jest-cache
npm ci

# Docker
docker system prune -af --volumes
```

## 📈 CI/CD Operations

```bash
# View CI status
gh run list

# View specific run
gh run view <run-id>

# Re-run failed jobs
gh run rerun <run-id>

# Download artifacts
gh run download <run-id>

# Trigger manual workflow
gh workflow run ci.yml
```

## 🔗 Useful URLs

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| Backend API | http://localhost:8000 |
| API Docs (Swagger) | http://localhost:8000/docs |
| API Docs (ReDoc) | http://localhost:8000/redoc |
| Health Check | http://localhost:8000/health |
| Version Info | http://localhost:8000/version |
| Frontend Version | http://localhost:3000/version.json |

## 📚 More Information

- **Full Testing Guide:** See `backend/tests/` and `frontend/src/__tests__/`
- **CI/CD Details:** See `CI-CD-GUIDE.md`
- **Versioning:** See `VERSIONING.md`
- **Docker:** See `DOCKER-IMPROVEMENTS.md`
- **Production Setup:** See `PRODUCTION-IMPROVEMENTS.md`

## 🆘 Need Help?

1. Check documentation files
2. Review GitHub Actions logs
3. Check Docker logs: `docker compose logs`
4. Open an issue with detailed information
5. Include versions, error messages, and logs

