"""Configuration management with environment variable validation"""

import os

from pydantic_settings import BaseSettings, SettingsConfigDict


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
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL", "postgresql://appuser:apppassword@localhost:5432/appdb"
    )
    DATABASE_POOL_SIZE: int = int(os.getenv("DATABASE_POOL_SIZE", "5"))
    DATABASE_MAX_OVERFLOW: int = int(os.getenv("DATABASE_MAX_OVERFLOW", "10"))
    DATABASE_POOL_TIMEOUT: int = int(os.getenv("DATABASE_POOL_TIMEOUT", "30"))
    DATABASE_POOL_RECYCLE: int = int(os.getenv("DATABASE_POOL_RECYCLE", "3600"))

    # Security Configuration
    SECRET_KEY: str = os.getenv("SECRET_KEY", "change-me-in-production")
    ALLOWED_HOSTS: list[str] = os.getenv("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

    # Rate Limiting
    RATE_LIMIT_ENABLED: bool = os.getenv("RATE_LIMIT_ENABLED", "true").lower() == "true"
    RATE_LIMIT_PER_MINUTE: int = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))

    # Logging
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    LOG_FORMAT: str = os.getenv("LOG_FORMAT", "json")

    # Testing
    TESTING: bool = os.getenv("TESTING", "false").lower() == "true"

    def get_cors_origins(self) -> list[str]:
        """Parse CORS origins from environment variable"""
        if self.CORS_ORIGINS == "*":
            return ["*"]
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",")]


settings = Settings()
