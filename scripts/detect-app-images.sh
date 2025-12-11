#!/bin/bash
# Detect which Docker images need to be built based on application structure.
# Pure bash implementation - no Python dependencies needed.
#
# Usage: scripts/detect-app-images.sh [--format matrix|json|list] [--no-shared]

set -euo pipefail

FORMAT="${1:-matrix}"
NO_SHARED="${2:-}"

BASE_DIR="."
MATRIX_ITEMS=()

# Function to add a matrix item
add_matrix_item() {
    local service=$1
    local type=$2
    local app="${3:-}"
    local context=$4
    local image_name=$5
    local dockerfile=$6
    
    local item="{\"service\":\"$service\",\"type\":\"$type\""
    if [ -n "$app" ]; then
        item="$item,\"app\":\"$app\""
    fi
    item="$item,\"context\":\"$context\",\"image_name\":\"$image_name\",\"dockerfile\":\"$dockerfile\"}"
    MATRIX_ITEMS+=("$item")
}

# Check for shared backend/frontend (legacy support)
if [ -z "$NO_SHARED" ]; then
    if [ -d "$BASE_DIR/backend" ] && [ -f "$BASE_DIR/backend/Dockerfile" ]; then
        add_matrix_item "backend" "shared" "" "./backend" "ci-backend" "./backend/Dockerfile"
    fi
    
    if [ -d "$BASE_DIR/frontend" ] && [ -f "$BASE_DIR/frontend/Dockerfile" ]; then
        add_matrix_item "frontend" "shared" "" "./frontend" "ci-frontend" "./frontend/Dockerfile"
    fi
fi

# Scan applications directory for app-specific images
if [ -d "$BASE_DIR/applications" ]; then
    while IFS= read -r app_dir; do
        app_name=$(basename "$app_dir")
        
        # Check for backend
        if [ -d "$app_dir/backend" ] && [ -f "$app_dir/backend/Dockerfile" ]; then
            add_matrix_item \
                "backend" \
                "app-specific" \
                "$app_name" \
                "./applications/$app_name/backend" \
                "$app_name-backend" \
                "./applications/$app_name/backend/Dockerfile"
        fi
        
        # Check for frontend
        if [ -d "$app_dir/frontend" ] && [ -f "$app_dir/frontend/Dockerfile" ]; then
            add_matrix_item \
                "frontend" \
                "app-specific" \
                "$app_name" \
                "./applications/$app_name/frontend" \
                "$app_name-frontend" \
                "./applications/$app_name/frontend/Dockerfile"
        fi
    done < <(find "$BASE_DIR/applications" -mindepth 1 -maxdepth 1 -type d | sort)
fi

# Build JSON output
MATRIX_JSON="{\"include\":["
FIRST=true
for item in "${MATRIX_ITEMS[@]}"; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        MATRIX_JSON="$MATRIX_JSON,"
    fi
    MATRIX_JSON="$MATRIX_JSON$item"
done
MATRIX_JSON="$MATRIX_JSON]}"

# Output based on format
case "$FORMAT" in
    matrix|json)
        echo "$MATRIX_JSON"
        ;;
    list)
        echo "$MATRIX_JSON" | jq -r '.include[].image_name'
        ;;
    *)
        echo "Error: Unknown format '$FORMAT'. Use: matrix, json, or list" >&2
        exit 1
        ;;
esac

