#!/bin/bash
# Initialize DynamoDB Local table for E2E tests
# This script creates the greetings table in DynamoDB Local with the same schema as production

set -e

DYNAMODB_ENDPOINT="${DYNAMODB_ENDPOINT_URL:-http://localhost:8000}"
TABLE_NAME="${DYNAMODB_TABLE_NAME:-dev-greetings}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "::notice::Initializing DynamoDB Local table: $TABLE_NAME"
echo "::notice::DynamoDB endpoint: $DYNAMODB_ENDPOINT"

# DynamoDB Local still expects signed requests; dummy credentials are fine.
# Also disable IMDS to avoid credential resolution timeouts in CI.
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export AWS_EC2_METADATA_DISABLED="${AWS_EC2_METADATA_DISABLED:-true}"

# Wait for DynamoDB Local to be ready
echo "Waiting for DynamoDB Local to be ready..."
max_attempts=30
attempt=0
while [ $attempt -lt $max_attempts ]; do
  # DynamoDB Local doesn't respond 200 OK to a plain GET / request.
  # We only need to know the TCP connection succeeds (curl exit 0 without -f).
  if curl -s --connect-timeout 1 --max-time 2 "$DYNAMODB_ENDPOINT" > /dev/null 2>&1; then
    echo "✓ DynamoDB Local is ready"
    break
  fi
  attempt=$((attempt + 1))
  echo "Attempt $attempt/$max_attempts: DynamoDB Local not ready yet, waiting..."
  sleep 2
done

if [ $attempt -eq $max_attempts ]; then
  echo "::error::DynamoDB Local failed to become ready after $max_attempts attempts"
  exit 1
fi

# Check if table already exists
if aws dynamodb describe-table \
  --table-name "$TABLE_NAME" \
  --endpoint-url "$DYNAMODB_ENDPOINT" \
  --region "$AWS_REGION" \
  > /dev/null 2>&1; then
  echo "::notice::Table $TABLE_NAME already exists, skipping creation"
  exit 0
fi

# Create the table with the same schema as defined in Terraform
echo "Creating table: $TABLE_NAME"
aws dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=created_at,AttributeType=S \
    AttributeName=user_name,AttributeType=S \
  --key-schema \
    AttributeName=id,KeyType=HASH \
    AttributeName=created_at,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes \
    'IndexName=user-name-index,KeySchema=[{AttributeName=user_name,KeyType=HASH}],Projection={ProjectionType=ALL}' \
  --endpoint-url "$DYNAMODB_ENDPOINT" \
  --region "$AWS_REGION" \
  > /dev/null

echo "Waiting for table to be active..."
aws dynamodb wait table-exists \
  --table-name "$TABLE_NAME" \
  --endpoint-url "$DYNAMODB_ENDPOINT" \
  --region "$AWS_REGION"

echo "::notice::✓ DynamoDB table '$TABLE_NAME' created successfully"
