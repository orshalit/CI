import json
import logging
import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path as PathLib

from fastapi import Depends, FastAPI, HTTPException, Path, Query, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from config import settings
from database import Greeting, database_available, get_db, init_db
from logging_config import setup_logging
from middleware import (
    ErrorHandlingMiddleware,
    LoggingMiddleware,
    RequestIdMiddleware,
    SecurityHeadersMiddleware,
)
from schemas import (
    GreetingResponse,
    GreetingsListResponse,
    HealthResponse,
    HelloResponse,
    UserGreetingsResponse,
    VersionResponse,
)


# Setup logging
setup_logging(log_level=settings.LOG_LEVEL, log_format=settings.LOG_FORMAT)
logger = logging.getLogger(__name__)

# Initialize rate limiter
limiter = Limiter(key_func=get_remote_address)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan event handler for startup and shutdown"""
    # Startup: Initialize database only if available and not in testing mode
    if not settings.TESTING and database_available:
        logger.info("Initializing database...")
        try:
            init_db()
            logger.info("Database initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize database: {e}", exc_info=True)
            raise
    elif not settings.TESTING and not database_available:
        logger.warning(
            "Database is not available (DATABASE_URL is empty). "
            "Application will run without database features."
        )
    yield
    # Shutdown: cleanup if needed
    logger.info("Shutting down application...")


app = FastAPI(
    title=settings.API_TITLE,
    version=settings.API_VERSION,
    # Deployment test#11 - verify downstream jobs and debug deploy
    lifespan=lifespan,
    docs_url="/docs" if not settings.TESTING else None,
    redoc_url="/redoc" if not settings.TESTING else None,
)

# Add rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Add middleware (order matters - last added is first executed)
# RequestIdMiddleware should be first so request_id is available for all
# other middleware
app.add_middleware(ErrorHandlingMiddleware)
app.add_middleware(LoggingMiddleware)
app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestIdMiddleware)

# Enable CORS with environment-based configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.get_cors_origins(),
    allow_credentials=settings.CORS_ALLOW_CREDENTIALS,
    allow_methods=settings.CORS_ALLOW_METHODS,
    allow_headers=settings.CORS_ALLOW_HEADERS,
)


@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["health"],
    summary="Health check endpoint",
    description="Check the health status of the API and database connectivity (DEPLOY-TEST-1)",
)
async def health_check():
    """Health check endpoint with database connectivity check and version info"""
    # Get version info for response
    version_file = PathLib("/app/version.json")
    version_info = {"version": None, "commit": None}
    
    if version_file.exists():
        try:
            with open(version_file) as f:
                version_data = json.load(f)
                version_info["version"] = version_data.get("version", os.getenv("APP_VERSION"))
                version_info["commit"] = version_data.get("commit", os.getenv("GIT_COMMIT"))
        except (json.JSONDecodeError, OSError):
            version_info["version"] = os.getenv("APP_VERSION")
            version_info["commit"] = os.getenv("GIT_COMMIT")
    else:
        version_info["version"] = os.getenv("APP_VERSION")
        version_info["commit"] = os.getenv("GIT_COMMIT")
    
    # Check if database is available
    if not database_available:
        return HealthResponse(
            status="healthy", 
            database="unavailable",
            version=version_info["version"],
            commit=version_info["commit"]
        )

    # Test database connection if available
    try:
        db = next(get_db())
        db.execute(text("SELECT 1"))
        db.close()
        return HealthResponse(
            status="healthy", 
            database="connected",
            version=version_info["version"],
            commit=version_info["commit"]
        )
    except SQLAlchemyError as e:
        logger.error(f"Database health check failed: {e}", exc_info=True)
        return HealthResponse(
            status="unhealthy", 
            database="disconnected", 
            error=str(e),
            version=version_info["version"],
            commit=version_info["commit"]
        )
    except Exception as e:
        logger.error(f"Unexpected error in health check: {e}", exc_info=True)
        return HealthResponse(
            status="unhealthy", 
            database="unknown", 
            error="Internal error",
            version=version_info["version"],
            commit=version_info["commit"]
        )


@app.get(
    "/version",
    response_model=VersionResponse,
    tags=["info"],
    summary="Version information",
    description="Get application version and build information",
)
async def get_version():
    """
    Returns version information about the running application.

    This endpoint provides build metadata including:
    - Application version
    - Git commit SHA
    - Build timestamp
    - Python version
    - Deployment environment
    """
    # Try to read version from version.json file (created during Docker build)
    version_file = PathLib("/app/version.json")

    if version_file.exists():
        try:
            with open(version_file) as f:
                version_data = json.load(f)

            return VersionResponse(
                version=version_data.get(
                    "version", os.getenv("APP_VERSION", "unknown")
                ),
                commit=version_data.get(
                    "commit", os.getenv("GIT_COMMIT", "unknown")
                ),
                build_date=version_data.get(
                    "build_date", os.getenv("BUILD_DATE", "unknown")
                ),
                python_version=version_data.get(
                    "python_version",
                    f"{sys.version_info.major}.{sys.version_info.minor}",
                ),
                environment=os.getenv("ENVIRONMENT", "development"),
            )
        except (json.JSONDecodeError, OSError) as e:
            logger.warning(f"Failed to read version.json: {e}")

    # Fallback to environment variables
    return VersionResponse(
        version=os.getenv("APP_VERSION", settings.API_VERSION),
        commit=os.getenv("GIT_COMMIT", "unknown"),
        build_date=os.getenv("BUILD_DATE", "unknown"),
        python_version=f"{sys.version_info.major}.{sys.version_info.minor}",
        environment=os.getenv("ENVIRONMENT", "development"),
    )


def rate_limit():
    """Conditional rate limiting decorator"""
    if settings.RATE_LIMIT_ENABLED:
        return limiter.limit(f"{settings.RATE_LIMIT_PER_MINUTE}/minute")

    # Return a no-op decorator if rate limiting is disabled
    def noop_decorator(func):
        return func

    return noop_decorator


@app.get(
    "/api/hello",
    response_model=HelloResponse,
    tags=["greetings"],
    summary="Hello endpoint",
    description="Simple hello endpoint for testing",
)
@rate_limit()
async def hello(request: Request):
    """Simple hello endpoint (DEPLOY-TEST-1: Version info added)"""
    # DEPLOY-TEST-1: Show build info only in non-production environments
    # For security: Don't expose deployment timestamps in production
    environment = os.getenv("ENVIRONMENT", "development")
    
    if environment.lower() != "production":
        # In dev/staging: Show build date for verification (less sensitive than current timestamp)
        version_file = PathLib("/app/version.json")
        build_info = ""
        if version_file.exists():
            try:
                with open(version_file) as f:
                    version_data = json.load(f)
                    build_date = version_data.get("build_date", "unknown")
                    commit_short = version_data.get("commit", "unknown")[:7] if version_data.get("commit") != "unknown" else "unknown"
                    build_info = f" (build: {commit_short}, {build_date})"
            except (json.JSONDecodeError, OSError):
                pass
        
        return HelloResponse(message=f"hello from backend{build_info}")
    else:
        # In production: Keep it simple, no build info
        return HelloResponse(message="hello from backend")


@app.get(
    "/api/deploy-test-2",
    response_model=HelloResponse,
    tags=["testing"],
    summary="Deployment test endpoint",
    description="DEPLOY-TEST-2: Test endpoint to verify deployment pipeline",
)
@rate_limit()
async def deploy_test_2(request: Request):
    """DEPLOY-TEST-2: Test endpoint for deployment verification"""
    return HelloResponse(
        message="DEPLOY-TEST-2: Backend deployment successful! Timestamp: 2025-01-XX"
    )


@app.get(
    "/api/deploy-test-3",
    response_model=HelloResponse,
    tags=["testing"],
    summary="Deployment test endpoint #3",
    description="DEPLOY-TEST-3: Latest test endpoint to verify CI/CD fixes",
)
@rate_limit()
async def deploy_test_3(request: Request):
    """DEPLOY-TEST-3: Latest test endpoint for deployment verification after fixes"""
    environment = os.getenv("ENVIRONMENT", "development")
    return HelloResponse(
        message=f"DEPLOY-TEST-3: ✅ Backend deployed successfully! Environment: {environment} | Pipeline fixes verified"
    )


@app.get(
    "/api/greet/{user}",
    response_model=GreetingResponse,
    tags=["greetings"],
    summary="Greet a user",
    description=(
        "Create a personalized greeting for a user and store it in the database"
    ),
)
@rate_limit()
async def greet_user(
    request: Request,
    user: str = Path(..., min_length=1, max_length=100, description="User name"),
    db: Session = Depends(get_db),  # noqa: B008
):
    """Personalized greeting endpoint that stores greetings in database"""
    # Check if database is available (get_db will raise RuntimeError if not,
    # but we want 503)
    if not database_available:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is not available. Please configure DATABASE_URL."
        )

    try:
        # Validate and sanitize input
        user_clean = user.strip()
        if not user_clean:
            # Raise RequestValidationError to return 422 (FastAPI's standard
            # for validation errors)
            raise RequestValidationError(
                errors=[
                    {
                        "type": "value_error",
                        "loc": ("path", "user"),
                        "msg": "User name cannot be empty or whitespace only",
                        "input": user,
                    }
                ]
            )

        if len(user_clean) > 100:
            raise RequestValidationError(
                errors=[
                    {
                        "type": "value_error.string_too_long",
                        "loc": ("path", "user"),
                        "msg": "User name too long (max 100 characters)",
                        "input": user,
                    }
                ]
            )

        greeting_message = f"Hello, {user_clean}!"

        # Store greeting in database with proper error handling
        try:
            greeting = Greeting(user_name=user_clean, message=greeting_message)
            db.add(greeting)
            db.commit()
            db.refresh(greeting)
        except IntegrityError as e:
            db.rollback()
            logger.error(f"Database integrity error: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to save greeting",
            ) from e
        except SQLAlchemyError as e:
            db.rollback()
            logger.error(f"Database error: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error occurred",
            ) from e

        return GreetingResponse(
            message=greeting_message,
            id=greeting.id,
            created_at=greeting.created_at,
        )
    except (HTTPException, RequestValidationError):
        # Re-raise HTTPException and RequestValidationError to let FastAPI handle them
        raise
    except RuntimeError as e:
        # Handle database unavailable error from get_db()
        if "Database is not available" in str(e):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database is not available. Please configure DATABASE_URL."
            ) from e
        raise
    except Exception as e:
        logger.error(f"Unexpected error in greet_user: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error",
        ) from e


@app.get(
    "/api/greetings",
    response_model=GreetingsListResponse,
    tags=["greetings"],
    summary="Get all greetings",
    description="Retrieve all greetings with pagination",
)
@rate_limit()
async def get_greetings(
    request: Request,
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(
        10, ge=1, le=100, description="Maximum number of records to return"
    ),
    db: Session = Depends(get_db),  # noqa: B008
):
    """Get all greetings from database with pagination"""
    # Check if database is available (get_db will raise RuntimeError if not,
    # but we want 503)
    if not database_available:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is not available. Please configure DATABASE_URL."
        )

    try:
        # Validate pagination parameters
        if skip < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Skip must be >= 0"
            )
        if limit < 1 or limit > 100:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Limit must be between 1 and 100",
            )

        # Query with error handling
        try:
            total = db.query(Greeting).count()
            greetings = (
                db.query(Greeting)
                .order_by(Greeting.created_at.desc())
                .offset(skip)
                .limit(limit)
                .all()
            )
        except SQLAlchemyError as e:
            logger.error(f"Database error in get_greetings: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error occurred",
            ) from e

        return GreetingsListResponse(
            total=total, greetings=greetings, skip=skip, limit=limit
        )
    except HTTPException:
        raise
    except RuntimeError as e:
        # Handle database unavailable error from get_db()
        if "Database is not available" in str(e):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database is not available. Please configure DATABASE_URL."
            ) from e
        raise
    except Exception as e:
        logger.error(f"Unexpected error in get_greetings: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error",
        ) from e


@app.get(
    "/api/greetings/{user}",
    response_model=UserGreetingsResponse,
    tags=["greetings"],
    summary="Get user greetings",
    description="Retrieve all greetings for a specific user",
)
@rate_limit()
async def get_user_greetings(
    request: Request,
    user: str = Path(..., min_length=1, max_length=100, description="User name"),
    db: Session = Depends(get_db),  # noqa: B008
):
    """Get all greetings for a specific user"""
    # Check if database is available (get_db will raise RuntimeError if not,
    # but we want 503)
    if not database_available:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is not available. Please configure DATABASE_URL."
        )

    try:
        # Validate and sanitize input
        user_clean = user.strip()
        if not user_clean:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User name cannot be empty",
            )

        # Query with error handling
        try:
            greetings = (
                db.query(Greeting)
                .filter(Greeting.user_name == user_clean)
                .order_by(Greeting.created_at.desc())
                .all()
            )
        except SQLAlchemyError as e:
            logger.error(f"Database error in get_user_greetings: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error occurred",
            ) from e

        return UserGreetingsResponse(
            user=user_clean, count=len(greetings), greetings=greetings
        )
    except HTTPException:
        raise
    except RuntimeError as e:
        # Handle database unavailable error from get_db()
        if "Database is not available" in str(e):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database is not available. Please configure DATABASE_URL."
            ) from e
        raise
    except Exception as e:
        logger.error(f"Unexpected error in get_user_greetings: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error",
        ) from e
