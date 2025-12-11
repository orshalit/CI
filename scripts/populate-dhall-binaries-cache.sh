#!/bin/bash
# Populate Dhall binaries cache in the repository
# Run this manually when you want to update the cached binaries
# This creates a stable fallback that's committed to the repo

set -euo pipefail

DHALL_VERSION="1.41.2"
CACHE_DIR="dhall/cache/binaries"
TEMP_DIR=$(mktemp -d)

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

echo "::notice::Populating Dhall binaries cache..."

# Create cache directory
mkdir -p "$CACHE_DIR"

# Download and cache dhall
echo "::notice::Downloading dhall v$DHALL_VERSION..."
if curl -L -f "https://github.com/dhall-lang/dhall-haskell/releases/download/${DHALL_VERSION}/dhall-${DHALL_VERSION}-x86_64-linux.tar.bz2" \
    -o "$TEMP_DIR/dhall.tar.bz2" 2>/dev/null; then
    cd "$TEMP_DIR"
    tar -xjf dhall.tar.bz2
    if [ -f ./bin/dhall ]; then
        cp ./bin/dhall "$CACHE_DIR/dhall"
        chmod +x "$CACHE_DIR/dhall"
        echo "::notice::✓ Cached dhall binary"
        "$CACHE_DIR/dhall" --version
    else
        echo "::error::dhall binary not found in archive"
        exit 1
    fi
    cd - > /dev/null
else
    echo "::error::Failed to download dhall"
    exit 1
fi

# Download and cache dhall-json
echo "::notice::Downloading dhall-json v$DHALL_VERSION..."
JSON_URL=$(curl -s "https://api.github.com/repos/dhall-lang/dhall-haskell/releases/tags/${DHALL_VERSION}" | \
    jq -r '.assets[] | select(.name | contains("dhall-json") and contains("x86_64-linux")) | .browser_download_url' | head -1)

if [ -z "$JSON_URL" ] || [ "$JSON_URL" = "null" ]; then
    echo "::error::Could not find dhall-json release URL"
    exit 1
fi

echo "::notice::Found dhall-json at: $JSON_URL"
if echo "$JSON_URL" | grep -q "\.tar\.bz2"; then
    if curl -L -f "$JSON_URL" -o "$TEMP_DIR/dhall-json.tar.bz2" 2>/dev/null; then
        cd "$TEMP_DIR"
        tar -xjf dhall-json.tar.bz2
        if [ -f ./bin/dhall-to-json ]; then
            cp ./bin/dhall-to-json "$CACHE_DIR/dhall-to-json"
            chmod +x "$CACHE_DIR/dhall-to-json"
            echo "::notice::✓ Cached dhall-to-json binary"
            "$CACHE_DIR/dhall-to-json" --version
        else
            echo "::error::dhall-to-json binary not found in archive"
            exit 1
        fi
        cd - > /dev/null
    else
        echo "::error::Failed to download dhall-json"
        exit 1
    fi
elif echo "$JSON_URL" | grep -q "\.tar\.gz"; then
    if curl -L -f "$JSON_URL" -o "$TEMP_DIR/dhall-json.tar.gz" 2>/dev/null; then
        cd "$TEMP_DIR"
        tar -xzf dhall-json.tar.gz
        if [ -f ./bin/dhall-to-json ]; then
            cp ./bin/dhall-to-json "$CACHE_DIR/dhall-to-json"
            chmod +x "$CACHE_DIR/dhall-to-json"
            echo "::notice::✓ Cached dhall-to-json binary"
            "$CACHE_DIR/dhall-to-json" --version
        else
            echo "::error::dhall-to-json binary not found in archive"
            exit 1
        fi
        cd - > /dev/null
    else
        echo "::error::Failed to download dhall-json"
        exit 1
    fi
else
    echo "::error::Unknown archive format: $JSON_URL"
    exit 1
fi

echo "::notice::✓ Dhall binaries cache populated successfully"
echo "::notice::Cache location: $CACHE_DIR"
ls -lh "$CACHE_DIR"

