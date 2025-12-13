"""Configuration management with environment variable validation"""

import logging
import os

from pydantic_settings import BaseSettings, SettingsConfigDict


logger = logging.getLogger(__name__)


def _get_secret_key() -> str:
    """
    Get SECRET_KEY from Secrets Manager or fallback to environment variable.

    This function attempts to retrieve the session secret from AWS Secrets Manager
    using dynamic discovery. If that fails, it falls back to the SECRET_KEY
    environment variable, and finally to a default value.

    Returns:
        str: Secret key value
    """
    try:
        # Try to import secrets module (may not be available in all environments)
        from secrets import get_session_secret

        try:
            # Try to get from Secrets Manager via dynamic discovery
            secret_key = get_session_secret()
            logger.info("Successfully retrieved SECRET_KEY from Secrets Manager")
            return secret_key
        except Exception as e:
            logger.debug(f"Could not retrieve SECRET_KEY from Secrets Manager: {e}")
            # Fall through to environment variable fallback
    except ImportError:
        logger.debug("secrets module not available, using environment variable fallback")
    except Exception as e:
        logger.debug(f"Error importing secrets module: {e}")

    # Fallback to environment variable
    env_secret = os.getenv("SECRET_KEY")
    if env_secret:
        logger.info("Using SECRET_KEY from environment variable")
        return env_secret

    # Final fallback (should only be used in local development/testing)
    logger.warning(
        "SECRET_KEY not found in Secrets Manager or environment variable. "
        "Using default value. This should not be used in production!"
    )
    return "change-me-in-production"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")
    """Application settings with validation"""

    # API Configuration
    API_TITLE: str = "Backend API"
    API_VERSION: str = "1.0.0"
    API_V1_PREFIX: str = "/api/v1"

    # CORS Configuration
    CORS_ORIGINS: str = os.getenv("CORS_ORIGINS", "http://localhost:3000")
    CORS_ALLOW_CREDENTIALS: bool = True
    CORS_ALLOW_METHODS: list[str] = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    CORS_ALLOW_HEADERS: list[str] = ["*"]

    # Database Configuration
    # Default to empty string - database is optional
    # If DATABASE_URL is not set, database features will be unavailable
    DATABASE_URL: str = os.getenv("DATABASE_URL", "")
    DATABASE_POOL_SIZE: int = int(os.getenv("DATABASE_POOL_SIZE", "5"))
    DATABASE_MAX_OVERFLOW: int = int(os.getenv("DATABASE_MAX_OVERFLOW", "10"))
    DATABASE_POOL_TIMEOUT: int = int(os.getenv("DATABASE_POOL_TIMEOUT", "30"))
    DATABASE_POOL_RECYCLE: int = int(os.getenv("DATABASE_POOL_RECYCLE", "3600"))

    # Security Configuration
    # SECRET_KEY is loaded dynamically from Secrets Manager or environment variable
    SECRET_KEY: str = _get_secret_key()
    ALLOWED_HOSTS: list[str] = os.getenv("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

    # Rate Limiting
    RATE_LIMIT_ENABLED: bool = os.getenv("RATE_LIMIT_ENABLED", "true").lower() == "true"
    RATE_LIMIT_PER_MINUTE: int = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))

    # Logging
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    LOG_FORMAT: str = os.getenv("LOG_FORMAT", "json")

    # Testing
    TESTING: bool = os.getenv("TESTING", "false").lower() == "true"

    # Authentication
    AUTH_REQUIRED: bool = os.getenv("AUTH_REQUIRED", "true").lower() == "true"

    def get_cors_origins(self) -> list[str]:
        """Parse CORS origins from environment variable"""
        if self.CORS_ORIGINS == "*":
            return ["*"]
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",")]


settings = Settings()
