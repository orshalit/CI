#!/bin/bash
# Update Dhall imports to use the correct repository name from environment variable
# This makes imports dynamic instead of hardcoded
# Usage: DEVOPS_REPO_NAME=projectdevops ./scripts/update-dhall-repo-imports.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get repository name from environment variable or use default
DEVOPS_REPO_NAME="${DEVOPS_REPO_NAME:-projectdevops}"

echo "Updating Dhall imports to use repository: $DEVOPS_REPO_NAME"
echo ""

# Find all Dhall files with any orshalit/* imports (handles both DEVOPS and projectdevops)
FILES=$(grep -r "https://raw.githubusercontent.com/orshalit/" "$REPO_ROOT/dhall" --include="*.dhall" -l 2>/dev/null || true)

if [ -z "$FILES" ]; then
    echo "No Dhall files with remote imports found"
    exit 0
fi

# Update each file - replace any repository name with the correct one
UPDATED=0
for file in $FILES; do
    # Replace any orshalit/[repo]/ with orshalit/$DEVOPS_REPO_NAME/
    # This handles both DEVOPS and projectdevops (or any other name)
    if sed -i.bak "s|https://raw\.githubusercontent\.com/orshalit/[^/]*/|https://raw.githubusercontent.com/orshalit/$DEVOPS_REPO_NAME/|g" "$file"; then
        rm -f "${file}.bak"
        echo "✓ Updated: $file"
        UPDATED=$((UPDATED + 1))
    fi
done

echo ""
echo "Updated $UPDATED file(s) to use repository '$DEVOPS_REPO_NAME'"

