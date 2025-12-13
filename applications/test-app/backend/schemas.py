"""Pydantic schemas for request/response validation"""

from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class VersionResponse(BaseModel):
    """API version information schema"""

    version: str = Field(..., description="Application version")
    commit: str = Field(..., description="Git commit SHA")
    build_date: str = Field(..., description="Build timestamp")
    python_version: str = Field(..., description="Python version")
    environment: str = Field(..., description="Deployment environment")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "version": "1.0.0",
                    "commit": "abc123",
                    "build_date": "2024-01-01T00:00:00Z",
                    "python_version": "3.11",
                    "environment": "production",
                }
            ]
        }
    }


class HealthResponse(BaseModel):
    """Health check response schema"""

    status: str
    database: str
    error: str | None = None
    version: str | None = Field(None, description="Application version (DEPLOY-TEST-1)")
    commit: str | None = Field(None, description="Git commit SHA")


class HelloResponse(BaseModel):
    """Hello endpoint response schema"""

    message: str


class GreetingCreate(BaseModel):
    """
    Greeting creation schema for request body validation.

    Note: Currently unused as the greet endpoint takes user_name as a path parameter.
    Kept for future use if POST /api/greetings endpoint is added.
    """

    user_name: str = Field(..., min_length=1, max_length=100, description="User name")

    @field_validator("user_name")
    @classmethod
    def validate_user_name(cls, v: str) -> str:
        """Sanitize and validate user name"""
        if not v or not v.strip():
            raise ValueError("User name cannot be empty")
        # Remove potentially dangerous characters
        sanitized = v.strip()
        if len(sanitized) > 100:
            raise ValueError("User name too long")
        return sanitized


class GreetingResponse(BaseModel):
    """Greeting response schema"""

    message: str
    id: str  # Changed from int to str (DynamoDB uses string UUIDs)
    created_at: str  # Changed from datetime to str (ISO timestamp string)

    model_config = {"from_attributes": True}


class GreetingItem(BaseModel):
    """Individual greeting item schema"""

    id: str  # Changed from int to str (DynamoDB uses string UUIDs)
    user_name: str
    message: str
    created_at: str  # Changed from datetime to str (ISO timestamp string)

    model_config = {"from_attributes": True}


class GreetingsListResponse(BaseModel):
    """Greetings list response schema"""

    total: int
    greetings: list[GreetingItem]
    skip: int
    limit: int


class UserGreetingsResponse(BaseModel):
    """User-specific greetings response schema"""

    user: str
    count: int
    greetings: list[GreetingItem]


class ErrorResponse(BaseModel):
    """Error response schema"""

    error: str
    detail: str | None = None
    status_code: int


class DynamoDBStatusResponse(BaseModel):
    """DynamoDB status response schema"""

    available: bool
    table_name: str | None = None
    table_status: str | None = None
    endpoint_url: str | None = None
    region: str | None = None
    message: str


class ConfigResponse(BaseModel):
    """Public configuration response schema for frontend runtime config"""

    api_key: str = Field(..., description="Backend API key for authentication")
    backend_url: str = Field(..., description="Backend API base URL")
    environment: str = Field(..., description="Deployment environment")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "api_key": "sk_live_abc123...",
                    "backend_url": "https://test-api.app.dev.light-solutions.org",
                    "environment": "dev",
                }
            ]
        }
    }


class StatusResponse(BaseModel):
    """System status response schema"""

    package_manager: str = Field(..., description="Package manager in use")
    status: str = Field(..., description="System status")
    message: str = Field(..., description="Status message")


class MetricsResponse(BaseModel):
    """System metrics response schema"""

    uptime_seconds: float = Field(..., description="Application uptime in seconds")
    total_requests: int = Field(..., description="Total number of requests processed")
    active_connections: int = Field(..., description="Current active connections")
    memory_usage_mb: float = Field(..., description="Memory usage in MB")
    timestamp: str = Field(..., description="Timestamp when metrics were collected")
