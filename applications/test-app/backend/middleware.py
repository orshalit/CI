"""Custom middleware for security, logging, request tracking, and error handling."""

import logging
import time
import uuid
from collections.abc import Callable

from fastapi import Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.base import BaseHTTPMiddleware


logger = logging.getLogger(__name__)


class RequestIdMiddleware(BaseHTTPMiddleware):
    """
    Add unique request ID for distributed tracing.

    The request ID is:
    - Taken from incoming X-Request-ID header if present
    - Generated as UUID if not present
    - Stored in request.state.request_id for access in handlers
    - Added to response headers as X-Request-ID
    """

    async def dispatch(self, request: Request, call_next: Callable):
        # Get existing request ID or generate new one
        request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))

        # Store in request state for access in handlers
        request.state.request_id = request_id

        # Process request
        response = await call_next(request)

        # Add request ID to response headers
        response.headers["X-Request-ID"] = request_id

        return response


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Add security headers to all responses."""

    async def dispatch(self, request: Request, call_next: Callable):
        response = await call_next(request)

        # Security headers
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"

        return response


class LoggingMiddleware(BaseHTTPMiddleware):
    """Log all requests and responses with request ID correlation."""

    async def dispatch(self, request: Request, call_next: Callable):
        start_time = time.time()

        # Get request ID (set by RequestIdMiddleware)
        request_id = getattr(request.state, "request_id", "unknown")

        # Log request
        logger.info(
            f"Request: {request.method} {request.url.path}",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "client_ip": request.client.host if request.client else None,
            },
        )

        try:
            response = await call_next(request)
            process_time = time.time() - start_time

            # Log response
            logger.info(
                f"Response: {request.method} {request.url.path} - {response.status_code}",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "process_time": process_time,
                },
            )

            # Add process time header
            response.headers["X-Process-Time"] = str(process_time)

            return response
        except Exception as e:
            process_time = time.time() - start_time
            logger.error(
                f"Error processing request: {request.method} {request.url.path}",
                extra={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "error": str(e),
                    "process_time": process_time,
                },
                exc_info=True,
            )
            raise


class ErrorHandlingMiddleware(BaseHTTPMiddleware):
    """Global error handling middleware with request ID correlation."""

    async def dispatch(self, request: Request, call_next: Callable):
        # Get request ID for error correlation
        request_id = getattr(request.state, "request_id", "unknown")

        try:
            response = await call_next(request)
            return response
        except StarletteHTTPException as e:
            return JSONResponse(
                status_code=e.status_code,
                content={
                    "error": e.detail,
                    "status_code": e.status_code,
                    "request_id": request_id,
                },
            )
        except RequestValidationError as e:
            return JSONResponse(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                content={
                    "error": "Validation error",
                    "detail": e.errors(),
                    "status_code": 422,
                    "request_id": request_id,
                },
            )
        except Exception as e:
            logger.exception(f"Unhandled exception: {str(e)}", extra={"request_id": request_id})
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={
                    "error": "Internal server error",
                    "status_code": 500,
                    "request_id": request_id,
                },
            )

