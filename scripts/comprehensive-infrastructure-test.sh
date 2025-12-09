#!/bin/bash
# Comprehensive Infrastructure Test Script
# Tests all aspects of the ECS Fargate deployment

set -euo pipefail

ENVIRONMENT="${1:-dev}"
MODULE_PATH="${2:-04-ecs-fargate}"
PLAN_DIR="DEVOPS/live/$ENVIRONMENT/$MODULE_PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_test() {
    echo -e "${BLUE}▶${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
    TESTS_WARNED=$((TESTS_WARNED + 1))
}

# Check if Terraform is initialized
check_terraform_init() {
    print_test "Checking Terraform initialization..."
    if [ ! -d "$PLAN_DIR/.terraform" ]; then
        print_fail "Terraform not initialized. Run: terraform -chdir=$PLAN_DIR init"
        return 1
    fi
    print_pass "Terraform initialized"
}

# Get Terraform outputs
get_outputs() {
    print_test "Fetching Terraform outputs..."
    cd "$PLAN_DIR"
    
    # Initialize if needed
    terraform init -no-color >/dev/null 2>&1 || true
    
    # Get outputs
    ALB_DNS=$(terraform output -raw alb_dns_names 2>/dev/null | jq -r '.["legacy::api"]' 2>/dev/null || echo "")
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
    NAMESPACE_ID=$(terraform output -raw service_discovery_namespace_id 2>/dev/null || echo "")
    SERVICE_NAMES=$(terraform output -json service_names 2>/dev/null || echo "{}")
    LOG_GROUPS=$(terraform output -json log_group_names 2>/dev/null || echo "{}")
    
    if [ -z "$ALB_DNS" ] || [ -z "$CLUSTER_NAME" ]; then
        print_fail "Failed to get Terraform outputs. Ensure deployment is complete."
        return 1
    fi
    
    print_pass "Terraform outputs retrieved"
    echo "  ALB DNS: $ALB_DNS"
    echo "  Cluster: $CLUSTER_NAME"
    echo "  Namespace ID: $NAMESPACE_ID"
}

# Test 1: Verify ECS Cluster
test_ecs_cluster() {
    print_header "Test 1: ECS Cluster Verification"
    
    print_test "Checking ECS cluster exists..."
    if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        print_pass "ECS cluster '$CLUSTER_NAME' is ACTIVE"
    else
        print_fail "ECS cluster '$CLUSTER_NAME' not found or not active"
        return 1
    fi
    
    print_test "Checking cluster services..."
    SERVICE_COUNT=$(aws ecs list-services --cluster "$CLUSTER_NAME" --query 'serviceArns | length(@)' --output text 2>/dev/null || echo "0")
    if [ "$SERVICE_COUNT" -ge 4 ]; then
        print_pass "Found $SERVICE_COUNT services in cluster (expected at least 4)"
    else
        print_warn "Found only $SERVICE_COUNT services (expected at least 4)"
    fi
}

# Test 2: Verify ECS Services
test_ecs_services() {
    print_header "Test 2: ECS Services Verification"
    
    # Get expected service names from Terraform outputs
    EXPECTED_SERVICES=$(echo "$SERVICE_NAMES" | jq -r 'keys[]' 2>/dev/null || echo "")
    
    if [ -z "$EXPECTED_SERVICES" ]; then
        print_warn "Could not get expected services from Terraform outputs"
        return
    fi
    
    for service_key in $EXPECTED_SERVICES; do
        SERVICE_NAME=$(echo "$SERVICE_NAMES" | jq -r ".[\"$service_key\"]" 2>/dev/null || echo "")
        
        if [ -z "$SERVICE_NAME" ]; then
            print_warn "Service name not found for key: $service_key"
            continue
        fi
        
        print_test "Checking service: $SERVICE_NAME ($service_key)..."
        
        # Check if service exists
        SERVICE_STATUS=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$SERVICE_NAME" \
            --query 'services[0].status' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
            # Get running count
            RUNNING_COUNT=$(aws ecs describe-services \
                --cluster "$CLUSTER_NAME" \
                --services "$SERVICE_NAME" \
                --query 'services[0].runningCount' \
                --output text 2>/dev/null || echo "0")
            
            DESIRED_COUNT=$(aws ecs describe-services \
                --cluster "$CLUSTER_NAME" \
                --services "$SERVICE_NAME" \
                --query 'services[0].desiredCount' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$RUNNING_COUNT" -eq "$DESIRED_COUNT" ] && [ "$DESIRED_COUNT" -gt 0 ]; then
                print_pass "$SERVICE_NAME: $RUNNING_COUNT/$DESIRED_COUNT tasks running"
            else
                print_warn "$SERVICE_NAME: $RUNNING_COUNT/$DESIRED_COUNT tasks (expected $DESIRED_COUNT)"
            fi
        else
            print_fail "$SERVICE_NAME: Status is $SERVICE_STATUS (expected ACTIVE)"
        fi
    done
}

# Test 3: Verify ALB and Target Groups
test_alb_target_groups() {
    print_header "Test 3: ALB and Target Groups Verification"
    
    print_test "Checking ALB exists..."
    ALB_ARN=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?DNSName=='$ALB_DNS'].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ALB_ARN" ]; then
        print_fail "ALB with DNS $ALB_DNS not found"
        return 1
    fi
    
    print_pass "ALB found: $ALB_DNS"
    
    # Get listeners
    print_test "Checking ALB listeners..."
    HTTP_LISTENER=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$ALB_ARN" \
        --query "Listeners[?Port==\`80\`].ListenerArn" \
        --output text 2>/dev/null || echo "")
    
    HTTPS_LISTENER=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$ALB_ARN" \
        --query "Listeners[?Port==\`443\`].ListenerArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$HTTPS_LISTENER" ]; then
        print_pass "HTTPS listener (port 443) configured"
    else
        print_warn "HTTPS listener not found (HTTPS may be disabled)"
    fi
    
    if [ -n "$HTTP_LISTENER" ]; then
        print_pass "HTTP listener (port 80) configured"
    else
        print_warn "HTTP listener not found"
    fi
    
    # Check target groups
    print_test "Checking target groups health..."
    TARGET_GROUPS=$(aws elbv2 describe-target-groups \
        --query "TargetGroups[?contains(LoadBalancerArns, '$ALB_ARN')].TargetGroupArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$TARGET_GROUPS" ]; then
        print_warn "No target groups found for ALB"
        return
    fi
    
    for tg_arn in $TARGET_GROUPS; do
        TG_NAME=$(aws elbv2 describe-target-groups \
            --target-group-arns "$tg_arn" \
            --query 'TargetGroups[0].TargetGroupName' \
            --output text 2>/dev/null || echo "unknown")
        
        HEALTHY_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn "$tg_arn" \
            --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
            --output text 2>/dev/null || echo "0")
        
        TOTAL_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn "$tg_arn" \
            --query 'TargetHealthDescriptions | length(@)' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$HEALTHY_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
            print_pass "$TG_NAME: $HEALTHY_COUNT/$TOTAL_COUNT targets healthy"
        elif [ "$TOTAL_COUNT" -gt 0 ]; then
            print_warn "$TG_NAME: $HEALTHY_COUNT/$TOTAL_COUNT targets healthy"
        else
            print_warn "$TG_NAME: No targets registered"
        fi
    done
}

# Test 4: Verify Service Discovery
test_service_discovery() {
    print_header "Test 4: Service Discovery Verification"
    
    if [ -z "$NAMESPACE_ID" ]; then
        print_warn "Namespace ID not available, skipping Service Discovery tests"
        return
    fi
    
    print_test "Checking Service Discovery namespace..."
    NAMESPACE_NAME=$(aws servicediscovery get-namespace \
        --id "$NAMESPACE_ID" \
        --query 'Namespace.Name' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$NAMESPACE_NAME" ]; then
        print_pass "Namespace '$NAMESPACE_NAME' (ID: $NAMESPACE_ID) exists"
    else
        print_fail "Namespace with ID $NAMESPACE_ID not found"
        return 1
    fi
    
    # Get expected service names from Terraform
    EXPECTED_SERVICES=$(echo "$SERVICE_NAMES" | jq -r 'keys[]' 2>/dev/null || echo "")
    
    print_test "Checking Service Discovery services..."
    AWS_SERVICES=$(aws servicediscovery list-services \
        --filters Name=NAMESPACE_ID,Values="$NAMESPACE_ID" \
        --query 'Services[*].[Name,Id]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$AWS_SERVICES" ]; then
        print_warn "No Service Discovery services found in namespace (may be ECS-registered)"
        echo "  Note: ECS-registered services may not appear in list-services"
        echo "  DNS resolution is the authoritative test"
    else
        SERVICE_COUNT=$(echo "$AWS_SERVICES" | wc -l | tr -d ' ')
        print_pass "Found $SERVICE_COUNT Service Discovery services in namespace"
        
        # List services
        echo "$AWS_SERVICES" | while read -r name id; do
            echo "  - $name (ID: $id)"
        done
    fi
}

# Test 5: Verify CloudWatch Logs
test_cloudwatch_logs() {
    print_header "Test 5: CloudWatch Logs Verification"
    
    EXPECTED_LOGS=$(echo "$LOG_GROUPS" | jq -r 'keys[]' 2>/dev/null || echo "")
    
    if [ -z "$EXPECTED_LOGS" ]; then
        print_warn "Could not get expected log groups from Terraform outputs"
        return
    fi
    
    for service_key in $EXPECTED_LOGS; do
        LOG_GROUP=$(echo "$LOG_GROUPS" | jq -r ".[\"$service_key\"]" 2>/dev/null || echo "")
        
        if [ -z "$LOG_GROUP" ]; then
            print_warn "Log group not found for service: $service_key"
            continue
        fi
        
        print_test "Checking log group: $LOG_GROUP..."
        
        # Check if log group exists
        if aws logs describe-log-groups \
            --log-group-name-prefix "$LOG_GROUP" \
            --query "logGroups[?logGroupName=='$LOG_GROUP']" \
            --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
            
            # Check for recent log streams
            STREAM_COUNT=$(aws logs describe-log-streams \
                --log-group-name "$LOG_GROUP" \
                --order-by LastEventTime \
                --descending \
                --max-items 1 \
                --query 'logStreams | length(@)' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$STREAM_COUNT" -gt 0 ]; then
                print_pass "$LOG_GROUP: Active (has log streams)"
            else
                print_warn "$LOG_GROUP: Exists but no log streams yet"
            fi
        else
            print_fail "$LOG_GROUP: Log group not found"
        fi
    done
}

# Test 6: Test HTTPS Endpoints (Host-Based Routing)
test_https_endpoints() {
    print_header "Test 6: HTTPS Endpoint Testing (Host-Based Routing)"
    
    if [ -z "$ALB_DNS" ]; then
        print_warn "ALB DNS not available, skipping endpoint tests"
        return
    fi
    
    # Expected services from services.generated.tfvars
    # Based on current config: host-based routing with HTTPS
    declare -A HOSTS=(
        ["legacy-api.app.dev.light-solutions.org"]="/health"
        ["legacy-frontend.app.dev.light-solutions.org"]="/"
        ["test-api.app.dev.light-solutions.org"]="/health"
        ["test-frontend.app.dev.light-solutions.org"]="/"
    )
    
    print_test "Testing HTTPS endpoints with host headers..."
    echo "  Note: Using self-signed cert warning is expected if using test certs"
    echo ""
    
    for host in "${!HOSTS[@]}"; do
        path="${HOSTS[$host]}"
        print_test "Testing: https://$host$path"
        
        # Test with curl (ignore cert errors for testing)
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 10 \
            --insecure \
            -H "Host: $host" \
            "https://$ALB_DNS$path" 2>/dev/null || echo "000")
        
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
            print_pass "$host: HTTP $HTTP_CODE (endpoint responding)"
        elif [ "$HTTP_CODE" = "404" ]; then
            print_warn "$host: HTTP 404 (endpoint found but path not handled)"
        elif [ "$HTTP_CODE" = "000" ]; then
            print_warn "$host: Connection failed (may need VPC access or DNS)"
        else
            print_warn "$host: HTTP $HTTP_CODE (unexpected response)"
        fi
    done
    
    # Test HTTP to HTTPS redirect
    print_test "Testing HTTP to HTTPS redirect..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        -H "Host: legacy-api.app.dev.light-solutions.org" \
        "http://$ALB_DNS/health" 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        print_pass "HTTP to HTTPS redirect working (HTTP $HTTP_CODE)"
    elif [ "$HTTP_CODE" = "200" ]; then
        print_warn "HTTP endpoint responding (redirect may not be configured)"
    else
        print_warn "HTTP endpoint returned: $HTTP_CODE"
    fi
}

# Test 7: Verify Terraform State
test_terraform_state() {
    print_header "Test 7: Terraform State Verification"
    
    print_test "Checking Terraform state..."
    cd "$PLAN_DIR"
    
    # Check if state exists
    if terraform state list >/dev/null 2>&1; then
        STATE_RESOURCES=$(terraform state list | wc -l | tr -d ' ')
        print_pass "Terraform state accessible ($STATE_RESOURCES resources)"
        
        # Check for key resources
        print_test "Verifying key resources in state..."
        
        KEY_RESOURCES=(
            "module.ecs_fargate.aws_ecs_cluster.this"
            "module.ecs_fargate.aws_service_discovery_private_dns_namespace.this"
        )
        
        for resource in "${KEY_RESOURCES[@]}"; do
            if terraform state show "$resource" >/dev/null 2>&1; then
                print_pass "$resource: In state"
            else
                print_fail "$resource: Not in state"
            fi
        done
        
        # Check Service Discovery services
        SD_COUNT=$(terraform state list | grep "aws_service_discovery_service.services" | wc -l | tr -d ' ')
        if [ "$SD_COUNT" -ge 4 ]; then
            print_pass "Service Discovery services in state: $SD_COUNT (expected at least 4)"
        else
            print_warn "Service Discovery services in state: $SD_COUNT (expected at least 4)"
        fi
        
        # Check ECS services
        ECS_COUNT=$(terraform state list | grep "aws_ecs_service.services" | wc -l | tr -d ' ')
        if [ "$ECS_COUNT" -ge 4 ]; then
            print_pass "ECS services in state: $ECS_COUNT (expected at least 4)"
        else
            print_warn "ECS services in state: $ECS_COUNT (expected at least 4)"
        fi
    else
        print_fail "Terraform state not accessible"
        return 1
    fi
}

# Test 8: Verify ALB Listener Rules
test_alb_listener_rules() {
    print_header "Test 8: ALB Listener Rules Verification"
    
    if [ -z "$ALB_ARN" ]; then
        print_warn "ALB ARN not available, skipping listener rules test"
        return
    fi
    
    print_test "Checking HTTPS listener rules..."
    
    if [ -z "$HTTPS_LISTENER" ]; then
        print_warn "HTTPS listener not found, checking HTTP listener..."
        LISTENER_ARN="$HTTP_LISTENER"
    else
        LISTENER_ARN="$HTTPS_LISTENER"
    fi
    
    if [ -z "$LISTENER_ARN" ]; then
        print_warn "No listener found for rules verification"
        return
    fi
    
    RULES=$(aws elbv2 describe-rules \
        --listener-arn "$LISTENER_ARN" \
        --query 'Rules[*].[Priority, Conditions[0].HostHeaderConfig.Values[0], Actions[0].TargetGroupArn]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$RULES" ]; then
        RULE_COUNT=$(echo "$RULES" | wc -l | tr -d ' ')
        print_pass "Found $RULE_COUNT listener rules"
        
        echo "$RULES" | while read -r priority host tg_arn; do
            if [ "$priority" = "default" ]; then
                echo "  - Default rule (catch-all)"
            else
                TG_NAME=$(aws elbv2 describe-target-groups \
                    --target-group-arns "$tg_arn" \
                    --query 'TargetGroups[0].TargetGroupName' \
                    --output text 2>/dev/null || echo "unknown")
                echo "  - Priority $priority: Host '$host' → $TG_NAME"
            fi
        done
    else
        print_warn "No listener rules found"
    fi
}

# Main execution
main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Comprehensive Infrastructure Test Suite                 ║${NC}"
    echo -e "${GREEN}║     Environment: $ENVIRONMENT | Module: $MODULE_PATH${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Initialize
    check_terraform_init || exit 1
    get_outputs || exit 1
    
    # Run tests
    test_terraform_state
    test_ecs_cluster
    test_ecs_services
    test_alb_target_groups
    test_alb_listener_rules
    test_service_discovery
    test_cloudwatch_logs
    test_https_endpoints
    
    # Summary
    print_header "Test Summary"
    echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "${YELLOW}Warnings:${NC} $TESTS_WARNED"
    echo -e "${RED}Failed:${NC} $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All critical tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed. Review output above.${NC}"
        exit 1
    fi
}

# Run main
main "$@"

