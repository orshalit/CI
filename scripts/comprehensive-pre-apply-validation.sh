#!/bin/bash
# Comprehensive Pre-Apply Validation Script
# Checks for all edge cases before Terraform apply

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
  echo "::notice::Comprehensive validation only runs for 04-ecs-fargate module"
  exit 0
fi

echo "::notice::🔍 Running comprehensive pre-apply validation..."

# Initialize Terraform
terraform -chdir="$PLAN_DIR" init -no-color >/dev/null 2>&1 || true

# Build var files for commands
VAR_FILES=""
if [ -f "$PLAN_DIR/terraform.tfvars" ]; then
  VAR_FILES="terraform.tfvars"
fi
if [ -f "$PLAN_DIR/services.generated.tfvars" ]; then
  if [ -n "$VAR_FILES" ]; then
    VAR_FILES="$VAR_FILES services.generated.tfvars"
  else
    VAR_FILES="services.generated.tfvars"
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

ERRORS=0
WARNINGS=0

# ============================================================================
# 1. Check for Namespace Replacement (High Priority)
# ============================================================================
echo "::notice::Checking for Service Discovery namespace replacement..."
if terraform -chdir="$PLAN_DIR" show -no-color tfplan 2>/dev/null | grep -q "aws_service_discovery_private_dns_namespace.*must be replaced"; then
  echo "::error::❌ CRITICAL: Service Discovery namespace will be replaced!"
  echo "::error::Namespace replacement will cause ALL services to fail."
  echo "::error::This requires manual intervention and coordination."
  echo "::error::"
  echo "::error::To proceed safely:"
  echo "::error::  1. Export all service discovery service IDs"
  echo "::error::  2. Create new namespace"
  echo "::error::  3. Recreate all services with new namespace"
  echo "::error::  4. Update ECS services to use new service discovery"
  ERRORS=$((ERRORS + 1))
else
  echo "::notice::✓ Namespace replacement not detected"
fi

# ============================================================================
# 2. Check ALB Listener Rule Priority Conflicts (Medium Priority)
# ============================================================================
echo "::notice::Checking ALB listener rule priority conflicts..."

# Get ALB listener ARNs from state
ALB_LISTENERS=$(terraform -chdir="$PLAN_DIR" state list 2>/dev/null | \
  grep 'module.ecs_fargate.aws_lb_listener\.' || echo "")

if [ -n "$ALB_LISTENERS" ]; then
  # Get planned priorities from plan
  PLAN_OUTPUT=$(terraform -chdir="$PLAN_DIR" show -no-color tfplan 2>&1 || echo "")
  PLANNED_RULES=$(echo "$PLAN_OUTPUT" | grep "aws_lb_listener_rule.service" | \
    grep -E "(will be created|must be replaced)" || echo "")
  
  if [ -n "$PLANNED_RULES" ]; then
    # Extract priorities from plan output
    PLANNED_PRIORITIES=""
    while IFS= read -r rule_line; do
      # Try to extract priority from plan (look for priority = X)
      PRIORITY=$(echo "$PLAN_OUTPUT" | grep -A 20 "$rule_line" | grep -E "priority\s*=" | \
        head -1 | sed 's/.*priority\s*=\s*\([0-9]*\).*/\1/' || echo "")
      if [ -n "$PRIORITY" ] && [ "$PRIORITY" != "null" ]; then
        if echo "$PLANNED_PRIORITIES" | grep -q "^${PRIORITY}$"; then
          echo "::error::❌ Priority conflict detected: priority $PRIORITY used multiple times"
          echo "::error::Rule: $rule_line"
          ERRORS=$((ERRORS + 1))
        else
          PLANNED_PRIORITIES="${PLANNED_PRIORITIES}${PRIORITY}"$'\n'
        fi
      fi
    done <<< "$PLANNED_RULES"
    
    # Also check against existing rules
    for listener_resource in $ALB_LISTENERS; do
      LISTENER_ARN=$(terraform -chdir="$PLAN_DIR" state show "$listener_resource" 2>/dev/null | \
        grep -E '^\s+arn\s+=' | awk '{print $3}' | tr -d '"' || echo "")
      
      if [ -n "$LISTENER_ARN" ]; then
        # Get existing rules and their priorities
        EXISTING_PRIORITIES=$(aws elbv2 describe-rules --listener-arn "$LISTENER_ARN" \
          --query 'Rules[?Priority!=`default`].Priority' --output text 2>/dev/null || echo "")
        
        # Check if any planned priority conflicts with existing
        for planned_priority in $PLANNED_PRIORITIES; do
          [ -z "$planned_priority" ] && continue
          if echo "$EXISTING_PRIORITIES" | grep -q "^${planned_priority}$"; then
            echo "::error::❌ Priority $planned_priority already exists on listener"
            echo "::error::This will cause apply to fail"
            ERRORS=$((ERRORS + 1))
          fi
        done
      fi
    done
    
    if [ $ERRORS -eq 0 ]; then
      echo "::notice::✓ No priority conflicts detected"
    fi
  fi
fi

# ============================================================================
# 3. Check ECS Service Desired Count Drift (Medium Priority)
# ============================================================================
echo "::notice::Checking ECS service desired count drift..."

if [ -f "$PLAN_DIR/services.generated.tfvars" ]; then
  # Get cluster name
  CLUSTER_NAME=$(terraform -chdir="$PLAN_DIR" output -raw ecs_cluster_name 2>/dev/null || \
    terraform -chdir="$PLAN_DIR" state show 'module.ecs_fargate.aws_ecs_cluster.this' 2>/dev/null | \
    grep -E '^\s+name\s+=' | awk '{print $3}' | tr -d '"' || echo "")
  
  if [ -n "$CLUSTER_NAME" ]; then
    # Get expected service keys
    EXPECTED_KEYS=$(grep -E '^\s+"[^"]+::[^"]+"\s*=\s*\{' "$PLAN_DIR/services.generated.tfvars" | \
      sed 's/^\s*"\([^"]*\)".*/\1/' || echo "")
    
    # Get desired counts from plan (more accurate than parsing tfvars)
    PLAN_OUTPUT=$(terraform -chdir="$PLAN_DIR" show -no-color tfplan 2>&1 || echo "")
    
    for tf_key in $EXPECTED_KEYS; do
      # Get service name pattern
      SVC_NAME=$(echo "$tf_key" | sed 's/.*::\(.*\)/\1/')
      APP=$(echo "$tf_key" | sed 's/::.*//')
      EXPECTED_ECS_NAME="dev-${APP}-${SVC_NAME}"
      
      # Extract desired_count from plan for this service
      PLAN_DESIRED=$(echo "$PLAN_OUTPUT" | grep -A 30 "aws_ecs_service.services\[\"$tf_key\"\]" | \
        grep -E "desired_count\s*=" | head -1 | sed 's/.*desired_count\s*=\s*\([0-9]*\).*/\1/' || echo "")
      
      # Check if service exists in AWS
      AWS_SERVICE=$(aws ecs describe-services --cluster "$CLUSTER_NAME" \
        --services "$EXPECTED_ECS_NAME" \
        --query 'services[0].[desiredCount,runningCount]' \
        --output text 2>/dev/null || echo "")
      
      if [ -n "$AWS_SERVICE" ] && [ "$AWS_SERVICE" != "None None" ]; then
        AWS_DESIRED=$(echo "$AWS_SERVICE" | awk '{print $1}')
        AWS_RUNNING=$(echo "$AWS_SERVICE" | awk '{print $2}')
        
        # Compare desired counts
        if [ -n "$PLAN_DESIRED" ] && [ "$PLAN_DESIRED" != "$AWS_DESIRED" ]; then
          DIFF=$((PLAN_DESIRED - AWS_DESIRED))
          if [ ${DIFF#-} -gt 2 ]; then  # Absolute difference > 2
            echo "::warning::⚠️ Service '$tf_key' desired count drift detected"
            echo "::warning::  Config: $PLAN_DESIRED, AWS: $AWS_DESIRED, Running: $AWS_RUNNING"
            echo "::warning::  Terraform will reset to $PLAN_DESIRED (difference: $DIFF)"
            WARNINGS=$((WARNINGS + 1))
          fi
        fi
        
        # Warn if service is in failed state
        if [ "$AWS_RUNNING" = "0" ] && [ "$AWS_DESIRED" != "0" ]; then
          echo "::warning::⚠️ Service '$tf_key' has desired=$AWS_DESIRED but running=0"
          echo "::warning::Service may be in failed state or scaling"
          WARNINGS=$((WARNINGS + 1))
        fi
      fi
    done
  fi
fi

# ============================================================================
# 4. Check Task Definition Revision Accumulation (Medium Priority)
# ============================================================================
echo "::notice::Checking task definition revision accumulation..."

if [ -f "$PLAN_DIR/services.generated.tfvars" ]; then
  EXPECTED_KEYS=$(grep -E '^\s+"[^"]+::[^"]+"\s*=\s*\{' "$PLAN_DIR/services.generated.tfvars" | \
    sed 's/^\s*"\([^"]*\)".*/\1/' || echo "")
  
  for tf_key in $EXPECTED_KEYS; do
    APP=$(echo "$tf_key" | sed 's/::.*//')
    SVC=$(echo "$tf_key" | sed 's/.*::\(.*\)/\1/')
    FAMILY="dev-${APP}-${SVC}"
    
    # Count task definition revisions
    REVISION_COUNT=$(aws ecs list-task-definitions --family-prefix "$FAMILY" \
      --status ACTIVE \
      --query 'length(taskDefinitionArns)' \
      --output text 2>/dev/null || echo "0")
    
    if [ "$REVISION_COUNT" -gt 8 ]; then
      echo "::warning::⚠️ Task definition '$FAMILY' has $REVISION_COUNT revisions"
      echo "::warning::Consider cleaning up old revisions (AWS keeps last 10 by default)"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
fi

# ============================================================================
# 5. Check Route53 Record Conflicts (Medium Priority)
# ============================================================================
echo "::notice::Checking Route53 record conflicts..."

# Check if Route53 records are being created
PLAN_OUTPUT=$(terraform -chdir="$PLAN_DIR" show -no-color tfplan 2>&1 || echo "")
if echo "$PLAN_OUTPUT" | grep -q "aws_route53_record.*will be created"; then
  echo "::notice::Route53 records will be created - checking for conflicts..."
  
  # Get zone IDs and record names from plan (approximate)
  # Would need proper plan parsing for exact values
  # For now, just warn
  echo "::warning::⚠️ Route53 records will be created"
  echo "::warning::Verify records don't already exist in the hosted zone"
  WARNINGS=$((WARNINGS + 1))
fi

# ============================================================================
# 6. Check Resource Naming Conflicts (Low Priority)
# ============================================================================
echo "::notice::Checking resource naming conflicts..."

# Check for duplicate service names (same name after sanitization)
if [ -f "$PLAN_DIR/services.generated.tfvars" ]; then
  EXPECTED_KEYS=$(grep -E '^\s+"[^"]+::[^"]+"\s*=\s*\{' "$PLAN_DIR/services.generated.tfvars" | \
    sed 's/^\s*"\([^"]*\)".*/\1/' || echo "")
  
  # Extract sanitized names (part after ::)
  SANITIZED_NAMES=""
  for tf_key in $EXPECTED_KEYS; do
    SANITIZED=$(echo "$tf_key" | sed 's/.*::\(.*\)/\1/' | tr '[:upper:]' '[:lower:]' | tr '::' '-' | tr ' ' '-' | tr '.' '-')
    if echo "$SANITIZED_NAMES" | grep -q "^${SANITIZED}$"; then
      echo "::error::❌ Duplicate sanitized service name detected: '$SANITIZED'"
      echo "::error::Service keys: $tf_key and another service"
      echo "::error::This will cause naming conflicts"
      ERRORS=$((ERRORS + 1))
    else
      SANITIZED_NAMES="${SANITIZED_NAMES}${SANITIZED}"$'\n'
    fi
  done
fi

# ============================================================================
# 7. Check Provider Version (Low Priority)
# ============================================================================
echo "::notice::Checking Terraform and provider versions..."

TERRAFORM_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || echo "unknown")
echo "::notice::Terraform version: $TERRAFORM_VERSION"

# Check if version matches expected (1.6.0)
if [ "$TERRAFORM_VERSION" != "1.6.0" ]; then
  echo "::warning::⚠️ Terraform version mismatch: expected 1.6.0, got $TERRAFORM_VERSION"
  echo "::warning::This may cause unexpected behavior"
  WARNINGS=$((WARNINGS + 1))
fi

# ============================================================================
# 8. Check Target Group Health Check Path Drift (Medium Priority)
# ============================================================================
echo "::notice::Checking target group health check path drift..."

REGION="${AWS_REGION:-us-east-1}"
DRIFT_DETECTED=false

# Get all target groups from Terraform state
TF_TGS=$(terraform -chdir="$PLAN_DIR" state list 2>/dev/null | \
  grep "aws_lb_target_group" || echo "")

if [ -n "$TF_TGS" ]; then
  for tg_resource in $TF_TGS; do
    TG_OUTPUT=$(terraform -chdir="$PLAN_DIR" state show "$tg_resource" 2>/dev/null || echo "")
    
    if [ -n "$TG_OUTPUT" ]; then
      TG_NAME=$(echo "$TG_OUTPUT" | grep -E "^\s*name\s*=" | head -1 | \
        sed -E 's/.*name\s*=\s*"?([^"]+)"?.*/\1/' | tr -d ' ' || echo "")
      HC_BLOCK=$(echo "$TG_OUTPUT" | sed -n '/health_check {/,/}/p')
      TF_PATH=$(echo "$HC_BLOCK" | grep -E "^\s+path\s*=" | head -1 | \
        sed -E 's/.*path\s*=\s*"?([^"]+)"?.*/\1/' | tr -d ' ' || echo "/")
      
      if [ -n "$TG_NAME" ]; then
        AWS_PATH=$(aws elbv2 describe-target-groups \
          --region "$REGION" \
          --names "$TG_NAME" \
          --query 'TargetGroups[0].HealthCheckPath' \
          --output text 2>/dev/null || echo "")
        
        if [ -n "$AWS_PATH" ] && [ "$AWS_PATH" != "None" ] && [ "$TF_PATH" != "$AWS_PATH" ]; then
          echo "::error::❌ Health check path drift for $TG_NAME:"
          echo "::error::  Terraform: $TF_PATH"
          echo "::error::  AWS:       $AWS_PATH"
          DRIFT_DETECTED=true
          ERRORS=$((ERRORS + 1))
        fi
      fi
    fi
  done
  
  if [ "$DRIFT_DETECTED" = false ]; then
    echo "::notice::✓ No target group health check path drift detected"
  fi
fi

# ============================================================================
# 9. Check VPC/Subnet Changes (Low Priority)
# ============================================================================
echo "::notice::Checking for VPC/subnet changes..."

# Check if VPC or subnets are being modified
PLAN_OUTPUT=$(terraform -chdir="$PLAN_DIR" show -no-color tfplan 2>&1 || echo "")
if echo "$PLAN_OUTPUT" | grep -q "data.terraform_remote_state.vpc"; then
  # VPC is from remote state - check if it changed
  echo "::notice::VPC configuration uses remote state"
  echo "::notice::Verify VPC module (01-vpc) hasn't changed recently"
  
  # Check if VPC outputs changed (would require comparing remote state)
  # For now, just inform
  echo "::notice::If VPC/subnets changed, ECS services may need to be recreated"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "::notice::📊 Validation Summary:"
echo "::notice::  Errors: $ERRORS"
echo "::notice::  Warnings: $WARNINGS"

if [ $ERRORS -gt 0 ]; then
  echo "::error::❌ Validation failed with $ERRORS error(s)"
  echo "::error::Please fix the errors above before proceeding with apply"
  exit 1
elif [ $WARNINGS -gt 0 ]; then
  echo "::warning::⚠️ Validation completed with $WARNINGS warning(s)"
  echo "::warning::Review warnings above before proceeding"
  exit 0
else
  echo "::notice::✓ All validations passed"
  exit 0
fi

