#!/bin/bash
# Sync Dhall cache with remote sources
# This ensures cached versions are up-to-date and available as fallback

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$BASE_DIR/dhall/cache"

echo "::notice::Syncing Dhall cache..."

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Sync Service.dhall from DEVOPS repo
echo "::notice::Caching Service.dhall..."
SERVICE_URL="https://raw.githubusercontent.com/orshalit/DEVOPS/main/config/types/Service.dhall"
if curl -f -L "$SERVICE_URL" -o "$CACHE_DIR/Service.dhall.tmp" 2>/dev/null; then
  mv "$CACHE_DIR/Service.dhall.tmp" "$CACHE_DIR/Service.dhall"
  echo "::notice::✓ Service.dhall cached successfully"
else
  echo "::warning::Failed to cache Service.dhall from remote, keeping existing cache"
fi

# Cache Prelude using dhall freeze (if dhall is available)
if command -v dhall &> /dev/null; then
  echo "::notice::Caching Dhall Prelude..."
  # Use dhall's built-in cache mechanism
  dhall freeze --all --cache "$CACHE_DIR" https://prelude.dhall-lang.org/v21.0.0/package.dhall 2>/dev/null || {
    echo "::warning::Failed to freeze Prelude, will use remote import"
  }
else
  echo "::notice::dhall not available, skipping Prelude cache (will use remote)"
fi

echo "::notice::✓ Dhall cache sync complete"

