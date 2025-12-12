#!/bin/bash
# Retrieve backend API key from AWS Secrets Manager
#
# This script retrieves the backend API key from AWS Secrets Manager
# using the same discovery pattern as the backend application.
#
# Usage:
#   ./scripts/get-api-key.sh <environment> [application]
#
# Example:
#   ./scripts/get-api-key.sh dev test-app
#
# Output:
#   Prints the API key value to stdout (or empty string if not found)
#   Exit code: 0 if successful, 1 if error

set -euo pipefail

ENVIRONMENT="${1:-dev}"
APPLICATION="${2:-test-app}"
AWS_REGION="${AWS_REGION:-us-east-1}"

SECRET_IDENTIFIER="backend-api-key"
SSM_PARAMETER_PATH="/${ENVIRONMENT}/${APPLICATION}/secrets/${SECRET_IDENTIFIER}/secret_name"

echo "::notice::Retrieving API key for ${ENVIRONMENT}/${APPLICATION}..." >&2

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "::error::AWS CLI is not installed or not in PATH" >&2
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "::error::jq is not installed or not in PATH" >&2
    exit 1
fi

# Step 1: Get secret name from SSM Parameter Store
SECRET_NAME=""
if aws ssm get-parameter \
    --name "$SSM_PARAMETER_PATH" \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null | grep -q .; then
    
    SECRET_NAME=$(aws ssm get-parameter \
        --name "$SSM_PARAMETER_PATH" \
        --region "$AWS_REGION" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "")
fi

if [ -z "$SECRET_NAME" ]; then
    echo "::warning::Secret name not found in SSM Parameter Store at $SSM_PARAMETER_PATH" >&2
    echo "::warning::Trying direct secret name: ${ENVIRONMENT}/${APPLICATION}/${SECRET_IDENTIFIER}" >&2
    SECRET_NAME="${ENVIRONMENT}/${APPLICATION}/${SECRET_IDENTIFIER}"
fi

# Step 2: Retrieve secret value from Secrets Manager
API_KEY=""
if aws secretsmanager get-secret-value \
    --secret-id "$SECRET_NAME" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text 2>/dev/null | grep -q .; then
    
    API_KEY=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo "")
fi

if [ -z "$API_KEY" ]; then
    echo "::error::Failed to retrieve API key from Secrets Manager" >&2
    echo "::error::Secret name: $SECRET_NAME" >&2
    echo "::error::Please ensure:" >&2
    echo "::error::  1. Secret exists in AWS Secrets Manager" >&2
    echo "::error::  2. Secret has a value set (use generate-secrets.sh)" >&2
    echo "::error::  3. AWS credentials have permission to read the secret" >&2
    exit 1
fi

# Output the API key (to stdout, errors go to stderr)
echo "$API_KEY"
