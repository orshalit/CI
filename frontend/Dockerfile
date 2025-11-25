################################################################################
# Frontend Dockerfile - Production Grade
# Multi-stage build with proper versioning, labels, and security
################################################################################

# Build arguments for versioning and metadata
ARG NODE_VERSION=20
ARG NGINX_VERSION=1.25-alpine
ARG BUILD_DATE
ARG BUILD_VERSION=dev
ARG GIT_COMMIT=unknown
ARG GIT_BRANCH=unknown

################################################################################
# Stage 1: Builder - Build React application
################################################################################
FROM node:${NODE_VERSION}-alpine as builder

# Set build arguments for this stage
ARG BUILD_DATE
ARG BUILD_VERSION
ARG GIT_COMMIT
ARG NODE_VERSION

WORKDIR /app

# Copy package files for dependency installation
COPY package.json package-lock.json* ./

# Install dependencies with clean install for reproducibility
RUN npm ci --only=production=false

# Copy source code and configuration
COPY . .

# Create version info file
RUN echo "{\
  \"version\": \"${BUILD_VERSION}\",\
  \"commit\": \"${GIT_COMMIT}\",\
  \"build_date\": \"${BUILD_DATE}\",\
  \"node_version\": \"${NODE_VERSION}\"\
}" > /app/public/version.json

# Build the production application
# This creates the /app/dist directory
RUN npm run build

# Verify build output
RUN ls -la /app/dist && \
    echo "Build completed successfully" && \
    echo "Version: ${BUILD_VERSION}" && \
    echo "Commit: ${GIT_COMMIT}"

################################################################################
# Stage 2: Runtime - Serve with Nginx
################################################################################
FROM nginx:${NGINX_VERSION}

# Re-declare ARGs for this stage
ARG BUILD_DATE
ARG BUILD_VERSION=dev
ARG GIT_COMMIT=unknown
ARG GIT_BRANCH=unknown
ARG NODE_VERSION
ARG NGINX_VERSION

# OCI Labels - Standard container metadata
# https://github.com/opencontainers/image-spec/blob/main/annotations.md
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.authors="DevOps Team" \
      org.opencontainers.image.url="https://github.com/orshalit/CI" \
      org.opencontainers.image.source="https://github.com/orshalit/CI" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.vendor="Your Organization" \
      org.opencontainers.image.title="Frontend Application" \
      org.opencontainers.image.description="React frontend served with Nginx" \
      org.opencontainers.image.documentation="https://github.com/orshalit/CI/blob/main/README.md" \
      org.opencontainers.image.base.name="nginx:${NGINX_VERSION}" \
      # Custom labels
      app.version="${BUILD_VERSION}" \
      app.git.commit="${GIT_COMMIT}" \
      app.git.branch="${GIT_BRANCH}" \
      app.build.date="${BUILD_DATE}" \
      app.node.version="${NODE_VERSION}" \
      app.nginx.version="${NGINX_VERSION}"

# Create non-root user for security
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

# Create necessary directories with proper permissions
RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run /usr/share/nginx/html && \
    chown -R appuser:appuser /var/cache/nginx /var/log/nginx /var/run /usr/share/nginx/html && \
    chmod -R 755 /var/cache/nginx /var/log/nginx /usr/share/nginx/html && \
    # Remove default nginx content
    rm -rf /usr/share/nginx/html/*

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy built application from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html
COPY --from=builder /app/public/version.json /usr/share/nginx/html/version.json

# Ensure proper ownership
RUN chown -R appuser:appuser /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

# Create version info file in root for easy access
RUN echo "Frontend Version: ${BUILD_VERSION}" > /usr/share/nginx/html/build-info.txt && \
    echo "Commit: ${GIT_COMMIT}" >> /usr/share/nginx/html/build-info.txt && \
    echo "Build Date: ${BUILD_DATE}" >> /usr/share/nginx/html/build-info.txt && \
    chown appuser:appuser /usr/share/nginx/html/build-info.txt

# Set environment variables for version info
ENV APP_VERSION="${BUILD_VERSION}" \
    GIT_COMMIT="${GIT_COMMIT}" \
    BUILD_DATE="${BUILD_DATE}"

# Switch to non-root user
USER appuser

# Expose application port
EXPOSE 3000

# Health check - verifies nginx is serving content
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/ || exit 1

# Display version information
RUN cat /usr/share/nginx/html/version.json && \
    echo "Frontend container ready"

# Start nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
