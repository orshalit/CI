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
FROM python:${PYTHON_VERSION}-slim as builder

# Set build arguments for this stage
ARG BUILD_DATE
ARG BUILD_VERSION
ARG GIT_COMMIT

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    postgresql-client \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

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

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Python packages from builder
COPY --from=builder /root/.local /root/.local

# Copy application code and configuration
COPY main.py database.py config.py schemas.py middleware.py logging_config.py ./
COPY --from=builder /app/version.json ./version.json

# Make sure scripts in .local are usable
ENV PATH=/root/.local/bin:$PATH

# Set environment variables for version info
ENV APP_VERSION="${BUILD_VERSION}" \
    GIT_COMMIT="${GIT_COMMIT}" \
    BUILD_DATE="${BUILD_DATE}"

# Create non-root user for security
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app && \
    chmod -R 755 /app

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 8000

# Health check - verifies application is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Add version check command
RUN echo "Backend Version: ${BUILD_VERSION} (${GIT_COMMIT})" && \
    cat /app/version.json

# Run the application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
