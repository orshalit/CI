#!/bin/bash
# Update Dhall remote imports to use a specific DEVOPS commit hash
# Usage: ./scripts/update-dhall-imports.sh [commit-hash] [--verify]
#   If commit-hash is not provided, uses DEVOPS HEAD
#   --verify: Verify commit exists on remote before updating

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERIFY=false
COMMIT_HASH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify)
            VERIFY=true
            shift
            ;;
        *)
            if [ -z "$COMMIT_HASH" ]; then
                COMMIT_HASH="$1"
            else
                echo "Error: Unknown argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Get commit hash from argument or DEVOPS HEAD
if [ -z "$COMMIT_HASH" ]; then
    # Get DEVOPS repo path (assumes DEVOPS is sibling to CI)
    DEVOPS_DIR="${REPO_ROOT%/CI}/DEVOPS"
    if [ ! -d "$DEVOPS_DIR" ]; then
        echo "Error: DEVOPS directory not found at $DEVOPS_DIR" >&2
        echo "Usage: $0 [commit-hash] [--verify]" >&2
        exit 1
    fi
    COMMIT_HASH=$(cd "$DEVOPS_DIR" && git rev-parse HEAD)
    echo "Using DEVOPS HEAD: $COMMIT_HASH"
fi

# Verify commit exists on remote if requested
if [ "$VERIFY" = true ]; then
    echo "Verifying commit exists on remote..."
    DEVOPS_DIR="${REPO_ROOT%/CI}/DEVOPS"
    if [ ! -d "$DEVOPS_DIR" ]; then
        echo "Warning: Cannot verify - DEVOPS directory not found" >&2
    else
        # Get remote URL and convert to HTTPS format
        REMOTE_URL=$(cd "$DEVOPS_DIR" && git remote get-url origin)
        # Convert git@github.com:user/repo.git to https://github.com/user/repo
        if [[ "$REMOTE_URL" =~ git@github.com:(.+)\.git ]]; then
            REPO_PATH="${BASH_REMATCH[1]}"
            GITHUB_REPO="https://github.com/$REPO_PATH"
        elif [[ "$REMOTE_URL" =~ https://github.com/(.+)\.git ]]; then
            REPO_PATH="${BASH_REMATCH[1]}"
            GITHUB_REPO="https://github.com/$REPO_PATH"
        else
            echo "Warning: Could not parse remote URL: $REMOTE_URL" >&2
            GITHUB_REPO=""
        fi
        
        if [ -n "$GITHUB_REPO" ]; then
            # Check if commit exists on remote
            if ! (cd "$DEVOPS_DIR" && git fetch origin --quiet 2>/dev/null && git cat-file -e "$COMMIT_HASH" 2>/dev/null); then
                echo "Error: Commit $COMMIT_HASH not found locally in DEVOPS" >&2
                exit 1
            fi
            
            # Try to verify file exists at that commit
            TEST_URL="https://raw.githubusercontent.com/$REPO_PATH/$COMMIT_HASH/config/types/Service.dhall"
            if ! curl -sf --head "$TEST_URL" > /dev/null 2>&1; then
                echo "Warning: Cannot verify file exists at: $TEST_URL" >&2
                echo "  This might be normal if the commit isn't pushed yet" >&2
                echo "  Continuing anyway..." >&2
            else
                echo "✓ Verified: File exists at commit $COMMIT_HASH"
            fi
        fi
    fi
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
FAILED=0
for file in $FILES; do
    # Use sed to replace any DEVOPS commit hash or branch with the new commit hash
    # Pattern: .../DEVOPS/[hash-or-branch]/... -> .../DEVOPS/[new-hash]/...
    if sed -i.bak "s|https://raw.githubusercontent.com/orshalit/DEVOPS/[^/]*/|https://raw.githubusercontent.com/orshalit/DEVOPS/$COMMIT_HASH/|g" "$file"; then
        rm -f "${file}.bak"
        echo "✓ Updated: $file"
        UPDATED=$((UPDATED + 1))
    else
        echo "✗ Failed: $file" >&2
        FAILED=$((FAILED + 1))
    fi
done

echo ""
if [ $FAILED -gt 0 ]; then
    echo "Warning: $FAILED file(s) failed to update" >&2
fi
echo "Updated $UPDATED file(s) to use commit $COMMIT_HASH"
echo ""

# Validate Dhall syntax after update
echo "Validating Dhall syntax..."
if command -v dhall > /dev/null 2>&1; then
    VALIDATION_FAILED=0
    for file in $FILES; do
        if ! dhall type --file "$file" > /dev/null 2>&1; then
            echo "✗ Validation failed: $file" >&2
            VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
        fi
    done
    
    if [ $VALIDATION_FAILED -eq 0 ]; then
        echo "✓ All files validated successfully"
    else
        echo "✗ $VALIDATION_FAILED file(s) failed validation" >&2
        echo "  Run 'dhall type --file <file>' to see errors" >&2
    fi
else
    echo "Warning: 'dhall' command not found - skipping validation" >&2
fi

echo ""
echo "Next steps:"
echo "1. Review the changes: git diff"
echo "2. Test Dhall type-checking: dhall type --file dhall/services.dhall"
echo "3. Commit if satisfied: git add -A && git commit -m 'chore: Update DEVOPS import to $COMMIT_HASH'"
