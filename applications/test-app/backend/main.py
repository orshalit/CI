import json
import logging
import os
import psutil
import sys
import time
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path as PathLib

from botocore.exceptions import ClientError
from fastapi import Depends, FastAPI, HTTPException, Path, Query, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from auth import get_auth_dependency
from config import settings
from database import (
    Greeting,
    create_greeting,
    database_available,
    get_db,
    get_greetings as db_get_greetings,
    get_user_greetings as db_get_user_greetings,
    init_db,
    table_name,
)
from logging_config import setup_logging
from middleware import (
    ErrorHandlingMiddleware,
    LoggingMiddleware,
    RequestIdMiddleware,
    SecurityHeadersMiddleware,
)
from schemas import (
    ConfigResponse,
    DynamoDBStatusResponse,
    GreetingResponse,
    GreetingsListResponse,
    HealthResponse,
    HelloResponse,
    MetricsResponse,
    StatusResponse,
    UserGreetingsResponse,
    VersionResponse,
)


# Setup logging
setup_logging(log_level=settings.LOG_LEVEL, log_format=settings.LOG_FORMAT)
logger = logging.getLogger(__name__)

# Runtime metrics
# These must be defined at module import time (handlers use them).
request_count = 0
app_start_time = time.time()

# Initialize rate limiter
limiter = Limiter(key_func=get_remote_address)


def rate_limit():
    """Conditional rate limiting decorator."""
    if settings.RATE_LIMIT_ENABLED:
        return limiter.limit(f"{settings.RATE_LIMIT_PER_MINUTE}/minute")

    # Return a no-op decorator if rate limiting is disabled
    def noop_decorator(func):
        return func

    return noop_decorator


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan event handler for startup and shutdown"""
    # Startup: Initialize database only if available and not in testing mode
    # CI/CD Pipeline Test: Full pipeline validation with Dhall fixes
    # Pipeline run: Testing full deployment cycle after health diagnostics
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
    # Pipeline fix: terraform.tfvars.json validation and error handling
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
                version_info["version"] = version_data.get("version") or os.getenv("APP_VERSION") or settings.API_VERSION or "dev"
                version_info["commit"] = version_data.get("commit") or os.getenv("GIT_COMMIT") or "unknown"
        except (json.JSONDecodeError, OSError) as e:
            logger.warning(f"Failed to read version.json: {e}")
            version_info["version"] = os.getenv("APP_VERSION") or settings.API_VERSION or "dev"
            version_info["commit"] = os.getenv("GIT_COMMIT") or "unknown"
    else:
        version_info["version"] = os.getenv("APP_VERSION") or settings.API_VERSION or "dev"
        version_info["commit"] = os.getenv("GIT_COMMIT") or "unknown"
    
    # Log version info for debugging
    logger.debug(f"Health check version info: {version_info}")

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
        from database import dynamodb_client
        if dynamodb_client and table_name:
            dynamodb_client.describe_table(TableName=table_name)
            return HealthResponse(
                status="healthy",
                database="connected",
                version=version_info["version"],
                commit=version_info["commit"]
            )
        else:
            return HealthResponse(
                status="healthy",
                database="unavailable",
                version=version_info["version"],
                commit=version_info["commit"]
            )
    except ClientError as e:
        logger.error(f"DynamoDB health check failed: {e}", exc_info=True)
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
    "/api/config",
    response_model=ConfigResponse,
    tags=["config"],
    summary="Public configuration endpoint",
    description="Returns public configuration needed by frontend at runtime (including API key)",
)
@rate_limit()  # Rate limit decorator now properly defined before use
async def get_config():  # Pipeline trigger: test port discovery fix
    """
    Public configuration endpoint for frontend runtime configuration.
    
    This endpoint provides the API key and other public configuration
    that the frontend needs at runtime. The API key is fetched from
    Secrets Manager and returned securely.
    
    Note: This endpoint does NOT require authentication (it's public config).
    The API key returned here is used by the frontend to authenticate
    subsequent API requests.
    """
    try:
        from secrets import get_backend_api_key
        
        # Get API key from Secrets Manager
        api_key = get_backend_api_key()
        
        # Get backend URL from environment or settings
        backend_url = os.getenv(
            "BACKEND_API_URL",
            os.getenv("API_BASE_URL", "https://test-api.app.dev.light-solutions.org")
        )
        
        # Get environment
        environment = os.getenv("ENVIRONMENT", "development")
        
        return ConfigResponse(
            api_key=api_key,
            backend_url=backend_url,
            environment=environment,
        )
    except Exception as e:
        logger.error(f"Failed to retrieve config: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve configuration",
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

@app.get(
    "/api/status",
    response_model=StatusResponse,
    tags=["info"],
    summary="System status",
    description="Get system status including package manager information",
    dependencies=[get_auth_dependency()],
)
async def get_status():
    """
    Returns system status information including package manager details.

    This endpoint provides information about:
    - Package manager in use (uv)
    - System status
    - Status message

    Pipeline Test #10: Trigger full pipeline validation after DynamoDB init fix
    """
    return StatusResponse(
        package_manager="uv",
        status="operational",
        message="System is running with uv package manager (10-100x faster than pip) - Pipeline Test #10",
    )


@app.get(
    "/api/hello",
    response_model=HelloResponse,
    tags=["greetings"],
    summary="Hello endpoint",
    description="Simple hello endpoint for testing",
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def hello(request: Request):
    """Simple hello endpoint (DEPLOY-TEST-1: Version info added)"""
    global request_count
    request_count += 1
    
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
                    commit_val = version_data.get("commit", "unknown")
                    commit_short = commit_val[:7] if commit_val != "unknown" else "unknown"
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
    dependencies=[get_auth_dependency()],
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
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def deploy_test_3(request: Request):
    """DEPLOY-TEST-3: Latest test endpoint for deployment verification after fixes"""
    environment = os.getenv("ENVIRONMENT", "development")
    return HelloResponse(
        message=f"DEPLOY-TEST-3: ✅ Backend deployed successfully! Environment: {environment} | Fold arg order fixed | Built-images merge fixed | Full pipeline run"
    )


@app.get(
    "/api/secrets-test",
    tags=["testing"],
    summary="Secrets management test endpoint",
    description="Test endpoint to verify dynamic secrets discovery and retrieval from AWS Secrets Manager",
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def secrets_test(request: Request):
    """
    Test endpoint to verify secrets management integration.
    
    This endpoint demonstrates:
    - Dynamic secret discovery via SSM Parameter Store
    - Secret retrieval from AWS Secrets Manager
    - Proper error handling and fallbacks
    """
    from secrets import (
        get_external_api_key,
        get_jwt_signing_key,
        get_session_secret,
    )
    
    results = {
        "status": "success",
        "secrets_tested": [],
        "errors": [],
    }
    
    # Test each pre-configured secret
    secret_tests = [
        ("session-secret", get_session_secret, "SESSION_SECRET"),
        ("jwt-signing-key", get_jwt_signing_key, "JWT_SIGNING_KEY"),
        ("external-api-key", get_external_api_key, "EXTERNAL_API_KEY"),
    ]
    
    for secret_name, secret_func, env_var in secret_tests:
        try:
            secret_value = secret_func()
            # Don't expose the actual secret value, just confirm it exists
            secret_length = len(secret_value)
            results["secrets_tested"].append({
                "name": secret_name,
                "status": "retrieved",
                "source": "secrets_manager",
                "length": secret_length,
            })
            logger.debug(f"Successfully retrieved {secret_name} (length: {secret_length})")
        except ValueError as e:
            # Check if fallback to environment variable worked
            fallback_value = os.getenv(env_var)
            if fallback_value:
                results["secrets_tested"].append({
                    "name": secret_name,
                    "status": "retrieved",
                    "source": "environment_variable",
                    "length": len(fallback_value),
                })
                logger.info(f"Retrieved {secret_name} from environment variable fallback")
            else:
                results["secrets_tested"].append({
                    "name": secret_name,
                    "status": "not_found",
                    "error": str(e),
                })
                results["errors"].append(f"{secret_name}: {str(e)}")
                logger.warning(f"Could not retrieve {secret_name}: {e}")
        except Exception as e:
            results["secrets_tested"].append({
                "name": secret_name,
                "status": "error",
                "error": str(e),
            })
            results["errors"].append(f"{secret_name}: {str(e)}")
            logger.error(f"Error retrieving {secret_name}: {e}", exc_info=True)
    
    # Also verify SECRET_KEY from config uses secrets
    try:
        from config import settings
        secret_key_length = len(settings.SECRET_KEY)
        results["secrets_tested"].append({
            "name": "SECRET_KEY (from config)",
            "status": "configured",
            "source": "config_settings",
            "length": secret_key_length,
        })
    except Exception as e:
        results["errors"].append(f"SECRET_KEY config error: {str(e)}")
    
    # Set overall status
    if results["errors"]:
        results["status"] = "partial_success" if results["secrets_tested"] else "failed"
    
    return results


@app.get(
    "/api/greet/{user}",
    response_model=GreetingResponse,
    tags=["greetings"],
    summary="Greet a user",
    description=(
        "Create a personalized greeting for a user and store it in the database"
    ),
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def greet_user(
    request: Request,
    user: str = Path(..., min_length=1, max_length=100, description="User name"),
):
    """Personalized greeting endpoint that stores greetings in DynamoDB"""
    # Check if database is available
    if not database_available:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="DynamoDB is not available. Please ensure the table is created and IAM permissions are configured."
        )

    try:
        # Validate and sanitize input
        user_clean = user.strip()
        if not user_clean:
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

        # Store greeting in DynamoDB with proper error handling
        try:
            greeting = create_greeting(user_name=user_clean, message=greeting_message)
        except ClientError as e:
            logger.error(f"DynamoDB error: {e}", exc_info=True)
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
        raise
    except RuntimeError as e:
        if "DynamoDB is not available" in str(e):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="DynamoDB is not available. Please ensure the table is created and IAM permissions are configured."
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
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def get_greetings(
    request: Request,
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(
        10, ge=1, le=100, description="Maximum number of records to return"
    ),
):
    """Get all greetings from DynamoDB with pagination"""
    if not database_available:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="DynamoDB is not available. Please ensure the table is created and IAM permissions are configured."
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

        # Query DynamoDB with error handling
        try:
            greetings, total = db_get_greetings(skip=skip, limit=limit)
        except ClientError as e:
            logger.error(f"DynamoDB error in get_greetings: {e}", exc_info=True)
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
        if "DynamoDB is not available" in str(e):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="DynamoDB is not available. Please ensure the table is created and IAM permissions are configured."
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
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def get_user_greetings(
    request: Request,
    user: str = Path(..., min_length=1, max_length=100, description="User name"),
):
    """Get all greetings for a specific user from DynamoDB"""
    if not database_available:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="DynamoDB is not available. Please ensure the table is created and IAM permissions are configured."
        )

    try:
        # Validate and sanitize input
        user_clean = user.strip()
        if not user_clean:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User name cannot be empty",
            )

        # Query DynamoDB with error handling
        try:
            greetings = db_get_user_greetings(user_name=user_clean)
        except ClientError as e:
            logger.error(f"DynamoDB error in get_user_greetings: {e}", exc_info=True)
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
        if "DynamoDB is not available" in str(e):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="DynamoDB is not available. Please ensure the table is created and IAM permissions are configured."
            ) from e
        raise
    except Exception as e:
        logger.error(f"Unexpected error in get_user_greetings: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error",
        ) from e


@app.get(
    "/api/metrics",
    response_model=MetricsResponse,
    tags=["info"],
    summary="System metrics",
    description="Get system metrics including uptime, request count, and resource usage",
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def get_metrics(request: Request):
    """
    Returns system metrics including:
    - Application uptime
    - Total requests processed
    - Active connections
    - Memory usage
    """
    global request_count
    
    # Calculate uptime
    uptime_seconds = time.time() - app_start_time
    
    # Get memory usage
    process = psutil.Process(os.getpid())
    memory_info = process.memory_info()
    memory_usage_mb = memory_info.rss / (1024 * 1024)  # Convert to MB
    
    # Get active connections (approximate from process connections)
    try:
        connections = process.connections()
        active_connections = len(connections)
    except Exception:
        active_connections = 0
    
    return MetricsResponse(
        uptime_seconds=round(uptime_seconds, 2),
        total_requests=request_count,
        active_connections=active_connections,
        memory_usage_mb=round(memory_usage_mb, 2),
        timestamp=datetime.utcnow().isoformat() + "Z",
    )


@app.get(
    "/api/dynamodb-status",
    response_model=DynamoDBStatusResponse,
    status_code=status.HTTP_200_OK,
    summary="Get DynamoDB connection status",
    description="Returns the current status of DynamoDB connectivity and table information",
    tags=["Database"],
    dependencies=[get_auth_dependency()],
)
@rate_limit()
async def get_dynamodb_status(request: Request):
    """Get DynamoDB connection status and table information"""
    import os
    from database import database_available, table_name, dynamodb_client
    
    endpoint_url = os.getenv("DYNAMODB_ENDPOINT_URL")
    region = os.getenv("AWS_REGION", "us-east-1")
    
    if not database_available:
        return DynamoDBStatusResponse(
            available=False,
            table_name=table_name,
            endpoint_url=endpoint_url,
            region=region,
            message="DynamoDB is not available. Table may not exist or IAM permissions may be missing.",
        )
    
    # Try to get table status
    table_status = None
    try:
        if dynamodb_client and table_name:
            response = dynamodb_client.describe_table(TableName=table_name)
            table_status = response.get("Table", {}).get("TableStatus", "UNKNOWN")
    except Exception as e:
        logger.warning(f"Could not get table status: {e}")
    
    return DynamoDBStatusResponse(
        available=True,
        table_name=table_name,
        table_status=table_status,
        endpoint_url=endpoint_url,
        region=region,
        message=f"DynamoDB is available. Table '{table_name}' is {'ACTIVE' if table_status == 'ACTIVE' else table_status or 'UNKNOWN'}.",
    )
