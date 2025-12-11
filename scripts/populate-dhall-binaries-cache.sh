#!/bin/bash
# Populate dhall/cache/binaries/ with Linux binaries for fallback
# This script downloads and commits Dhall binaries to the repository cache
# Run this when you want to update the cached binaries
#
# Official Sources:
# - Documentation: https://docs.dhall-lang.org/
# - GitHub Releases: https://github.com/dhall-lang/dhall-haskell/releases
# - Installation Guide: https://docs.dhall-lang.org/tutorials/Getting-started_Generate-JSON-or-YAML.html#installation
#
# Usage: ./scripts/populate-dhall-binaries-cache.sh
# Requirements: Linux environment (or WSL), curl, tar, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$REPO_ROOT/dhall/cache/binaries"
DHALL_VERSION="1.41.2"

# Official GitHub releases URLs (from dhall-lang/dhall-haskell)
# These match the official installation documentation
DHALL_REPO="dhall-lang/dhall-haskell"
DHALL_RELEASES_URL="https://github.com/${DHALL_REPO}/releases"
DHALL_DOWNLOAD_BASE="https://github.com/${DHALL_REPO}/releases/download"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    log_warn "This script is designed for Linux. You're running on: $OSTYPE"
    log_warn "Consider running in WSL or GitHub Actions"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create cache directory
mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

log_info "Populating Dhall binaries cache (version $DHALL_VERSION)"
log_info "Cache directory: $CACHE_DIR"

# Download dhall binary
# Official download URL format: https://github.com/dhall-lang/dhall-haskell/releases/download/VERSION/dhall-VERSION-x86_64-linux.tar.bz2
log_info "Downloading dhall v$DHALL_VERSION from official GitHub releases..."
log_info "Release page: ${DHALL_RELEASES_URL}/tag/${DHALL_VERSION}"
DHALL_URL="${DHALL_DOWNLOAD_BASE}/${DHALL_VERSION}/dhall-${DHALL_VERSION}-x86_64-linux.tar.bz2"

if ! curl -L -f "$DHALL_URL" -o dhall.tar.bz2; then
    log_error "Failed to download dhall from: $DHALL_URL"
    exit 1
fi

# Extract dhall
log_info "Extracting dhall..."
if ! tar -xjf dhall.tar.bz2; then
    log_error "Failed to extract dhall archive"
    exit 1
fi

# Copy dhall binary
if [ -f "./bin/dhall" ]; then
    cp ./bin/dhall "$CACHE_DIR/dhall"
    chmod +x "$CACHE_DIR/dhall"
    log_info "✓ dhall binary cached: $CACHE_DIR/dhall"
    
    # Verify it works
    if "$CACHE_DIR/dhall" --version > /dev/null 2>&1; then
        VERSION=$("$CACHE_DIR/dhall" --version)
        log_info "  Verified version: $VERSION"
    else
        log_warn "  Binary exists but version check failed"
    fi
else
    log_error "dhall binary not found after extraction"
    exit 1
fi

# Download dhall-json binary
# dhall-json is included in the same release but with different versioning
# We use the GitHub API to find the correct asset name
log_info "Finding dhall-json download URL from official release..."
log_info "API: https://api.github.com/repos/${DHALL_REPO}/releases/tags/${DHALL_VERSION}"
API_RESPONSE=$(curl -s "https://api.github.com/repos/${DHALL_REPO}/releases/tags/${DHALL_VERSION}")

if [ -z "$API_RESPONSE" ] || [ "$API_RESPONSE" = "null" ]; then
    log_error "Failed to fetch GitHub API response"
    exit 1
fi

# Find dhall-json asset (case-insensitive)
JSON_URL=$(echo "$API_RESPONSE" | jq -r '.assets[] | select(.name | test("dhall-json.*x86_64.*linux"; "i")) | .browser_download_url' | head -1)

if [ -z "$JSON_URL" ] || [ "$JSON_URL" = "null" ]; then
    log_error "Could not find dhall-json download URL"
    log_error "Available assets:"
    echo "$API_RESPONSE" | jq -r '.assets[].name' | grep -i "linux" | head -10 || echo "  (none found)"
    exit 1
fi

log_info "Downloading dhall-json from: $JSON_URL"

# Determine archive format
DOWNLOAD_FILE=""
EXTRACT_CMD=""

if echo "$JSON_URL" | grep -q "\.tar\.bz2"; then
    DOWNLOAD_FILE="dhall-json.tar.bz2"
    EXTRACT_CMD="tar -xjf"
elif echo "$JSON_URL" | grep -q "\.tar\.gz"; then
    DOWNLOAD_FILE="dhall-json.tar.gz"
    EXTRACT_CMD="tar -xzf"
else
    log_error "Unknown archive format: $JSON_URL"
    exit 1
fi

if ! curl -L -f "$JSON_URL" -o "$DOWNLOAD_FILE"; then
    log_error "Failed to download dhall-json"
    exit 1
fi

# Extract dhall-json
log_info "Extracting dhall-json..."
if ! $EXTRACT_CMD "$DOWNLOAD_FILE"; then
    log_error "Failed to extract dhall-json archive"
    exit 1
fi

# Copy dhall-to-json binary
if [ -f "./bin/dhall-to-json" ]; then
    cp ./bin/dhall-to-json "$CACHE_DIR/dhall-to-json"
    chmod +x "$CACHE_DIR/dhall-to-json"
    log_info "✓ dhall-to-json binary cached: $CACHE_DIR/dhall-to-json"
    
    # Verify it works
    if "$CACHE_DIR/dhall-to-json" --version > /dev/null 2>&1; then
        VERSION=$("$CACHE_DIR/dhall-to-json" --version)
        log_info "  Verified version: $VERSION"
    else
        log_warn "  Binary exists but version check failed"
    fi
else
    log_error "dhall-to-json binary not found after extraction"
    exit 1
fi

# Cleanup temporary files
log_info "Cleaning up temporary files..."
rm -f dhall.tar.bz2 dhall-json.tar.* bin/* 2>/dev/null || true
rmdir bin 2>/dev/null || true

log_info ""
log_info "✓ Cache populated successfully!"
log_info ""
log_info "Files cached:"
ls -lh "$CACHE_DIR"/{dhall,dhall-to-json} 2>/dev/null || true
log_info ""
log_info "Source information:"
log_info "  Official docs: https://docs.dhall-lang.org/"
log_info "  GitHub releases: ${DHALL_RELEASES_URL}"
log_info "  Version: ${DHALL_VERSION}"
log_info ""
log_info "Next steps:"
log_info "1. Review the binaries: ls -lh $CACHE_DIR"
log_info "2. Test the install script: ./scripts/install-dhall-with-fallback.sh"
log_info "3. Commit the binaries:"
log_info "   git add dhall/cache/binaries/{dhall,dhall-to-json}"
log_info "   git commit -m 'chore: Add Dhall binaries to cache for fallback (v${DHALL_VERSION})'"

