# Full-Stack Application with CI/CD

This project contains a full-stack application with a Python FastAPI backend, React frontend, and PostgreSQL database, orchestrated with Docker Compose and automated CI/CD using GitHub Actions.

## Project Structure

```
CI/
├── backend/          # Python FastAPI backend
│   ├── main.py      # FastAPI application
│   ├── database.py  # Database models and connection
│   ├── requirements.txt
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

## Backend API Endpoints

- `GET /health` - Health check endpoint (includes database connectivity check)
- `GET /api/hello` - Returns "hello from backend"
- `GET /api/greet/{user}` - Returns personalized greeting and stores it in database
- `GET /api/greetings` - Get all greetings (with pagination: `?skip=0&limit=10`)
- `GET /api/greetings/{user}` - Get all greetings for a specific user

## Local Development

### Prerequisites

- Docker and Docker Compose
- Python 3.11+ (for local backend development)
- Node.js 20+ (for local frontend development)

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

### Running Backend Locally

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload
```

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
pytest tests/test_main.py -v          # Unit tests
pytest tests/test_integration.py -v   # Integration tests (requires running services)
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
   - Uses pip caching for faster builds
   
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

