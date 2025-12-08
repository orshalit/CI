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

# Ensure log directories and files are writable by appuser
# We're running as root here, so we can fix permissions
chown -R appuser:appuser /var/log/nginx /var/cache/nginx /var/run
chmod -R 755 /var/log/nginx /var/cache/nginx /var/run

# Create log files if they don't exist and ensure appuser can write to them
touch /var/log/nginx/access.log /var/log/nginx/error.log
chown appuser:appuser /var/log/nginx/access.log /var/log/nginx/error.log
chmod 644 /var/log/nginx/access.log /var/log/nginx/error.log

# Ensure PID file location is writable by appuser
# Remove any existing PID file that might be owned by root
rm -f /var/run/nginx.pid
# Create PID file with correct ownership
touch /var/run/nginx.pid
chown appuser:appuser /var/run/nginx.pid
chmod 644 /var/run/nginx.pid

# Verify nginx config
nginx -t

# Switch to appuser and start nginx
# su-exec is a lightweight su replacement for containers
exec su-exec appuser nginx -g "daemon off;"


