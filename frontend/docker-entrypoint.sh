#!/bin/sh
# Docker entrypoint script for frontend container
# Substitutes environment variables in nginx.conf template

set -e

# Default values if not set
export BACKEND_API_URL="${BACKEND_API_URL:-https://app.dev.example.com}"

# Escape special characters in BACKEND_API_URL for CSP
# Remove protocol and extract domain for CSP connect-src
CSP_BACKEND_URL=$(echo "$BACKEND_API_URL" | sed 's|^https\?://||' | sed 's|/.*$||')
if echo "$BACKEND_API_URL" | grep -q "^https"; then
    CSP_CONNECT_SRC="'self' https://${CSP_BACKEND_URL}"
else
    CSP_CONNECT_SRC="'self' http://${CSP_BACKEND_URL}"
fi

# Substitute environment variables in nginx.conf template
envsubst '${CSP_CONNECT_SRC}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Verify nginx config
nginx -t

# Switch to appuser and start nginx
# su-exec is a lightweight su replacement for containers
exec su-exec appuser nginx -g "daemon off;"

