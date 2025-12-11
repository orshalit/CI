#!/bin/bash
# Comprehensive State Validation and Auto-Import Script
# This script validates that all resources in config exist in state,
# and auto-imports any missing resources from AWS.

set -euo pipefail

PLAN_DIR="${1:-}"
ENVIRONMENT="${2:-}"
MODULE_PATH="${3:-}"

if [ -z "$PLAN_DIR" ] || [ -z "$ENVIRONMENT" ] || [ -z "$MODULE_PATH" ]; then
  echo "Usage: $0 <plan_dir> <environment> <module_path>"
  exit 1
fi

# Only run for ECS Fargate module
if [ "$MODULE_PATH" != "04-ecs-fargate" ]; then
  echo "::notice::State validation only runs for 04-ecs-fargate module"
  exit 0
fi

echo "::notice::🔍 Starting comprehensive state validation..."

# Initialize Terraform
terraform -chdir="$PLAN_DIR" init -no-color >/dev/null 2>&1 || true

# Build var files for commands
VAR_FILES=""
if [ -f "$PLAN_DIR/terraform.tfvars" ]; then
  VAR_FILES="terraform.tfvars"
fi
# Check for JSON format (new design)
if [ -f "$PLAN_DIR/services.generated.json" ]; then
  if [ -n "$VAR_FILES" ]; then
    VAR_FILES="$VAR_FILES services.generated.json"
  else
    VAR_FILES="services.generated.json"
  fi
fi

TF_ARGS=""
if [ -n "$VAR_FILES" ]; then
  for var_file in $VAR_FILES; do
    if [ -f "$PLAN_DIR/$var_file" ]; then
      TF_ARGS="$TF_ARGS -var-file=$var_file"
    fi
  done
fi

# Check if state exists
if ! terraform -chdir="$PLAN_DIR" state list -no-color >/dev/null 2>&1; then
  echo "::notice::No Terraform state found - skipping validation (fresh deployment)"
  exit 0
fi

# Get namespace ID for Service Discovery
NAMESPACE_ID=$(terraform -chdir="$PLAN_DIR" state show 'module.ecs_fargate.aws_service_discovery_private_dns_namespace.this' 2>/dev/null | \
  grep -E '^\s+id\s+=' | awk '{print $3}' | tr -d '"' || echo "")

IMPORTED_COUNT=0
MISSING_COUNT=0
ERRORS=0

# Validate Service Discovery Services
if [ -n "$NAMESPACE_ID" ] && [ -f "$PLAN_DIR/services.generated.json" ]; then
  echo "::notice::Validating Service Discovery services..."
  
  # Get expected service keys from JSON
  EXPECTED_KEYS=$(jq -r '.services | keys[]' "$PLAN_DIR/services.generated.json" 2>/dev/null || echo "")
  
  if [ -n "$EXPECTED_KEYS" ]; then
    # Get services in state
    STATE_SERVICES=$(terraform -chdir="$PLAN_DIR" state list 2>/dev/null | \
      grep 'module.ecs_fargate.aws_service_discovery_service.services\["' | \
      sed 's/.*\["\(.*\)"\]/\1/' || echo "")
    
    # Get services in AWS
    AWS_SERVICES=$(aws servicediscovery list-services \
      --filters Name=NAMESPACE_ID,Values="$NAMESPACE_ID" \
      --query 'Services[*].[Name,Id]' \
      --output text 2>/dev/null || echo "")
    
    # Check each expected service
    for tf_key in $EXPECTED_KEYS; do
      EXPECTED_NAME=$(echo "$tf_key" | sed 's/.*::\(.*\)/\1/' | tr '[:upper:]' '[:lower:]')
      
      # Check if exists in AWS
      AWS_SERVICE=$(echo "$AWS_SERVICES" | grep -E "^${EXPECTED_NAME}\t" || echo "")
      AWS_ID=""
      if [ -n "$AWS_SERVICE" ]; then
        AWS_ID=$(echo "$AWS_SERVICE" | awk '{print $2}')
      fi
      
      # Check if in state
      if echo "$STATE_SERVICES" | grep -q "^$tf_key$"; then
        # Service is in state - check if it matches AWS
        STATE_ID=$(terraform -chdir="$PLAN_DIR" state show "module.ecs_fargate.aws_service_discovery_service.services[\"$tf_key\"]" 2>/dev/null | \
          grep -E '^\s+id\s+=' | awk '{print $3}' | tr -d '"' || echo "")
        
        if [ -n "$AWS_ID" ] && [ -n "$STATE_ID" ] && [ "$AWS_ID" != "$STATE_ID" ]; then
          # State has different ID than AWS - this indicates a replacement scenario
          # The service in AWS is the "new" one that Terraform wants to create
          # We should update state to point to the existing AWS service to avoid replacement
          echo "::warning::⚠ Service Discovery '$tf_key' state mismatch detected"
          echo "::warning::   State ID: $STATE_ID"
          echo "::warning::   AWS ID: $AWS_ID"
          echo "::warning::   Updating state to match AWS (preventing unnecessary replacement)..."
          
          # Remove old state entry and import the correct one
          if terraform -chdir="$PLAN_DIR" state rm "module.ecs_fargate.aws_service_discovery_service.services[\"$tf_key\"]" 2>&1 && \
             terraform -chdir="$PLAN_DIR" import $TF_ARGS \
               "module.ecs_fargate.aws_service_discovery_service.services[\"$tf_key\"]" \
               "$AWS_ID" 2>&1; then
            echo "::notice::✓ Successfully updated state for '$tf_key' (ID: $AWS_ID)"
            IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
            # Force refresh on this specific resource to sync configuration attributes
            echo "::notice::Refreshing '$tf_key' to sync configuration attributes..."
            terraform -chdir="$PLAN_DIR" apply -refresh-only -target="module.ecs_fargate.aws_service_discovery_service.services[\"$tf_key\"]" -auto-approve $TF_ARGS >/dev/null 2>&1 || true
          else
            echo "::error::❌ Failed to update state for '$tf_key'"
            ERRORS=$((ERRORS + 1))
          fi
        elif [ -n "$AWS_ID" ] && [ "$AWS_ID" = "$STATE_ID" ]; then
          # Service is in state and ID matches - but we still need to refresh to sync config attributes
          # This ensures health_check_custom_config {} is properly synced from AWS
          echo "::notice::✓ Service Discovery '$tf_key' is in state and matches AWS (ID: $AWS_ID)"
          echo "::notice::Refreshing '$tf_key' to sync configuration attributes..."
          terraform -chdir="$PLAN_DIR" apply -refresh-only -target="module.ecs_fargate.aws_service_discovery_service.services[\"$tf_key\"]" -auto-approve $TF_ARGS >/dev/null 2>&1 || true
        else
          echo "::notice::✓ Service Discovery '$tf_key' is in state"
        fi
        continue
      fi
      
      # Service not in state
      if [ -z "$AWS_SERVICE" ]; then
        echo "::notice::ℹ Service Discovery '$tf_key' not in AWS (will be created)"
        continue
      fi
      
      # Service exists in AWS but not in state - import it
      echo "::warning::⚠ Service Discovery '$tf_key' exists in AWS but not in state - importing..."
      
      if terraform -chdir="$PLAN_DIR" import $TF_ARGS \
        "module.ecs_fargate.aws_service_discovery_service.services[\"$tf_key\"]" \
        "$AWS_ID" 2>&1; then
        echo "::notice::✓ Successfully imported '$tf_key'"
        IMPORTED_COUNT=$((IMPORTED_COUNT + 1))
        # Force refresh on this specific resource to sync configuration attributes
        echo "::notice::Refreshing '$tf_key' to sync configuration attributes..."
        terraform -chdir="$PLAN_DIR" apply -refresh-only -target="module.ecs_fargate.aws_service_discovery_service.services[\"$tf_key\"]" -auto-approve $TF_ARGS >/dev/null 2>&1 || true
      else
        echo "::error::❌ Failed to import '$tf_key'"
        MISSING_COUNT=$((MISSING_COUNT + 1))
        ERRORS=$((ERRORS + 1))
      fi
    done
    
    # Final refresh of all Service Discovery services to ensure all configuration attributes are synced
    # This is critical for health_check_custom_config {} which might not be properly synced after import
    if [ -n "$EXPECTED_KEYS" ]; then
      echo "::notice::Performing final refresh of all Service Discovery services..."
      REFRESH_OUTPUT=$(terraform -chdir="$PLAN_DIR" apply -refresh-only -auto-approve $TF_ARGS 2>&1 || echo "")
      if echo "$REFRESH_OUTPUT" | grep -q "No changes"; then
        echo "::notice::✓ All Service Discovery services are in sync with AWS"
      else
        echo "::notice::✓ Final refresh completed - configuration attributes synced"
        # Show what was updated
        if echo "$REFRESH_OUTPUT" | grep -q "updated in-place"; then
          echo "::notice::Resources updated in state:"
          echo "$REFRESH_OUTPUT" | grep "updated in-place" | head -5 || true
        fi
        # Check if any replacements are still planned (this shouldn't happen after refresh)
        if echo "$REFRESH_OUTPUT" | grep -q "must be replaced"; then
          echo "::warning::⚠ Some resources still need replacement after refresh"
          echo "::warning::This may indicate a configuration mismatch"
        fi
      fi
    fi
  fi
fi

# Validate ECS Services (check if they exist in AWS but not in state)
if [ -f "$PLAN_DIR/services.generated.json" ]; then
  echo "::notice::Validating ECS services..."
  
  # Get cluster name from state
  CLUSTER_NAME=$(terraform -chdir="$PLAN_DIR" output -raw ecs_cluster_name 2>/dev/null || \
    terraform -chdir="$PLAN_DIR" state show 'module.ecs_fargate.aws_ecs_cluster.this' 2>/dev/null | \
    grep -E '^\s+name\s+=' | awk '{print $3}' | tr -d '"' || echo "")
  
  if [ -n "$CLUSTER_NAME" ]; then
    # Get expected service keys from JSON
    EXPECTED_KEYS=$(jq -r '.services | keys[]' "$PLAN_DIR/services.generated.json" 2>/dev/null || echo "")
    
    # Get ECS services in state
    STATE_ECS=$(terraform -chdir="$PLAN_DIR" state list 2>/dev/null | \
      grep 'module.ecs_fargate.aws_ecs_service.services\["' | \
      sed 's/.*\["\(.*\)"\]/\1/' || echo "")
    
    # Get ECS services in AWS
    AWS_ECS=$(aws ecs list-services --cluster "$CLUSTER_NAME" \
      --query 'serviceArns[*]' --output text 2>/dev/null || echo "")
    
    # For each expected service, check if it exists in AWS
    for tf_key in $EXPECTED_KEYS; do
      # Check if in state
      if echo "$STATE_ECS" | grep -q "^$tf_key$"; then
        continue
      fi
      
      # Build expected ECS service name
      # Format: dev-{application}-{service-name}
      APP=$(echo "$tf_key" | sed 's/::.*//')
      SVC=$(echo "$tf_key" | sed 's/.*::\(.*\)/\1/')
      EXPECTED_ECS_NAME="dev-${APP}-${SVC}"
      
      # Check if exists in AWS (match by name pattern)
      if echo "$AWS_ECS" | grep -q "$EXPECTED_ECS_NAME"; then
        echo "::warning::⚠ ECS service '$tf_key' exists in AWS but not in state"
        echo "::warning::ECS service import requires service ARN - manual import may be needed"
        MISSING_COUNT=$((MISSING_COUNT + 1))
      fi
    done
  fi
fi

# Summary
if [ $IMPORTED_COUNT -gt 0 ]; then
  echo "::notice::✓ Imported $IMPORTED_COUNT resource(s) into state"
fi

if [ $MISSING_COUNT -gt 0 ]; then
  echo "::error::❌ $MISSING_COUNT resource(s) exist in AWS but couldn't be imported"
  echo "::error::These resources will cause 'already exists' errors during apply"
  exit 1
fi

if [ $ERRORS -eq 0 ] && [ $IMPORTED_COUNT -eq 0 ]; then
  echo "::notice::✓ All resources are properly in state"
fi

exit $ERRORS

