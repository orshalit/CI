"""API Key authentication middleware for FastAPI endpoints.

This module provides API key authentication using the X-API-Key header.
It integrates with the existing Secrets Manager infrastructure for key retrieval.
"""

import hmac
import logging

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import APIKeyHeader

from config import settings


logger = logging.getLogger(__name__)

# API Key header name
API_KEY_HEADER_NAME = "X-API-Key"

# Create API key header dependency
api_key_header = APIKeyHeader(name=API_KEY_HEADER_NAME, auto_error=False)


async def verify_api_key(api_key: str | None = Security(api_key_header)) -> str:
    """
    Verify API key from request header.

    This function:
    1. Retrieves the expected API key from Secrets Manager (via SSM discovery)
    2. Compares it with the provided API key from X-API-Key header
    3. Raises HTTPException if invalid or missing

    Args:
        api_key: API key from X-API-Key header (None if not provided)

    Returns:
        str: The validated API key (for logging/audit purposes)

    Raises:
        HTTPException: 401 if API key is missing or invalid
    """
    # Import here to avoid circular dependencies
    from secrets import get_backend_api_key

    # Get expected API key from Secrets Manager (with fallback to env var)
    try:
        expected_key = get_backend_api_key()
    except Exception as e:
        logger.error(f"Failed to retrieve backend API key: {e}", exc_info=True)
        # In production, this should fail. In dev/testing, allow fallback.
        if settings.TESTING:
            logger.warning("TESTING mode: Allowing request without API key validation")
            return api_key or "test-key-bypassed"
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="API authentication configuration error",
        ) from e

    # Check if API key is provided
    if not api_key:
        logger.warning("API request missing X-API-Key header")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing API key. Please provide X-API-Key header.",
            headers={"WWW-Authenticate": "ApiKey"},
        )

    # Compare API keys (use constant-time comparison to prevent timing attacks)
    # Use constant-time comparison
    if not hmac.compare_digest(api_key.encode(), expected_key.encode()):
        logger.warning(f"Invalid API key provided (key length: {len(api_key)})")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key",
            headers={"WWW-Authenticate": "ApiKey"},
        )

    logger.debug("API key validated successfully")
    return api_key


def get_auth_dependency():
    """
    Get authentication dependency based on configuration.

    Returns:
        Dependency or None: FastAPI dependency if auth is required, None otherwise

    This function allows conditional authentication:
    - TESTING mode: No authentication (for E2E tests)
    - AUTH_REQUIRED=false: No authentication (for gradual rollout)
    - Production: Authentication required
    """
    if settings.TESTING:
        logger.debug("TESTING mode: Authentication bypassed")
        return None

    if not settings.AUTH_REQUIRED:
        logger.debug("AUTH_REQUIRED=false: Authentication bypassed")
        return None

    return Depends(verify_api_key)
