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


class HelloResponse(BaseModel):
    """Hello endpoint response schema"""

    message: str


class GreetingCreate(BaseModel):
    """Greeting creation schema"""

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
    id: int
    created_at: datetime

    model_config = {"from_attributes": True}


class GreetingItem(BaseModel):
    """Individual greeting item schema"""

    id: int
    user_name: str
    message: str
    created_at: datetime

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
