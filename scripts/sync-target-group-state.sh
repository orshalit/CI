#!/bin/bash
# Force sync Terraform state with AWS target group health check paths
# This script can be used to fix state drift

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
TERRAFORM_DIR="${TERRAFORM_DIR:-}"

if [ -z "$TERRAFORM_DIR" ]; then
    echo "Error: TERRAFORM_DIR must be set"
    exit 1
fi

print_info() {
    echo "ℹ $1"
}

print_success() {
    echo "✓ $1"
}

# Force refresh Terraform state
force_refresh() {
    local tf_dir="$TERRAFORM_DIR"
    cd "$tf_dir" || exit 1
    
    print_info "Forcing Terraform state refresh..."
    
    # Build refresh arguments
    REFRESH_ARGS="-no-color"
    
    if [ -f "terraform.tfvars" ]; then
        REFRESH_ARGS="$REFRESH_ARGS -var-file=terraform.tfvars"
    fi
    
    if [ -f "services.generated.tfvars" ]; then
        REFRESH_ARGS="$REFRESH_ARGS -var-file=services.generated.tfvars"
    fi
    
    # Run refresh
    if terraform refresh $REFRESH_ARGS; then
        print_success "State refresh completed successfully"
        return 0
    else
        echo "Error: State refresh failed"
        return 1
    fi
}

# Main execution
main() {
    if ! command -v terraform &> /dev/null; then
        echo "Error: terraform is not installed"
        exit 1
    fi
    
    force_refresh
}

main "$@"

