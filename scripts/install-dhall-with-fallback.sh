#!/bin/bash
# Install Dhall and dhall-json with fallback to cached binaries
# This script provides resilience against GitHub releases being unavailable
#
# Fallback order:
# 1. Try GitHub releases (fastest, always latest)
# 2. Try GitHub Actions cache (fast, persists across runs, auto-managed)
# 3. Try repository cache (stable, pre-populated, committed fallback)
#
# Note: Repository cache is NOT updated by this script - it's pre-populated
# and committed. Use populate-dhall-binaries-cache.sh to update it manually.
#
# Usage: scripts/install-dhall-with-fallback.sh

set -euo pipefail

DHALL_VERSION="1.41.2"
# Use absolute path from repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="${DHALL_CACHE_DIR:-$BASE_DIR/dhall/cache/binaries}"
INSTALL_DIR="/usr/local/bin"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}::notice::${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}::warning::${NC} $1"
}

log_error() {
    echo -e "${RED}::error::${NC} $1"
}

# Function to check if a binary exists and works
check_binary() {
    local binary=$1
    if command -v "$binary" &> /dev/null; then
        if "$binary" --version &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

# Function to install from GitHub release
install_from_github() {
    local tool=$1
    local version=$2
    local temp_dir=$(mktemp -d)
    
    # Cleanup on exit
    trap "rm -rf $temp_dir" RETURN
    
    log_info "Attempting to download $tool v$version from GitHub releases..."
    
    if [ "$tool" = "dhall" ]; then
        local url="https://github.com/dhall-lang/dhall-haskell/releases/download/${version}/dhall-${version}-x86_64-linux.tar.bz2"
        if curl -L -f "$url" -o "$temp_dir/dhall.tar.bz2" 2>/dev/null; then
            cd "$temp_dir"
            if tar -xjf dhall.tar.bz2 2>/dev/null; then
                if [ -f ./bin/dhall ]; then
                    sudo mv ./bin/dhall "$INSTALL_DIR/"
                    log_info "✓ Successfully installed dhall from GitHub"
                    return 0
                fi
            fi
            cd - > /dev/null
        fi
    elif [ "$tool" = "dhall-json" ]; then
        # Try to find the correct dhall-json asset
        local json_url=$(curl -s "https://api.github.com/repos/dhall-lang/dhall-haskell/releases/tags/${version}" 2>/dev/null | \
            jq -r '.assets[] | select(.name | contains("dhall-json") and contains("x86_64-linux")) | .browser_download_url' | head -1)
        
        if [ -n "$json_url" ] && [ "$json_url" != "null" ]; then
            log_info "Found dhall-json at: $json_url"
            cd "$temp_dir"
            if echo "$json_url" | grep -q "\.tar\.bz2"; then
                if curl -L -f "$json_url" -o "$temp_dir/dhall-json.tar.bz2" 2>/dev/null; then
                    if tar -xjf dhall-json.tar.bz2 2>/dev/null; then
                        if [ -f ./bin/dhall-to-json ]; then
                            sudo mv ./bin/dhall-to-json "$INSTALL_DIR/"
                            log_info "✓ Successfully installed dhall-to-json from GitHub"
                            cd - > /dev/null
                            return 0
                        fi
                    fi
                fi
            elif echo "$json_url" | grep -q "\.tar\.gz"; then
                if curl -L -f "$json_url" -o "$temp_dir/dhall-json.tar.gz" 2>/dev/null; then
                    if tar -xzf dhall-json.tar.gz 2>/dev/null; then
                        if [ -f ./bin/dhall-to-json ]; then
                            sudo mv ./bin/dhall-to-json "$INSTALL_DIR/"
                            log_info "✓ Successfully installed dhall-to-json from GitHub"
                            cd - > /dev/null
                            return 0
                        fi
                    fi
                fi
            fi
            cd - > /dev/null
        fi
    fi
    
    return 1
}

# Function to install from cache directory
install_from_cache() {
    local tool=$1
    local cache_path=""
    
    if [ "$tool" = "dhall" ]; then
        cache_path="$CACHE_DIR/dhall"
    elif [ "$tool" = "dhall-json" ]; then
        cache_path="$CACHE_DIR/dhall-to-json"
    fi
    
    if [ -f "$cache_path" ] && [ -x "$cache_path" ]; then
        log_info "Installing $tool from cache: $cache_path"
        sudo cp "$cache_path" "$INSTALL_DIR/"
        sudo chmod +x "$INSTALL_DIR/$(basename "$cache_path")"
        log_info "✓ Successfully installed $tool from cache"
        return 0
    fi
    
    return 1
}

# Note: We don't cache binaries on every run - the cache is pre-populated
# and committed to the repo. Use populate-dhall-binaries-cache.sh to update it.

# Main installation logic
install_dhall() {
    if check_binary "dhall"; then
        log_info "dhall already installed: $(dhall --version)"
        return 0
    fi
    
    # Try GitHub first
    if install_from_github "dhall" "$DHALL_VERSION"; then
        return 0
    fi
    
    log_warn "GitHub download failed, trying cache..."
    
    # Fallback to cache
    if install_from_cache "dhall"; then
        return 0
    fi
    
    log_error "Failed to install dhall from GitHub or cache"
    return 1
}

install_dhall_json() {
    if check_binary "dhall-to-json"; then
        log_info "dhall-to-json already installed: $(dhall-to-json --version)"
        return 0
    fi
    
    # Try GitHub first
    if install_from_github "dhall-json" "$DHALL_VERSION"; then
        return 0
    fi
    
    log_warn "GitHub download failed, trying cache..."
    
    # Fallback to cache
    if install_from_cache "dhall-json"; then
        return 0
    fi
    
    log_error "Failed to install dhall-to-json from GitHub or cache"
    return 1
}

# Main execution
main() {
    log_info "Installing Dhall binaries (version $DHALL_VERSION) with fallback support..."
    
    # Install dhall
    if ! install_dhall; then
        log_error "Failed to install dhall"
        exit 1
    fi
    
    # Verify dhall installation
    dhall --version
    
    # Install dhall-json
    if ! install_dhall_json; then
        log_error "Failed to install dhall-to-json"
        exit 1
    fi
    
    # Verify dhall-to-json installation
    dhall-to-json --version
    
    log_info "✓ All Dhall binaries installed successfully"
}

main "$@"

