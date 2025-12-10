# Applications Directory

This directory contains all applications in the monorepo. Each application is self-contained with its own code, Dockerfiles, and docker-compose configuration.

## Structure

```
applications/
├── <app-name>/
│   ├── docker-compose.yml          # Generated: App-specific services
│   ├── docker-compose.prod.yml     # Generated: Production overrides (optional)
│   ├── backend/                    # Backend service code
│   │   └── Dockerfile
│   └── frontend/                   # Frontend service code
│       └── Dockerfile
└── .docker-compose.template.yml    # Template showing structure
```

## Generating Docker Compose Files

**Docker Compose files are auto-generated** - do not create them manually!

### Generate for a specific application:

```bash
# From repository root
./scripts/generate-app-compose.sh <app-name>

# Example: Generate for test-app
./scripts/generate-app-compose.sh test-app
```

### Generate production overrides:

```bash
./scripts/generate-app-compose.sh <app-name> --prod
```

### Generate for all applications:

```bash
./scripts/generate-app-compose.sh
```

## Usage

### Development - Single Application

**From repository root:**
```bash
docker compose -f docker-compose.base.yml \
               -f applications/<app-name>/docker-compose.yml up --build
```

**From application directory:**
```bash
cd applications/<app-name>
docker compose -f ../../docker-compose.base.yml \
               -f docker-compose.yml up --build
```

### Development - Multiple Applications

```bash
docker compose -f docker-compose.base.yml \
               -f applications/app1/docker-compose.yml \
               -f applications/app2/docker-compose.yml up
```

### All Applications (CI/CD)

```bash
docker compose -f docker-compose.base.yml \
               -f applications/*/docker-compose.yml up --build
```

## What Gets Generated?

The script automatically detects:
- ✅ `backend/` directory with `Dockerfile` → Creates `{app-name}-backend` service
- ✅ `frontend/` directory with `Dockerfile` → Creates `{app-name}-frontend` service
- ✅ Environment variables with app-specific prefixes
- ✅ Port mappings (configurable via env vars)
- ✅ Health checks and dependencies

## Environment Variables

Each application uses prefixed environment variables:

```bash
# Backend port (default: 8000)
<APP_NAME>_BACKEND_PORT=8000

# Frontend port (default: 3000)
<APP_NAME>_FRONTEND_PORT=3000

# Backend URL for frontend
<APP_NAME>_BACKEND_URL=http://<app-name>-backend:8000

# Production images
<APP_NAME>_BACKEND_IMAGE=ghcr.io/orshalit/<app-name>-backend:latest
<APP_NAME>_FRONTEND_IMAGE=ghcr.io/orshalit/<app-name>-frontend:latest
```

**Example for `test-app`:**
```bash
TEST_APP_BACKEND_PORT=8000
TEST_APP_FRONTEND_PORT=3000
TEST_APP_BACKEND_URL=http://test-app-backend:8000
```

## Adding a New Application

1. **Create application directory:**
   ```bash
   mkdir -p applications/new-app/{backend,frontend}
   ```

2. **Add Dockerfiles:**
   - `applications/new-app/backend/Dockerfile`
   - `applications/new-app/frontend/Dockerfile`

3. **Generate docker-compose:**
   ```bash
   ./scripts/generate-app-compose.sh new-app
   ```

4. **Start the application:**
   ```bash
   docker compose -f docker-compose.base.yml \
                  -f applications/new-app/docker-compose.yml up --build
   ```

## Shared Infrastructure

The `docker-compose.base.yml` file (in repository root) contains shared services:
- **Database** (PostgreSQL)
- **Redis** (if needed)
- **Message Queues** (if needed)
- **Networks** and **Volumes**

These are automatically included when you use:
```bash
docker compose -f docker-compose.base.yml -f applications/.../docker-compose.yml up
```

## Best Practices

1. ✅ **Always regenerate** compose files when adding/removing backend/frontend directories
2. ✅ **Don't edit** generated compose files manually - regenerate instead
3. ✅ **Use environment variables** for port conflicts between apps
4. ✅ **Keep applications self-contained** - all app code in `applications/<app-name>/`
5. ✅ **Use per-app compose files** for development, base + all for CI/CD

## Troubleshooting

**Port conflicts?**
```bash
# Set custom ports via environment variables
export NEW_APP_BACKEND_PORT=8001
export NEW_APP_FRONTEND_PORT=3001
docker compose -f docker-compose.base.yml \
               -f applications/new-app/docker-compose.yml up
```

**Compose file out of date?**
```bash
# Regenerate it
./scripts/generate-app-compose.sh <app-name>
```

**Need to see what will be generated?**
```bash
# Check the template
cat applications/.docker-compose.template.yml
```

## See Also

- `DOCKER-COMPOSE-ARCHITECTURE.md` - Architecture overview
- `DOCKER-COMPOSE-FILE-LOCATION.md` - File location best practices
- `scripts/generate-app-compose.sh` - Generation script

