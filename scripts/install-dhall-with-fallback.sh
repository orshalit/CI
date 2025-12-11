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
        # Note: dhall-json has its own versioning (e.g., 1.7.11) but is released with dhall-haskell
        local api_response=$(curl -s "https://api.github.com/repos/dhall-lang/dhall-haskell/releases/tags/${version}" 2>/dev/null)
        
        # Check if API response is valid JSON
        if [ -z "$api_response" ] || [ "$api_response" = "null" ]; then
            log_warn "Failed to fetch GitHub API response for dhall-json"
            return 1
        fi
        
        # Validate JSON response
        if ! echo "$api_response" | jq empty 2>/dev/null; then
            log_warn "GitHub API response is not valid JSON"
            log_warn "Response preview: $(echo "$api_response" | head -c 200)"
            return 1
        fi
        
        # Check if release exists
        if echo "$api_response" | jq -e '.message' >/dev/null 2>&1; then
            local error_msg=$(echo "$api_response" | jq -r '.message' 2>/dev/null)
            log_warn "GitHub API error: $error_msg"
            return 1
        fi
        
        # Match dhall-json asset (case-insensitive for Linux/Linux)
        # Asset format: dhall-json-1.7.11-x86_64-Linux.tar.bz2 (note: capital L in Linux)
        local json_url=$(echo "$api_response" | jq -r '.assets[] | select(.name | test("dhall-json.*x86_64.*linux"; "i")) | .browser_download_url' 2>/dev/null | head -1)
        
        if [ -z "$json_url" ] || [ "$json_url" = "null" ] || [ "$json_url" = "" ]; then
            log_warn "Could not find dhall-json download URL in GitHub release"
            log_warn "Available assets:"
            if echo "$api_response" | jq -e '.assets' >/dev/null 2>&1; then
                echo "$api_response" | jq -r '.assets[].name' 2>/dev/null | grep -i "linux" | head -10 || echo "  (no Linux assets found)"
            else
                echo "  (no assets array in response)"
            fi
            return 1
        fi
        
        log_info "Found dhall-json at: $json_url"
        cd "$temp_dir"
        
        local download_file=""
        local extract_cmd=""
        
        if echo "$json_url" | grep -q "\.tar\.bz2"; then
            download_file="dhall-json.tar.bz2"
            extract_cmd="tar -xjf"
        elif echo "$json_url" | grep -q "\.tar\.gz"; then
            download_file="dhall-json.tar.gz"
            extract_cmd="tar -xzf"
        else
            log_warn "Unknown archive format: $json_url"
            cd - > /dev/null
            return 1
        fi
        
        if ! curl -L -f "$json_url" -o "$temp_dir/$download_file" 2>/dev/null; then
            log_warn "Failed to download dhall-json from: $json_url"
            cd - > /dev/null
            return 1
        fi
        
        if ! $extract_cmd "$temp_dir/$download_file" 2>/dev/null; then
            log_warn "Failed to extract dhall-json archive"
            cd - > /dev/null
            return 1
        fi
        
        if [ -f ./bin/dhall-to-json ]; then
            sudo mv ./bin/dhall-to-json "$INSTALL_DIR/"
            log_info "✓ Successfully installed dhall-to-json from GitHub"
            cd - > /dev/null
            return 0
        else
            log_warn "dhall-to-json binary not found after extraction"
            log_warn "Contents of extracted directory:"
            ls -la ./bin/ 2>/dev/null || ls -la ./ 2>/dev/null || echo "  (directory not found)"
            cd - > /dev/null
            return 1
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
    
    # Fallback to cache (GitHub Actions cache or repository cache)
    if install_from_cache "dhall-json"; then
        return 0
    fi
    
    log_error "Failed to install dhall-to-json from GitHub or cache"
    log_error "Cache directory checked: $CACHE_DIR"
    if [ -d "$CACHE_DIR" ]; then
        log_error "Cache directory exists but is empty or binary not found"
        ls -la "$CACHE_DIR" 2>/dev/null || log_error "Could not list cache directory"
    else
        log_error "Cache directory does not exist"
    fi
    log_error "To fix: Populate cache with: bash scripts/populate-dhall-binaries-cache.sh (if script exists)"
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

