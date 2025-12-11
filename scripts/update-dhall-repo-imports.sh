#!/bin/bash
# Update Dhall imports to use the correct repository name from environment variable
# This makes imports dynamic instead of hardcoded
# Usage: DEVOPS_REPO_NAME=projectdevops ./scripts/update-dhall-repo-imports.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get repository name and owner from environment variables or use defaults
DEVOPS_REPO_NAME="${DEVOPS_REPO_NAME:-projectdevops}"
DEVOPS_REPO_OWNER="${DEVOPS_REPO_OWNER:-orshalit}"

echo "Updating Dhall imports to use repository: $DEVOPS_REPO_OWNER/$DEVOPS_REPO_NAME"
echo ""

# Find all Dhall files with any GitHub raw imports (handles any owner/repo combination)
FILES=$(grep -r "https://raw.githubusercontent.com/" "$REPO_ROOT/dhall" --include="*.dhall" -l 2>/dev/null || true)

if [ -z "$FILES" ]; then
    echo "No Dhall files with remote imports found"
    exit 0
fi

# Update each file - replace any owner/repo combination with the correct one
UPDATED=0
for file in $FILES; do
    # Replace any https://raw.githubusercontent.com/[owner]/[repo]/ with correct owner/repo
    # This handles any owner/repo combination dynamically
    if sed -i.bak "s|https://raw\.githubusercontent\.com/[^/]*/[^/]*/|https://raw.githubusercontent.com/$DEVOPS_REPO_OWNER/$DEVOPS_REPO_NAME/|g" "$file"; then
        rm -f "${file}.bak"
        echo "✓ Updated: $file"
        UPDATED=$((UPDATED + 1))
    fi
done

echo ""
echo "Updated $UPDATED file(s) to use repository '$DEVOPS_REPO_OWNER/$DEVOPS_REPO_NAME'"

