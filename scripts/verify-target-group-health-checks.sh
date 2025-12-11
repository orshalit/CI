#!/bin/bash
# Verify Target Group Health Check Paths
# This script compares Terraform configuration with actual AWS target groups
# and detects state drift

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
TERRAFORM_DIR="${TERRAFORM_DIR:-}"

if [ -z "$TERRAFORM_DIR" ]; then
    echo "Error: TERRAFORM_DIR must be set"
    exit 1
fi

print_header() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

print_success() {
    echo "✓ $1"
}

print_error() {
    echo "✗ $1"
}

print_warning() {
    echo "⚠ $1"
}

print_info() {
    echo "ℹ $1"
}

# Check if required tools are available
check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        echo "Error: aws-cli is not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed"
        exit 1
    fi
    
    if ! command -v terraform &> /dev/null; then
        echo "Error: terraform is not installed"
        exit 1
    fi
}

# Extract health check paths from Terraform state
get_terraform_health_check_paths() {
    local tf_dir="$1"
    cd "$tf_dir" || exit 1
    
    # Get all target group resources from state
    terraform state list 2>/dev/null | grep "aws_lb_target_group" | while read -r resource; do
        # Get the resource attributes using terraform state show (HCL output)
        TG_OUTPUT=$(terraform state show "$resource" 2>/dev/null || echo "")
        
        if [ -n "$TG_OUTPUT" ]; then
            # Extract target group name (look for name = "..." or name = ...)
            TG_NAME=$(echo "$TG_OUTPUT" | grep -E "^\s*name\s*=" | head -1 | sed -E 's/.*name\s*=\s*"?([^"]+)"?.*/\1/' | tr -d ' ' || echo "")
            
            # Extract health check path from health_check block
            # Look for the health_check block and find path within it
            HC_BLOCK=$(echo "$TG_OUTPUT" | sed -n '/health_check {/,/}/p')
            HC_PATH=$(echo "$HC_BLOCK" | grep -E "^\s+path\s*=" | head -1 | sed -E 's/.*path\s*=\s*"?([^"]+)"?.*/\1/' | tr -d ' ' || echo "/")
            
            # If path not found in health_check block, default to "/"
            if [ -z "$HC_PATH" ] || [ "$HC_PATH" = "" ]; then
                HC_PATH="/"
            fi
            
            # Get the service name from the resource key (e.g., module.ecs_fargate.aws_lb_target_group.services["app_shared::api"])
            SERVICE_NAME=$(echo "$resource" | sed -n 's/.*\["\([^"]*\)::\([^"]*\)"\]/\2/p' || echo "")
            
            if [ -n "$SERVICE_NAME" ] && [ -n "$TG_NAME" ]; then
                echo "$SERVICE_NAME|$HC_PATH|$TG_NAME"
            fi
        fi
    done
}

# Get health check paths from AWS
get_aws_health_check_paths() {
    aws elbv2 describe-target-groups \
        --region "$REGION" \
        --output json 2>/dev/null | \
        jq -r '.TargetGroups[] | select(.TargetGroupName | startswith("'$ENVIRONMENT'-")) | "\(.TargetGroupName)|\(.HealthCheckPath // "/")"'
}

# Compare Terraform state with AWS
compare_health_check_paths() {
    print_header "Comparing Terraform State with AWS Target Groups"
    
    local tf_dir="$TERRAFORM_DIR"
    local drift_detected=false
    
    # Get Terraform health check paths
    print_info "Reading health check paths from Terraform state..."
    TF_PATHS=$(get_terraform_health_check_paths "$tf_dir")
    
    # Get AWS health check paths
    print_info "Reading health check paths from AWS..."
    AWS_PATHS=$(get_aws_health_check_paths)
    
    # Create temp files for comparison
    TF_MAP=$(mktemp)
    AWS_MAP=$(mktemp)
    trap "rm -f $TF_MAP $AWS_MAP" EXIT
    
    # Store Terraform paths
    echo "$TF_PATHS" | while IFS='|' read -r service path tg_name; do
        if [ -n "$service" ] && [ -n "$tg_name" ]; then
            echo "$tg_name|$service|$path" >> "$TF_MAP"
        fi
    done
    
    # Store AWS paths
    echo "$AWS_PATHS" | while IFS='|' read -r tg_name path; do
        if [ -n "$tg_name" ]; then
            echo "$tg_name|$path" >> "$AWS_MAP"
        fi
    done
    
    # Compare each target group
    while IFS='|' read -r tg_name service tf_path; do
        if [ -z "$tg_name" ] || [ -z "$service" ]; then
            continue
        fi
        
        # Find matching AWS target group
        AWS_PATH=$(grep "^$tg_name|" "$AWS_MAP" 2>/dev/null | cut -d'|' -f2 || echo "")
        
        if [ -z "$AWS_PATH" ]; then
            print_warning "Target group $tg_name not found in AWS for service $service"
            drift_detected=true
        elif [ "$tf_path" != "$AWS_PATH" ]; then
            print_error "State drift detected for service $service (target group: $tg_name):"
            echo "  Terraform state: $tf_path"
            echo "  AWS actual:      $AWS_PATH"
            drift_detected=true
        else
            print_success "Service $service: Health check path matches ($tf_path)"
        fi
    done < "$TF_MAP"
    
    if [ "$drift_detected" = true ]; then
        print_error "State drift detected! Terraform state does not match AWS reality."
        echo ""
        echo "To fix this, run:"
        echo "  cd $tf_dir"
        # Check for JSON format
        if [ -f "services.generated.json" ]; then
          echo "  terraform refresh -var-file=terraform.tfvars -var-file=services.generated.json"
        else
          echo "  terraform refresh -var-file=terraform.tfvars"
        fi
        return 1
    else
        print_success "No state drift detected. Terraform state matches AWS."
        return 0
    fi
}

# Main execution
main() {
    check_prerequisites
    
    if ! compare_health_check_paths; then
        exit 1
    fi
}

main "$@"

