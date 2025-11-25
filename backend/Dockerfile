################################################################################
# Backend Dockerfile - Production Grade
# Multi-stage build with proper versioning, labels, and security
################################################################################

# Build arguments for versioning and metadata
ARG PYTHON_VERSION=3.11
ARG BUILD_DATE
ARG BUILD_VERSION=dev
ARG GIT_COMMIT=unknown
ARG GIT_BRANCH=unknown

################################################################################
# Stage 1: Builder - Install dependencies
################################################################################
FROM python:${PYTHON_VERSION}-slim AS builder

# Set build arguments for this stage
ARG BUILD_DATE
ARG BUILD_VERSION
ARG GIT_COMMIT
ARG PYTHON_VERSION

WORKDIR /app

# Install only build dependencies needed for pip compilation
# Note: gcc needed for some Python packages with C extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
# Clean up __pycache__ and .pyc files to reduce image size
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt && \
    find /root/.local -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true && \
    find /root/.local -type f -name "*.pyc" -delete 2>/dev/null || true

# Create version info file
RUN echo "{\
  \"version\": \"${BUILD_VERSION}\",\
  \"commit\": \"${GIT_COMMIT}\",\
  \"build_date\": \"${BUILD_DATE}\",\
  \"python_version\": \"${PYTHON_VERSION}\"\
}" > /app/version.json

################################################################################
# Stage 2: Runtime - Final production image
################################################################################
FROM python:${PYTHON_VERSION}-slim

# Re-declare ARGs for this stage
ARG BUILD_DATE
ARG BUILD_VERSION=dev
ARG GIT_COMMIT=unknown
ARG GIT_BRANCH=unknown
ARG PYTHON_VERSION

# OCI Labels - Standard container metadata
# https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.authors="DevOps Team" \
      org.opencontainers.image.url="https://github.com/orshalit/CI" \
      org.opencontainers.image.source="https://github.com/orshalit/CI" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.vendor="Your Organization" \
      org.opencontainers.image.title="Backend API" \
      org.opencontainers.image.description="FastAPI backend service with PostgreSQL" \
      org.opencontainers.image.documentation="https://github.com/orshalit/CI/blob/main/README.md" \
      org.opencontainers.image.base.name="python:${PYTHON_VERSION}-slim" \
      # Custom labels
      app.version="${BUILD_VERSION}" \
      app.git.commit="${GIT_COMMIT}" \
      app.git.branch="${GIT_BRANCH}" \
      app.build.date="${BUILD_DATE}" \
      app.python.version="${PYTHON_VERSION}"

WORKDIR /app

# Install only runtime dependencies (no build tools)
# - libpq5: PostgreSQL client library (runtime only, not dev headers)
# - curl: For health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user for security (before copying files)
RUN useradd -m -u 1000 -s /bin/bash appuser

# Copy installed Python packages from builder to user's home
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY main.py database.py config.py schemas.py middleware.py logging_config.py ./
COPY --from=builder /app/version.json ./version.json

# Set ownership (single layer for efficiency)
RUN chown -R appuser:appuser /app /home/appuser/.local && \
    chmod -R 755 /app

# Set environment variables for version info, PATH, and Python optimization
ENV APP_VERSION="${BUILD_VERSION}" \
    GIT_COMMIT="${GIT_COMMIT}" \
    BUILD_DATE="${BUILD_DATE}" \
    PATH=/home/appuser/.local/bin:$PATH \
    # Prevent Python from writing .pyc files (smaller image, faster startup)
    PYTHONDONTWRITEBYTECODE=1 \
    # Force Python stdout/stderr to be unbuffered (better for Docker logs)
    PYTHONUNBUFFERED=1 \
    # Set Python to use UTF-8 encoding
    PYTHONIOENCODING=utf-8 \
    # Disable pip version check for faster startup
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Expose application port
EXPOSE 8000

# Health check - verifies application is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Switch to non-root user (do this last before CMD)
USER appuser

# Run the application with production settings
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log"]
