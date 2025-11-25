import json
import logging
import os
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
from database import Greeting, get_db, init_db
from logging_config import setup_logging
from middleware import ErrorHandlingMiddleware, LoggingMiddleware, SecurityHeadersMiddleware
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
    # Startup: Initialize database only if not in testing mode
    if not settings.TESTING:
        logger.info("Initializing database...")
        try:
            init_db()
            logger.info("Database initialized successfully")
        except Exception as e:
            logger.error(f"Failed to initialize database: {e}", exc_info=True)
            raise
    yield
    # Shutdown: cleanup if needed
    logger.info("Shutting down application...")


app = FastAPI(
    title=settings.API_TITLE,
    version=settings.API_VERSION,
    lifespan=lifespan,
    docs_url="/docs" if not settings.TESTING else None,
    redoc_url="/redoc" if not settings.TESTING else None,
)

# Add rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Add middleware (order matters - last added is first executed)
app.add_middleware(ErrorHandlingMiddleware)
app.add_middleware(LoggingMiddleware)
app.add_middleware(SecurityHeadersMiddleware)

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
    description="Check the health status of the API and database connectivity"
)
async def health_check(db: Session = Depends(get_db)):
    """Health check endpoint with database connectivity check"""
    try:
        # Test database connection
        db.execute(text("SELECT 1"))
        return HealthResponse(status="healthy", database="connected")
    except SQLAlchemyError as e:
        logger.error(f"Database health check failed: {e}", exc_info=True)
        return HealthResponse(
            status="unhealthy",
            database="disconnected",
            error=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error in health check: {e}", exc_info=True)
        return HealthResponse(
            status="unhealthy",
            database="unknown",
            error="Internal error"
        )


@app.get(
    "/version",
    response_model=VersionResponse,
    tags=["info"],
    summary="Version information",
    description="Get application version and build information"
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
            with open(version_file, 'r') as f:
                version_data = json.load(f)
            
            return VersionResponse(
                version=version_data.get("version", os.getenv("APP_VERSION", "unknown")),
                commit=version_data.get("commit", os.getenv("GIT_COMMIT", "unknown")),
                build_date=version_data.get("build_date", os.getenv("BUILD_DATE", "unknown")),
                python_version=version_data.get("python_version", "3.11"),
                environment=settings.ENVIRONMENT
            )
        except (json.JSONDecodeError, IOError) as e:
            logger.warning(f"Failed to read version.json: {e}")
    
    # Fallback to environment variables
    return VersionResponse(
        version=os.getenv("APP_VERSION", settings.API_VERSION),
        commit=os.getenv("GIT_COMMIT", "unknown"),
        build_date=os.getenv("BUILD_DATE", "unknown"),
        python_version="3.11",
        environment=settings.ENVIRONMENT
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
    description="Simple hello endpoint for testing"
)
@rate_limit()
async def hello(request: Request):
    """Simple hello endpoint"""
    return HelloResponse(message="hello from backend")


@app.get(
    "/api/greet/{user}",
    response_model=GreetingResponse,
    tags=["greetings"],
    summary="Greet a user",
    description="Create a personalized greeting for a user and store it in the database"
)
@rate_limit()
async def greet_user(
    request: Request,
    user: str = Path(..., min_length=1, max_length=100, description="User name"),
    db: Session = Depends(get_db)
):
    """Personalized greeting endpoint that stores greetings in database"""
    try:
        # Validate and sanitize input
        user_clean = user.strip()
        if not user_clean:
            # Raise RequestValidationError to return 422 (FastAPI's standard for validation errors)
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
                detail="Failed to save greeting"
            )
        except SQLAlchemyError as e:
            db.rollback()
            logger.error(f"Database error: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error occurred"
            )
        
        return GreetingResponse(
            message=greeting_message,
            id=greeting.id,
            created_at=greeting.created_at
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in greet_user: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.get(
    "/api/greetings",
    response_model=GreetingsListResponse,
    tags=["greetings"],
    summary="Get all greetings",
    description="Retrieve all greetings with pagination"
)
@rate_limit()
async def get_greetings(
    request: Request,
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(10, ge=1, le=100, description="Maximum number of records to return"),
    db: Session = Depends(get_db)
):
    """Get all greetings from database with pagination"""
    try:
        # Validate pagination parameters
        if skip < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Skip must be >= 0"
            )
        if limit < 1 or limit > 100:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Limit must be between 1 and 100"
            )
        
        # Query with error handling
        try:
            total = db.query(Greeting).count()
            greetings = db.query(Greeting).order_by(Greeting.created_at.desc()).offset(skip).limit(limit).all()
        except SQLAlchemyError as e:
            logger.error(f"Database error in get_greetings: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error occurred"
            )
        
        return GreetingsListResponse(
            total=total,
            greetings=greetings,
            skip=skip,
            limit=limit
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in get_greetings: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )


@app.get(
    "/api/greetings/{user}",
    response_model=UserGreetingsResponse,
    tags=["greetings"],
    summary="Get user greetings",
    description="Retrieve all greetings for a specific user"
)
@rate_limit()
async def get_user_greetings(
    request: Request,
    user: str = Path(..., min_length=1, max_length=100, description="User name"),
    db: Session = Depends(get_db)
):
    """Get all greetings for a specific user"""
    try:
        # Validate and sanitize input
        user_clean = user.strip()
        if not user_clean:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User name cannot be empty"
            )
        
        # Query with error handling
        try:
            greetings = db.query(Greeting).filter(
                Greeting.user_name == user_clean
            ).order_by(Greeting.created_at.desc()).all()
        except SQLAlchemyError as e:
            logger.error(f"Database error in get_user_greetings: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Database error occurred"
            )
        
        return UserGreetingsResponse(
            user=user_clean,
            count=len(greetings),
            greetings=greetings
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in get_user_greetings: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

