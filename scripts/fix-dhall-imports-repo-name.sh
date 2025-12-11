#!/bin/bash
# Fix repository name in Dhall imports if it doesn't match GitHub
# Usage: ./scripts/fix-dhall-imports-repo-name.sh [correct-repo-name]
#   If repo-name not provided, tries to detect from DEVOPS remote

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get repository name from argument or DEVOPS remote
if [ $# -eq 1 ]; then
    REPO_NAME="$1"
else
    # Get DEVOPS repo path
    DEVOPS_DIR="${REPO_ROOT%/CI}/DEVOPS"
    if [ ! -d "$DEVOPS_DIR" ]; then
        echo "Error: DEVOPS directory not found at $DEVOPS_DIR" >&2
        echo "Usage: $0 [repo-name]" >&2
        exit 1
    fi
    
    # Extract repo name from remote URL (supports any owner)
    REMOTE_URL=$(cd "$DEVOPS_DIR" && git remote get-url origin)
    if [[ "$REMOTE_URL" =~ git@github.com:([^/]+)/(.+)\.git ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
    elif [[ "$REMOTE_URL" =~ https://github.com/([^/]+)/(.+)\.git ]]; then
        REPO_OWNER="${BASH_REMATCH[1]}"
        REPO_NAME="${BASH_REMATCH[2]}"
    else
        echo "Error: Could not parse repository name from: $REMOTE_URL" >&2
        exit 1
    fi
fi

echo "Updating Dhall imports to use repository: $REPO_NAME"
echo ""

# Get owner from environment or detect from remote
DEVOPS_REPO_OWNER="${DEVOPS_REPO_OWNER:-orshalit}"

# Find all Dhall files with DEVOPS repository imports (any repo name)
FILES=$(grep -r "https://raw.githubusercontent.com/$DEVOPS_REPO_OWNER/" "$REPO_ROOT/dhall" --include="*.dhall" -l 2>/dev/null || true)

if [ -z "$FILES" ]; then
    echo "No Dhall files with $DEVOPS_REPO_OWNER/* imports found"
    exit 0
fi

# Update each file
UPDATED=0
for file in $FILES; do
    # Replace any repo name with the correct one (keeps owner)
    if sed -i.bak "s|https://raw\.githubusercontent\.com/$DEVOPS_REPO_OWNER/[^/]*/|https://raw.githubusercontent.com/$DEVOPS_REPO_OWNER/$REPO_NAME/|g" "$file"; then
        rm -f "${file}.bak"
        echo "✓ Updated: $file"
        UPDATED=$((UPDATED + 1))
    fi
done

echo ""
echo "Updated $UPDATED file(s) to use repository '$REPO_NAME'"
echo ""
echo "Next steps:"
echo "1. Verify imports work: ./scripts/verify-dhall-imports.sh"
echo "2. Review changes: git diff"
echo "3. Commit if satisfied: git add -A && git commit -m 'fix: Update DEVOPS repo name to $REPO_NAME'"

