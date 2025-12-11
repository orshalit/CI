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

# Debug: Show environment variables
echo "::group::Debug: Environment variables"
echo "  DEVOPS_REPO_OWNER: '${DEVOPS_REPO_OWNER:-<not set>}'"
echo "  DEVOPS_REPO_NAME: '${DEVOPS_REPO_NAME:-<not set>}'"
if [ -n "${DEVOPS_REPO_OWNER:-}" ]; then
    echo "  DEVOPS_REPO_OWNER length: ${#DEVOPS_REPO_OWNER}"
fi
if [ -n "${DEVOPS_REPO_NAME:-}" ]; then
    echo "  DEVOPS_REPO_NAME length: ${#DEVOPS_REPO_NAME}"
fi
echo "::endgroup::"

# Debug: Test basic network connectivity
echo "::group::Debug: Network connectivity test"
if curl -s --max-time 5 https://raw.githubusercontent.com > /dev/null 2>&1; then
    echo "  ✓ GitHub raw.githubusercontent.com is reachable"
else
    echo "  ✗ GitHub raw.githubusercontent.com is NOT reachable"
    echo "  This may indicate a network connectivity issue"
fi
echo "::endgroup::"
echo ""

# Find all remote imports (not just DEVOPS - handles any remote)
IMPORTS=$(grep -r "https://raw.githubusercontent.com" "$REPO_ROOT/dhall" --include="*.dhall" -h 2>/dev/null || true)

if [ -z "$IMPORTS" ]; then
    echo "No remote imports found"
    exit 0
fi

# Extract unique URLs (handle both single-line and multi-line imports)
# Trim whitespace and newlines from URLs to prevent curl errors
# Use xargs to trim and handle newlines properly
UNIQUE_URLS=$(echo "$IMPORTS" | grep -oE "https://raw\.githubusercontent\.com/[^\"' \r\n]+" | xargs -n1 printf '%s\n' | sort -u)

if [ -z "$UNIQUE_URLS" ]; then
    echo "No valid import URLs found"
    exit 0
fi

# Debug: Show extracted URLs (one per line for clarity)
echo "::group::Debug: Extracted unique URLs"
echo "$UNIQUE_URLS" | while IFS= read -r url; do
    [ -n "$url" ] && echo "  URL: '$url' (length: ${#url})"
done
echo "::endgroup::"
echo ""

# Debug: Show found imports
echo "::group::Debug: Dhall files with remote imports"
FILES_WITH_IMPORTS=$(grep -r "https://raw.githubusercontent.com" "$REPO_ROOT/dhall" --include="*.dhall" -l 2>/dev/null || true)
if [ -n "$FILES_WITH_IMPORTS" ]; then
    while IFS= read -r file; do
        echo "  Found: $file"
        # Show the import line(s) from this file
        grep "https://raw.githubusercontent.com" "$file" | while IFS= read -r import_line; do
            echo "    $import_line"
        done
    done <<< "$FILES_WITH_IMPORTS"
else
    echo "  No files with remote imports found"
fi
echo "::endgroup::"
echo ""

# Function to check URL with retry logic
check_url() {
    local url="$1"
    local retry_count=0
    local http_code="000"
    local error_msg=""
    local curl_stderr=""
    local curl_stdout=""
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Debug: Show curl command being executed
        if [ "$retry_count" -eq 0 ]; then
            echo "::debug::Attempt $((retry_count + 1))/$MAX_RETRIES: Checking URL: $url" >&2
            echo "::debug::Curl command: curl -s -o /dev/null -w '%{http_code}' --max-time $TIMEOUT --retry 0 --fail-with-body '$url'" >&2
        else
            echo "::debug::Retry $((retry_count + 1))/$MAX_RETRIES after ${RETRY_DELAY}s delay" >&2
        fi
        
        # Try to fetch with timeout - capture both stdout and stderr separately
        curl_output=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time "$TIMEOUT" \
            --retry 0 \
            --fail-with-body \
            "$url" 2>&1) || curl_exit_code=$?
        
        # Extract HTTP code (should be last line)
        http_code=$(echo "$curl_output" | tail -1 | grep -oE '^[0-9]{3}$' || echo "000")
        curl_stderr=$(echo "$curl_output" | grep -vE '^[0-9]{3}$' || echo "")
        
        # Debug: Show what curl returned
        echo "::debug::Curl exit code: ${curl_exit_code:-0}" >&2
        echo "::debug::Curl stdout (HTTP code): '$http_code'" >&2
        if [ -n "$curl_stderr" ]; then
            echo "::debug::Curl stderr: $curl_stderr" >&2
        fi
        echo "::debug::Full curl output: $curl_output" >&2
        
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
            # Network error or timeout - extract more details
            if [ -n "$curl_stderr" ]; then
                if echo "$curl_stderr" | grep -qi "timeout\|timed out"; then
                    error_msg="Network timeout (exceeded ${TIMEOUT}s)"
                elif echo "$curl_stderr" | grep -qi "resolve\|DNS"; then
                    error_msg="DNS resolution failed"
                elif echo "$curl_stderr" | grep -qi "connect\|connection"; then
                    error_msg="Connection failed"
                elif echo "$curl_stderr" | grep -qi "SSL\|TLS\|certificate"; then
                    error_msg="SSL/TLS error"
                else
                    error_msg="Network error: $curl_stderr"
                fi
            else
                error_msg="Network error/timeout (HTTP 000)"
            fi
            
            echo "::debug::Network error details: $error_msg" >&2
            
            if [ $retry_count -lt $((MAX_RETRIES - 1)) ]; then
                echo "::debug::Will retry after ${RETRY_DELAY}s delay" >&2
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
    
    # Get dynamic values from environment
    local expected_owner="${DEVOPS_REPO_OWNER:-orshalit}"
    local expected_repo="${DEVOPS_REPO_NAME:-projectdevops}"
    
    # Extract repository and commit from URL
    # URL format: https://raw.githubusercontent.com/owner/repo/ref/path/to/file.dhall
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
            
            # Check if it's a DEVOPS import (matches expected owner)
            if [ "$owner" = "$expected_owner" ]; then
                echo "  1. Verify commit exists: git log --oneline -5 (in $owner/$repo repo)"
                echo "  2. Verify commit is pushed: git log origin/main --oneline -5"
                echo "  3. Check repository name matches GitHub (expected: $expected_repo, found: $repo)"
                if [ "$repo" != "$expected_repo" ]; then
                    echo "     → Repository mismatch! Update: DEVOPS_REPO_NAME=$expected_repo ./scripts/update-dhall-repo-imports.sh"
                fi
                echo "  4. Update repository: DEVOPS_REPO_NAME=$expected_repo DEVOPS_REPO_OWNER=$expected_owner ./scripts/update-dhall-repo-imports.sh"
                echo "  5. Update imports: ./scripts/update-dhall-imports.sh [commit-hash] --verify"
            else
                echo "  1. Verify commit/branch exists on remote"
                echo "  2. Check repository name is correct (expected: $expected_owner/$expected_repo)"
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

# Process URLs line by line to handle any remaining whitespace issues
echo "$UNIQUE_URLS" | while IFS= read -r url || [ -n "$url" ]; do
    # Trim any remaining whitespace/newlines
    url=$(echo "$url" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Skip empty URLs
    [ -z "$url" ] && continue
    
    echo -n "Checking: $url ... "
    
    # Debug: Show URL before processing (with hexdump to detect hidden chars)
    echo "::debug::Processing URL: '$url' (length: ${#url})" >&2
    echo "::debug::URL hexdump (first 100 chars): $(echo -n "$url" | head -c 100 | xxd -p 2>/dev/null || echo 'xxd not available')" >&2
    # Check for newlines/carriage returns
    if echo "$url" | grep -q $'\r'; then
        echo "::warning::URL contains carriage return (\\r)" >&2
    fi
    if echo "$url" | grep -q $'\n'; then
        echo "::warning::URL contains newline (\\n)" >&2
    fi
    
    # Debug: Parse URL components
    if [[ "$url" =~ https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+) ]]; then
        url_owner="${BASH_REMATCH[1]}"
        url_repo="${BASH_REMATCH[2]}"
        url_ref="${BASH_REMATCH[3]}"
        url_path="${BASH_REMATCH[4]}"
        echo "::debug::URL components - Owner: $url_owner, Repo: $url_repo, Ref: $url_ref, Path: $url_path" >&2
        
        # Check if repository name matches expected
        if [ -n "${DEVOPS_REPO_OWNER:-}" ] && [ -n "${DEVOPS_REPO_NAME:-}" ]; then
            if [ "$url_owner" = "$DEVOPS_REPO_OWNER" ] && [ "$url_repo" != "$DEVOPS_REPO_NAME" ]; then
                echo "::warning::Repository name mismatch! Expected: $DEVOPS_REPO_OWNER/$DEVOPS_REPO_NAME, Found: $url_owner/$url_repo" >&2
            fi
        fi
    fi
    
    # Check URL with retry logic
    if check_url "$url"; then
        echo "✓ OK"
        SUCCESS=$((SUCCESS + 1))
    else
        # Get error message (check_url outputs error to stdout when it fails)
        HTTP_CODE="000"
        ERROR_MSG="Network error/timeout"
        
        # Try to get HTTP code from check_url output
        CHECK_RESULT=$(check_url "$url" 2>&1 || true)
        if echo "$CHECK_RESULT" | grep -qE "^[0-9]{3}$"; then
            HTTP_CODE="$CHECK_RESULT"
            if [ "$HTTP_CODE" = "404" ]; then
                ERROR_MSG="Not found (404)"
            elif [ "$HTTP_CODE" = "403" ]; then
                ERROR_MSG="Forbidden (403)"
            elif [ "$HTTP_CODE" = "429" ]; then
                ERROR_MSG="Rate limited (429)"
            else
                ERROR_MSG="HTTP $HTTP_CODE"
            fi
        else
            ERROR_MSG="$CHECK_RESULT"
        fi
        
        echo "✗ FAILED"
        echo "  Error: $ERROR_MSG"
        FAILED=$((FAILED + 1))
        FAILED_URLS+=("$url|$HTTP_CODE")
        
        # Suggest fixes
        suggest_fix "$url" "$HTTP_CODE"
        echo ""
    fi
done <<< "$UNIQUE_URLS"

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
    echo "4. Check repository names match GitHub (expected: ${DEVOPS_REPO_OWNER:-orshalit}/${DEVOPS_REPO_NAME:-projectdevops})"
    echo "5. Update repository: DEVOPS_REPO_NAME=${DEVOPS_REPO_NAME:-projectdevops} DEVOPS_REPO_OWNER=${DEVOPS_REPO_OWNER:-orshalit} ./scripts/update-dhall-repo-imports.sh"
    exit 1
fi

echo "✓ All imports verified successfully"
