#!/bin/bash
################################################################################
# EC2 Deployment Script
#
# This script is executed on the EC2 instance via AWS SSM Run Command.
# It deploys the application using Docker Compose with:
# - Image pulling from GitHub Container Registry (GHCR)
# - Graceful container shutdown
# - Health check verification
# - Automatic rollback on failure
#
# Environment Variables (passed from GitHub Actions):
# - DEPLOY_VERSION: Docker image tag to deploy
# - DEPLOY_COMMIT: Git commit SHA
# - GITHUB_OWNER: GitHub organization/user
# - GITHUB_REPO: GitHub repository name
# - GITHUB_TOKEN: GitHub token for GHCR authentication
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ============================================================================
# Configuration
# ============================================================================

# Deployment directory (where docker-compose.prod.yml is located)
DEPLOY_DIR="/opt/ci-app"

# Log file
LOG_FILE="/var/log/ci-deploy.log"

# Docker Compose file
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.prod.yml"

# Rollback state file
ROLLBACK_FILE="${DEPLOY_DIR}/.last-successful-deployment"

# Health check configuration
HEALTH_CHECK_TIMEOUT=120  # seconds
HEALTH_CHECK_INTERVAL=5   # seconds

# Container registry
GHCR_REGISTRY="ghcr.io"

# ============================================================================
# Logging Functions
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_success() {
    log "SUCCESS" "$@"
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_environment() {
    log_info "Validating environment..."
    
    # Check required environment variables
    local required_vars=("DEPLOY_VERSION" "GITHUB_OWNER" "GITHUB_REPO" "GITHUB_TOKEN")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable ${var} is not set"
            exit 1
        fi
    done
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        exit 1
    fi
    
    # Check deployment directory
    if [ ! -d "${DEPLOY_DIR}" ]; then
        log_info "Creating deployment directory: ${DEPLOY_DIR}"
        sudo mkdir -p "${DEPLOY_DIR}"
        sudo chown "$(whoami):$(whoami)" "${DEPLOY_DIR}"
    fi
    
    log_success "Environment validation passed"
}

# ============================================================================
# Docker Functions
# ============================================================================

login_to_ghcr() {
    log_info "Authenticating to GitHub Container Registry..."
    
    # Login to GHCR using GitHub token
    echo "${GITHUB_TOKEN}" | docker login "${GHCR_REGISTRY}" \
        -u "${GITHUB_OWNER}" \
        --password-stdin >> "${LOG_FILE}" 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Successfully authenticated to GHCR"
    else
        log_error "Failed to authenticate to GHCR"
        exit 1
    fi
}

pull_images() {
    log_info "Pulling Docker images for version: ${DEPLOY_VERSION}"
    
    local backend_image="${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-backend:${DEPLOY_VERSION}"
    local frontend_image="${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-frontend:${DEPLOY_VERSION}"
    
    # Pull backend image
    log_info "Pulling backend image: ${backend_image}"
    if docker pull "${backend_image}"; then
        log_success "Backend image pulled successfully"
    else
        log_error "Failed to pull backend image"
        exit 1
    fi
    
    # Pull frontend image
    log_info "Pulling frontend image: ${frontend_image}"
    if docker pull "${frontend_image}"; then
        log_success "Frontend image pulled successfully"
    else
        log_error "Failed to pull frontend image"
        exit 1
    fi
}

# ============================================================================
# Deployment Functions
# ============================================================================

save_current_state() {
    log_info "Saving current deployment state for rollback..."
    
    # Get currently running versions
    local current_backend_image
    local current_frontend_image
    
    current_backend_image=$(docker ps --filter "name=backend" --format "{{.Image}}" 2>/dev/null || echo "none")
    current_frontend_image=$(docker ps --filter "name=frontend" --format "{{.Image}}" 2>/dev/null || echo "none")
    
    # Save to rollback file
    cat > "${ROLLBACK_FILE}" <<EOF
BACKEND_IMAGE=${current_backend_image}
FRONTEND_IMAGE=${current_frontend_image}
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    
    log_info "Current state saved (backend: ${current_backend_image}, frontend: ${current_frontend_image})"
}

create_docker_compose_env() {
    log_info "Creating Docker Compose environment file..."
    
    # Load existing environment variables if .env exists
    if [ -f "${DEPLOY_DIR}/.env" ]; then
        source "${DEPLOY_DIR}/.env" 2>/dev/null || true
    fi
    
    # Create .env file for docker-compose
    cat > "${DEPLOY_DIR}/.env" <<EOF
# Auto-generated by deployment script
# DO NOT EDIT MANUALLY - Last updated: $(date)

# Build metadata
BUILD_VERSION=${DEPLOY_VERSION}
GIT_COMMIT=${DEPLOY_COMMIT:-unknown}

# Docker images (set by deployment script)
BACKEND_IMAGE=${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-backend:${DEPLOY_VERSION}
FRONTEND_IMAGE=${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-frontend:${DEPLOY_VERSION}

# Database configuration (using containerized Postgres for now)
# TODO: Migrate to RDS in future
POSTGRES_USER=${POSTGRES_USER:-appuser}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-apppassword}
POSTGRES_DB=${POSTGRES_DB:-appdb}
POSTGRES_PORT=5432

# Application ports
BACKEND_PORT=8000
FRONTEND_PORT=3000

# Application configuration
CORS_ORIGINS=${CORS_ORIGINS:-http://localhost:3000}
SECRET_KEY=${SECRET_KEY:-change-in-production-please}
LOG_LEVEL=${LOG_LEVEL:-INFO}
LOG_FORMAT=json
RATE_LIMIT_ENABLED=true
RATE_LIMIT_PER_MINUTE=60
DATABASE_POOL_SIZE=5
DATABASE_MAX_OVERFLOW=10

# Frontend configuration
VITE_BACKEND_URL=http://localhost:8000
EOF
    
    log_success "Docker Compose environment file created"
}

deploy_containers() {
    log_info "Deploying containers with Docker Compose..."
    
    cd "${DEPLOY_DIR}" || exit 1
    
    # Export environment variables for docker-compose
    export BUILD_VERSION="${DEPLOY_VERSION}"
    export GIT_COMMIT="${DEPLOY_COMMIT:-unknown}"
    
    # Set image references to the images we just pulled
    export BACKEND_IMAGE="${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-backend:${DEPLOY_VERSION}"
    export FRONTEND_IMAGE="${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-frontend:${DEPLOY_VERSION}"
    
    log_info "Using images:"
    log_info "  Backend: ${BACKEND_IMAGE}"
    log_info "  Frontend: ${FRONTEND_IMAGE}"
    
    log_info "Stopping old containers gracefully..."
    docker compose -f "${COMPOSE_FILE}" down --timeout 30 >> "${LOG_FILE}" 2>&1 || true
    
    log_info "Starting new containers..."
    if docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans >> "${LOG_FILE}" 2>&1; then
        log_success "Containers started successfully"
    else
        log_error "Failed to start containers"
        return 1
    fi
}

# ============================================================================
# Health Check Functions
# ============================================================================

wait_for_service() {
    local service_name="$1"
    local health_url="$2"
    local timeout="$3"
    
    log_info "Waiting for ${service_name} to be healthy (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [ ${elapsed} -lt ${timeout} ]; do
        if curl -f -s "${health_url}" > /dev/null 2>&1; then
            log_success "${service_name} is healthy"
            return 0
        fi
        
        sleep ${HEALTH_CHECK_INTERVAL}
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        
        if [ $((elapsed % 20)) -eq 0 ]; then
            log_info "Still waiting for ${service_name}... (${elapsed}s / ${timeout}s)"
        fi
    done
    
    log_error "${service_name} health check timed out after ${timeout}s"
    return 1
}

verify_deployment() {
    log_info "Verifying deployment health..."
    
    local all_healthy=true
    
    # Wait a moment for containers to start
    sleep 5
    
    # Check database
    log_info "Checking database..."
    if docker exec database pg_isready -U appuser -d appdb >> "${LOG_FILE}" 2>&1; then
        log_success "Database is healthy"
    else
        log_error "Database is not healthy"
        all_healthy=false
    fi
    
    # Check backend
    if ! wait_for_service "Backend" "http://localhost:8000/health" ${HEALTH_CHECK_TIMEOUT}; then
        all_healthy=false
    fi
    
    # Check frontend
    if ! wait_for_service "Frontend" "http://localhost:3000/" ${HEALTH_CHECK_TIMEOUT}; then
        all_healthy=false
    fi
    
    # Verify versions
    log_info "Verifying deployed versions..."
    local backend_version
    backend_version=$(curl -s http://localhost:8000/version 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    
    if [ "${backend_version}" = "${DEPLOY_VERSION}" ]; then
        log_success "Backend version verified: ${backend_version}"
    else
        log_error "Backend version mismatch: expected ${DEPLOY_VERSION}, got ${backend_version}"
        all_healthy=false
    fi
    
    if [ "${all_healthy}" = true ]; then
        log_success "All health checks passed"
        return 0
    else
        log_error "Some health checks failed"
        return 1
    fi
}

# ============================================================================
# Rollback Functions
# ============================================================================

rollback_deployment() {
    log_error "Initiating rollback to previous version..."
    
    if [ ! -f "${ROLLBACK_FILE}" ]; then
        log_error "No rollback state found. Cannot rollback."
        return 1
    fi
    
    # Load previous state
    source "${ROLLBACK_FILE}"
    
    if [ "${BACKEND_IMAGE}" = "none" ] || [ "${FRONTEND_IMAGE}" = "none" ]; then
        log_error "No previous deployment found. Cannot rollback."
        return 1
    fi
    
    log_info "Rolling back to: backend=${BACKEND_IMAGE}, frontend=${FRONTEND_IMAGE}"
    
    cd "${DEPLOY_DIR}" || exit 1
    
    # Set environment variables for rollback
    export BACKEND_IMAGE="${BACKEND_IMAGE}"
    export FRONTEND_IMAGE="${FRONTEND_IMAGE}"
    
    # Rollback
    docker compose -f "${COMPOSE_FILE}" down --timeout 30 >> "${LOG_FILE}" 2>&1 || true
    docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans >> "${LOG_FILE}" 2>&1
    
    log_info "Rollback complete. Please verify manually."
}

# ============================================================================
# Cleanup Functions
# ============================================================================

cleanup() {
    log_info "Performing cleanup..."
    
    # Remove old/dangling images to save space
    log_info "Removing dangling images..."
    docker image prune -f >> "${LOG_FILE}" 2>&1 || true
    
    # Keep only last 3 versions of each image
    log_info "Removing old image versions..."
    docker images "${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-backend" \
        --format "{{.Tag}}" | tail -n +4 | xargs -r -I {} \
        docker rmi "${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-backend:{}" >> "${LOG_FILE}" 2>&1 || true
    
    docker images "${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-frontend" \
        --format "{{.Tag}}" | tail -n +4 | xargs -r -I {} \
        docker rmi "${GHCR_REGISTRY}/${GITHUB_OWNER,,}/ci-frontend:{}" >> "${LOG_FILE}" 2>&1 || true
    
    log_success "Cleanup complete"
}

# ============================================================================
# Main Deployment Flow
# ============================================================================

main() {
    log_info "=========================================="
    log_info "Starting deployment"
    log_info "Version: ${DEPLOY_VERSION}"
    log_info "Commit: ${DEPLOY_COMMIT:-unknown}"
    log_info "Repository: ${GITHUB_OWNER}/${GITHUB_REPO}"
    log_info "=========================================="
    
    # Validate environment
    validate_environment
    
    # Authenticate to registry
    login_to_ghcr
    
    # Save current state for potential rollback
    save_current_state
    
    # Pull new images
    pull_images
    
    # Create environment configuration
    create_docker_compose_env
    
    # Deploy containers
    if ! deploy_containers; then
        log_error "Deployment failed"
        rollback_deployment
        exit 1
    fi
    
    # Verify deployment
    if ! verify_deployment; then
        log_error "Health checks failed"
        rollback_deployment
        exit 1
    fi
    
    # Cleanup old images
    cleanup
    
    log_success "=========================================="
    log_success "Deployment completed successfully!"
    log_success "Version: ${DEPLOY_VERSION}"
    log_success "=========================================="
    
    # Update rollback file with successful deployment
    echo "LAST_SUCCESSFUL_VERSION=${DEPLOY_VERSION}" >> "${ROLLBACK_FILE}"
}

# Execute main function
main "$@"

