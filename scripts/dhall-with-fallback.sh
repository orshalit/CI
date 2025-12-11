#!/bin/bash
# Wrapper script for dhall commands with fallback to cached imports
# Usage: dhall-with-fallback.sh <dhall-command> <args...>

set -euo pipefail

DHALL_CMD="${1:-dhall}"
shift || true

# Set Dhall cache directory
export DHALL_CACHE="${DHALL_CACHE:-$HOME/.cache/dhall}"

# Try to use remote imports first
# If that fails, we'll modify the import paths to use local cache

echo "::notice::Running dhall with fallback support..."

# First, try normal execution
if "$DHALL_CMD" "$@" 2>/tmp/dhall-error.log; then
  exit 0
fi

# Check if error is related to imports
if grep -q "Remote host not found\|Failed to resolve\|Network" /tmp/dhall-error.log; then
  echo "::warning::Remote import failed, attempting fallback to cached versions..."
  
  # For now, we'll need to manually replace imports in the file
  # A better approach would be to use dhall's import system with local cache
  # But Dhall doesn't have built-in fallback, so we'll need to:
  # 1. Pre-cache imports using 'dhall freeze'
  # 2. Or modify import paths programmatically
  
  echo "::error::Remote imports unavailable and fallback not yet implemented"
  echo "::error::Please ensure network connectivity or run 'dhall freeze' to cache imports"
  cat /tmp/dhall-error.log
  exit 1
else
  # Some other error, show it
  cat /tmp/dhall-error.log
  exit 1
fi

