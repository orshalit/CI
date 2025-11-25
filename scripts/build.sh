#!/usr/bin/env bash
################################################################################
# Docker Build Script - Production Grade
# 
# This script builds Docker images with proper versioning and metadata.
# It automatically captures git information and build timestamps.
#
# Usage:
#   ./scripts/build.sh [OPTIONS]
#
# Options:
#   --version VERSION    Set build version (default: git tag or 'dev')
#   --tag TAG           Additional Docker tag (default: 'latest')
#   --push              Push images to registry
#   --registry URL      Registry URL (default: none)
#   --backend-only      Build only backend
#   --frontend-only     Build only frontend
#   --no-cache          Build without Docker cache
#   --help              Show this help message
#
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
BUILD_VERSION=""
DOCKER_TAG="latest"
PUSH_IMAGES=false
REGISTRY=""
BUILD_BACKEND=true
BUILD_FRONTEND=true
NO_CACHE=""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    grep "^#" "$0" | grep -v "^#!/" | sed 's/^# \?//'
    exit 0
}

################################################################################
# Parse Arguments
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            BUILD_VERSION="$2"
            shift 2
            ;;
        --tag)
            DOCKER_TAG="$2"
            shift 2
            ;;
        --push)
            PUSH_IMAGES=true
            shift
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --backend-only)
            BUILD_BACKEND=true
            BUILD_FRONTEND=false
            shift
            ;;
        --frontend-only)
            BUILD_BACKEND=false
            BUILD_FRONTEND=true
            shift
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            ;;
    esac
done

################################################################################
# Gather Build Metadata
################################################################################

log_info "Gathering build metadata..."

# Get git information
if command -v git &> /dev/null && [ -d "${PROJECT_ROOT}/.git" ]; then
    GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    GIT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
    GIT_DIRTY=$(git diff --quiet || echo "-dirty")
else
    log_warning "Git not available or not a git repository"
    GIT_COMMIT="unknown"
    GIT_BRANCH="unknown"
    GIT_TAG=""
    GIT_DIRTY=""
fi

# Determine build version
if [ -z "$BUILD_VERSION" ]; then
    if [ -n "$GIT_TAG" ]; then
        BUILD_VERSION="$GIT_TAG"
    elif [ "$GIT_BRANCH" == "main" ] || [ "$GIT_BRANCH" == "master" ]; then
        BUILD_VERSION="main-${GIT_COMMIT}"
    else
        BUILD_VERSION="dev-${GIT_COMMIT}"
    fi
    BUILD_VERSION="${BUILD_VERSION}${GIT_DIRTY}"
fi

# Build timestamp (ISO 8601 format)
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Display build info
echo ""
log_info "Build Information:"
echo "  Version:     ${BUILD_VERSION}"
echo "  Git Commit:  ${GIT_COMMIT}${GIT_DIRTY}"
echo "  Git Branch:  ${GIT_BRANCH}"
echo "  Build Date:  ${BUILD_DATE}"
echo "  Docker Tag:  ${DOCKER_TAG}"
echo ""

################################################################################
# Build Docker Images
################################################################################

# Common build arguments
COMMON_BUILD_ARGS=(
    --build-arg "BUILD_DATE=${BUILD_DATE}"
    --build-arg "BUILD_VERSION=${BUILD_VERSION}"
    --build-arg "GIT_COMMIT=${GIT_COMMIT}"
    --build-arg "GIT_BRANCH=${GIT_BRANCH}"
)

# Determine image names
if [ -n "$REGISTRY" ]; then
    BACKEND_IMAGE="${REGISTRY}/backend"
    FRONTEND_IMAGE="${REGISTRY}/frontend"
else
    BACKEND_IMAGE="ci-backend"
    FRONTEND_IMAGE="ci-frontend"
fi

# Build Backend
if [ "$BUILD_BACKEND" = true ]; then
    log_info "Building backend image..."
    
    docker build \
        ${NO_CACHE} \
        "${COMMON_BUILD_ARGS[@]}" \
        -t "${BACKEND_IMAGE}:${DOCKER_TAG}" \
        -t "${BACKEND_IMAGE}:${BUILD_VERSION}" \
        -f "${PROJECT_ROOT}/backend/Dockerfile" \
        "${PROJECT_ROOT}/backend"
    
    log_success "Backend image built successfully"
    
    # Inspect image labels
    log_info "Backend image labels:"
    docker inspect "${BACKEND_IMAGE}:${DOCKER_TAG}" \
        --format='{{json .Config.Labels}}' | jq '.' || true
fi

# Build Frontend
if [ "$BUILD_FRONTEND" = true ]; then
    log_info "Building frontend image..."
    
    docker build \
        ${NO_CACHE} \
        "${COMMON_BUILD_ARGS[@]}" \
        -t "${FRONTEND_IMAGE}:${DOCKER_TAG}" \
        -t "${FRONTEND_IMAGE}:${BUILD_VERSION}" \
        -f "${PROJECT_ROOT}/frontend/Dockerfile" \
        "${PROJECT_ROOT}/frontend"
    
    log_success "Frontend image built successfully"
    
    # Inspect image labels
    log_info "Frontend image labels:"
    docker inspect "${FRONTEND_IMAGE}:${DOCKER_TAG}" \
        --format='{{json .Config.Labels}}' | jq '.' || true
fi

################################################################################
# Push Images (Optional)
################################################################################

if [ "$PUSH_IMAGES" = true ]; then
    if [ -z "$REGISTRY" ]; then
        log_error "Cannot push without --registry specified"
        exit 1
    fi
    
    log_info "Pushing images to registry..."
    
    if [ "$BUILD_BACKEND" = true ]; then
        docker push "${BACKEND_IMAGE}:${DOCKER_TAG}"
        docker push "${BACKEND_IMAGE}:${BUILD_VERSION}"
        log_success "Backend images pushed"
    fi
    
    if [ "$BUILD_FRONTEND" = true ]; then
        docker push "${FRONTEND_IMAGE}:${DOCKER_TAG}"
        docker push "${FRONTEND_IMAGE}:${BUILD_VERSION}"
        log_success "Frontend images pushed"
    fi
fi

################################################################################
# Summary
################################################################################

echo ""
log_success "Build complete!"
echo ""
echo "Images built:"
if [ "$BUILD_BACKEND" = true ]; then
    echo "  - ${BACKEND_IMAGE}:${DOCKER_TAG}"
    echo "  - ${BACKEND_IMAGE}:${BUILD_VERSION}"
fi
if [ "$BUILD_FRONTEND" = true ]; then
    echo "  - ${FRONTEND_IMAGE}:${DOCKER_TAG}"
    echo "  - ${FRONTEND_IMAGE}:${BUILD_VERSION}"
fi
echo ""

# Show how to run the images
log_info "To run the built images:"
if [ "$BUILD_BACKEND" = true ]; then
    echo "  Backend:  docker run -p 8000:8000 ${BACKEND_IMAGE}:${DOCKER_TAG}"
fi
if [ "$BUILD_FRONTEND" = true ]; then
    echo "  Frontend: docker run -p 3000:3000 ${FRONTEND_IMAGE}:${DOCKER_TAG}"
fi
echo ""

# Show how to check version
log_info "To check image version:"
if [ "$BUILD_BACKEND" = true ]; then
    echo "  Backend:  docker run --rm ${BACKEND_IMAGE}:${DOCKER_TAG} cat /app/version.json"
fi
if [ "$BUILD_FRONTEND" = true ]; then
    echo "  Frontend: docker run --rm ${FRONTEND_IMAGE}:${DOCKER_TAG} cat /usr/share/nginx/html/version.json"
fi
echo ""

