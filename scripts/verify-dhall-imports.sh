#!/bin/bash
# Verify Dhall remote imports are accessible
# Usage: ./scripts/verify-dhall-imports.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Verifying Dhall remote imports..."
echo ""

# Find all DEVOPS imports
IMPORTS=$(grep -r "https://raw.githubusercontent.com/orshalit/DEVOPS/" "$REPO_ROOT/dhall" --include="*.dhall" -h || true)

if [ -z "$IMPORTS" ]; then
    echo "No DEVOPS imports found"
    exit 0
fi

# Extract unique URLs
UNIQUE_URLS=$(echo "$IMPORTS" | grep -o "https://raw.githubusercontent.com/orshalit/DEVOPS/[^ ]*" | sort -u)

FAILED=0
SUCCESS=0

for url in $UNIQUE_URLS; do
    echo -n "Checking: $url ... "
    
    # Try to fetch the file
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ OK"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "✗ FAILED (HTTP $HTTP_CODE)"
        FAILED=$((FAILED + 1))
        
        # Try to suggest fix
        if [ "$HTTP_CODE" = "404" ]; then
            echo "  → This commit may not exist on remote, or repository name is wrong"
            echo "  → Check if commit is pushed: cd ../DEVOPS && git log origin/main"
            echo "  → Check repository name: git remote get-url origin"
        fi
    fi
done

echo ""
echo "Results: $SUCCESS succeeded, $FAILED failed"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Troubleshooting:"
    echo "1. Verify commit exists: cd ../DEVOPS && git log --oneline -5"
    echo "2. Verify commit is pushed: cd ../DEVOPS && git log origin/main --oneline -5"
    echo "3. Check repository name matches GitHub: git remote get-url origin"
    echo "4. Update imports: ./scripts/update-dhall-imports.sh [commit-hash] --verify"
    exit 1
fi

echo "✓ All imports verified successfully"

