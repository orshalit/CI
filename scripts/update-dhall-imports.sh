#!/bin/bash
# Update Dhall remote imports to use a specific DEVOPS commit hash
# Usage: ./scripts/update-dhall-imports.sh [commit-hash]
#   If commit-hash is not provided, uses DEVOPS HEAD

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get commit hash from argument or DEVOPS HEAD
if [ $# -eq 1 ]; then
    COMMIT_HASH="$1"
else
    # Get DEVOPS repo path (assumes DEVOPS is sibling to CI)
    DEVOPS_DIR="${REPO_ROOT%/CI}/DEVOPS"
    if [ ! -d "$DEVOPS_DIR" ]; then
        echo "Error: DEVOPS directory not found at $DEVOPS_DIR" >&2
        echo "Usage: $0 [commit-hash]" >&2
        exit 1
    fi
    COMMIT_HASH=$(cd "$DEVOPS_DIR" && git rev-parse HEAD)
fi

echo "Updating Dhall imports to use DEVOPS commit: $COMMIT_HASH"

# Find all Dhall files with DEVOPS imports
FILES=$(grep -r "https://raw.githubusercontent.com/orshalit/DEVOPS/" "$REPO_ROOT/dhall" --include="*.dhall" -l || true)

if [ -z "$FILES" ]; then
    echo "No Dhall files with DEVOPS imports found"
    exit 0
fi

# Update each file
UPDATED=0
for file in $FILES; do
    # Use sed to replace any DEVOPS commit hash or branch with the new commit hash
    # Pattern: .../DEVOPS/[hash-or-branch]/... -> .../DEVOPS/[new-hash]/...
    if sed -i.bak "s|https://raw.githubusercontent.com/orshalit/DEVOPS/[^/]*/|https://raw.githubusercontent.com/orshalit/DEVOPS/$COMMIT_HASH/|g" "$file"; then
        rm -f "${file}.bak"
        echo "✓ Updated: $file"
        UPDATED=$((UPDATED + 1))
    fi
done

echo ""
echo "Updated $UPDATED file(s) to use commit $COMMIT_HASH"
echo ""
echo "Next steps:"
echo "1. Review the changes: git diff"
echo "2. Test Dhall type-checking: dhall type --file dhall/services.dhall"
echo "3. Commit if satisfied: git add -A && git commit -m 'chore: Update DEVOPS import to $COMMIT_HASH'"

