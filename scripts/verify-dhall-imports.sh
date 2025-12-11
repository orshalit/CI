#!/bin/bash
# Verify Dhall remote imports are accessible
# Handles all edge cases: network failures, rate limits, repo name mismatches, etc.
# Usage: ./scripts/verify-dhall-imports.sh [--retry N] [--timeout SECONDS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
MAX_RETRIES=3
TIMEOUT=10
RETRY_DELAY=2

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --retry)
            MAX_RETRIES="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

echo "Verifying Dhall remote imports..."
echo "  Max retries: $MAX_RETRIES"
echo "  Timeout: ${TIMEOUT}s"
echo ""

# Find all remote imports (not just DEVOPS - handles any remote)
IMPORTS=$(grep -r "https://raw.githubusercontent.com" "$REPO_ROOT/dhall" --include="*.dhall" -h 2>/dev/null || true)

if [ -z "$IMPORTS" ]; then
    echo "No remote imports found"
    exit 0
fi

# Extract unique URLs (handle both single-line and multi-line imports)
UNIQUE_URLS=$(echo "$IMPORTS" | grep -oE "https://raw\.githubusercontent\.com/[^\"' ]+" | sort -u)

if [ -z "$UNIQUE_URLS" ]; then
    echo "No valid import URLs found"
    exit 0
fi

# Function to check URL with retry logic
check_url() {
    local url="$1"
    local retry_count=0
    local http_code="000"
    local error_msg=""
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Try to fetch with timeout
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time "$TIMEOUT" \
            --retry 0 \
            --fail-with-body \
            "$url" 2>&1 | tail -1 || echo "000")
        
        # Check if we got a valid HTTP code
        if [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
            if [ "$http_code" = "200" ]; then
                return 0  # Success
            elif [ "$http_code" = "404" ]; then
                error_msg="Not found (404)"
                break  # Don't retry 404s
            elif [ "$http_code" = "403" ]; then
                error_msg="Forbidden (403) - Repository may be private"
                break  # Don't retry 403s
            elif [ "$http_code" = "429" ]; then
                error_msg="Rate limited (429)"
                if [ $retry_count -lt $((MAX_RETRIES - 1)) ]; then
                    sleep $RETRY_DELAY
                    retry_count=$((retry_count + 1))
                    continue
                fi
                break
            else
                error_msg="HTTP $http_code"
                if [ $retry_count -lt $((MAX_RETRIES - 1)) ]; then
                    sleep $RETRY_DELAY
                    retry_count=$((retry_count + 1))
                    continue
                fi
                break
            fi
        else
            # Network error or timeout
            error_msg="Network error/timeout"
            if [ $retry_count -lt $((MAX_RETRIES - 1)) ]; then
                sleep $RETRY_DELAY
                retry_count=$((retry_count + 1))
                continue
            fi
            break
        fi
    done
    
    echo "$error_msg"
    return 1
}

# Function to suggest fixes for common issues
suggest_fix() {
    local url="$1"
    local http_code="$2"
    
    # Extract repository and commit from URL
    if [[ "$url" =~ https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+) ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        local ref="${BASH_REMATCH[3]}"
        local path="${BASH_REMATCH[4]}"
        
        echo "  → Repository: $owner/$repo"
        echo "  → Reference: $ref"
        echo "  → Path: $path"
        
        if [ "$http_code" = "404" ]; then
            echo ""
            echo "  Possible fixes:"
            
            # Check if it's a DEVOPS import
            if [[ "$repo" =~ ^(DEVOPS|projectdevops)$ ]]; then
                echo "  1. Verify commit exists: git log --oneline -5 (in DEVOPS repo)"
                echo "  2. Verify commit is pushed: git log origin/main --oneline -5"
                echo "  3. Check repository name matches GitHub"
                echo "  4. Try alternative repo name:"
                if [ "$repo" = "DEVOPS" ]; then
                    echo "     → Try: projectdevops"
                else
                    echo "     → Try: DEVOPS"
                fi
                echo "  5. Update imports: ./scripts/update-dhall-imports.sh [commit-hash] --verify"
            else
                echo "  1. Verify commit/branch exists on remote"
                echo "  2. Check repository name is correct"
                echo "  3. Verify file path is correct"
            fi
        elif [ "$http_code" = "403" ]; then
            echo ""
            echo "  Possible fixes:"
            echo "  1. Repository may be private - check access permissions"
            echo "  2. Use GitHub token for authentication (if needed)"
        elif [ "$http_code" = "429" ]; then
            echo ""
            echo "  Possible fixes:"
            echo "  1. Wait a few minutes and retry"
            echo "  2. Check GitHub API rate limit status"
        fi
    fi
}

FAILED=0
SUCCESS=0
FAILED_URLS=()

echo "Found $(echo "$UNIQUE_URLS" | wc -l) unique import URL(s)"
echo ""

for url in $UNIQUE_URLS; do
    echo -n "Checking: $url ... "
    
    # Check URL with retry logic
    if check_url "$url"; then
        echo "✓ OK"
        SUCCESS=$((SUCCESS + 1))
    else
        ERROR=$(check_url "$url" 2>&1 || true)
        HTTP_CODE=$(echo "$ERROR" | grep -oE "[0-9]{3}" | head -1 || echo "000")
        echo "✗ FAILED"
        echo "  Error: $ERROR"
        FAILED=$((FAILED + 1))
        FAILED_URLS+=("$url|$HTTP_CODE")
        
        # Suggest fixes
        suggest_fix "$url" "$HTTP_CODE"
        echo ""
    fi
done

echo ""
echo "Results: $SUCCESS succeeded, $FAILED failed"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Failed imports:"
    for failed_item in "${FAILED_URLS[@]}"; do
        url="${failed_item%%|*}"
        code="${failed_item##*|}"
        echo "  ✗ $url (HTTP $code)"
    done
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Run: ./scripts/verify-dhall-imports.sh --retry 5 --timeout 15"
    echo "2. Check network connectivity"
    echo "3. Verify commits exist on remote repositories"
    echo "4. Check repository names match GitHub"
    echo "5. For DEVOPS imports: ./scripts/fix-dhall-imports-repo-name.sh"
    exit 1
fi

echo "✓ All imports verified successfully"
