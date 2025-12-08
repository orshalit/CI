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
FROM node:${NODE_VERSION}-alpine AS builder

# Set build arguments for this stage
ARG BUILD_DATE
ARG BUILD_VERSION
ARG GIT_COMMIT
ARG NODE_VERSION

WORKDIR /app

# Set Node environment for optimized production build
ENV NODE_ENV=production

# Copy package files first (for better layer caching)
COPY package.json package-lock.json* ./

# Install ALL dependencies (including devDependencies for build)
# Using --ignore-scripts for security, run build separately
RUN npm ci --include=dev --ignore-scripts

# Copy source code (after dependencies for better caching)
COPY . .

# Create version info file
RUN mkdir -p /app/public && \
    echo "{\
  \"version\": \"${BUILD_VERSION}\",\
  \"commit\": \"${GIT_COMMIT}\",\
  \"build_date\": \"${BUILD_DATE}\",\
  \"node_version\": \"${NODE_VERSION}\"\
}" > /app/public/version.json

# Build the production application
# NODE_ENV=production enables React optimizations
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
    adduser -D -u 1000 -G appuser appuser && \
    # Install su-exec for switching users in entrypoint
    apk add --no-cache su-exec

# Create necessary directories with proper permissions
RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run /usr/share/nginx/html && \
    chown -R appuser:appuser /var/cache/nginx /var/log/nginx /var/run /usr/share/nginx/html && \
    chmod -R 755 /var/cache/nginx /var/log/nginx /usr/share/nginx/html && \
    # Remove default nginx content
    rm -rf /usr/share/nginx/html/*

# Copy custom nginx configuration template and entrypoint script
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Copy built application from builder stage
COPY --from=builder --chown=appuser:appuser /app/dist /usr/share/nginx/html
COPY --from=builder --chown=appuser:appuser /app/public/version.json /usr/share/nginx/html/version.json

# Create build info file (as root, before switching user)
RUN echo "Frontend Version: ${BUILD_VERSION}" > /usr/share/nginx/html/build-info.txt && \
    echo "Commit: ${GIT_COMMIT}" >> /usr/share/nginx/html/build-info.txt && \
    echo "Build Date: ${BUILD_DATE}" >> /usr/share/nginx/html/build-info.txt && \
    chown appuser:appuser /usr/share/nginx/html/build-info.txt

# Set environment variables for version info and backend URL
ENV APP_VERSION="${BUILD_VERSION}" \
    GIT_COMMIT="${GIT_COMMIT}" \
    BUILD_DATE="${BUILD_DATE}" \
    BACKEND_API_URL="${BACKEND_API_URL:-https://app.dev.example.com}"

# Expose application port
EXPOSE 3000

# Health check - verifies nginx is serving content
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/ || exit 1

# Keep as root for entrypoint (needs to write to /etc/nginx/)
# Entrypoint will switch to appuser before starting nginx
# Use entrypoint script to inject environment variables into nginx config
ENTRYPOINT ["/docker-entrypoint.sh"]

