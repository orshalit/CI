#!/bin/bash
################################################################################
# ECS Deployment Diagnostic Script
#
# This script performs comprehensive diagnostics on ECS deployments to identify
# issues with services, tasks, target groups, load balancers, and networking.
#
# Prerequisites:
# - AWS CLI installed and configured
# - jq installed (for JSON parsing)
#   Install with: sudo apt-get install jq (Ubuntu/Debian)
#                  or: brew install jq (macOS)
################################################################################

set -euo pipefail

# Check prerequisites
check_prerequisites() {
    local missing_tools=()
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}❌ Missing required tools: ${missing_tools[*]}${NC}"
        echo ""
        echo "Installation instructions:"
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "aws-cli")
                    echo "  AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
                    ;;
                "jq")
                    if command -v apt-get &> /dev/null; then
                        echo "  jq: sudo apt-get update && sudo apt-get install -y jq"
                    elif command -v yum &> /dev/null; then
                        echo "  jq: sudo yum install -y jq"
                    elif command -v brew &> /dev/null; then
                        echo "  jq: brew install jq"
                    else
                        echo "  jq: https://stedolan.github.io/jq/download/"
                    fi
                    ;;
            esac
        done
        echo ""
        exit 1
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-dev-ecs-cluster}"
REGION="${AWS_REGION:-us-east-1}"
SERVICES=("dev-api-service" "dev-api_single-service" "dev-frontend-service")

print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# ============================================================================
# 1. Check ECS Service Status
# ============================================================================
check_ecs_services() {
    print_header "1. Checking ECS Service Status"
    
    for service in "${SERVICES[@]}"; do
        echo ""
        print_info "Service: $service"
        
        SERVICE_INFO=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$service" \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        if [ "$SERVICE_INFO" = "{}" ]; then
            print_error "Service $service not found"
            continue
        fi
        
        # Extract key information
        DESIRED_COUNT=$(echo "$SERVICE_INFO" | jq -r '.services[0].desiredCount // 0')
        RUNNING_COUNT=$(echo "$SERVICE_INFO" | jq -r '.services[0].runningCount // 0')
        PENDING_COUNT=$(echo "$SERVICE_INFO" | jq -r '.services[0].pendingCount // 0')
        STATUS=$(echo "$SERVICE_INFO" | jq -r '.services[0].status // "unknown"')
        
        echo "  Desired: $DESIRED_COUNT | Running: $RUNNING_COUNT | Pending: $PENDING_COUNT"
        echo "  Status: $STATUS"
        
        if [ "$RUNNING_COUNT" -eq "$DESIRED_COUNT" ] && [ "$DESIRED_COUNT" -gt 0 ]; then
            print_success "Service has all tasks running"
        else
            print_warning "Service does not have all tasks running"
        fi
        
        # Check recent events
        echo ""
        echo "  Recent Events:"
        echo "$SERVICE_INFO" | jq -r '.services[0].events[:3] | .[] | "    [\(.createdAt)] \(.message)"' || echo "    No events found"
    done
}

# ============================================================================
# 2. Check Stopped Tasks and Their Reasons
# ============================================================================
check_stopped_tasks() {
    print_header "2. Checking Stopped Tasks"
    
    for service in "${SERVICES[@]}"; do
        echo ""
        print_info "Service: $service"
        
        STOPPED_TASKS=$(aws ecs list-tasks \
            --cluster "$CLUSTER_NAME" \
            --service-name "$service" \
            --desired-status STOPPED \
            --region "$REGION" \
            --max-items 5 \
            --output json 2>/dev/null | jq -r '.taskArns[]' || echo "")
        
        if [ -z "$STOPPED_TASKS" ]; then
            print_success "No stopped tasks found"
            continue
        fi
        
        print_warning "Found stopped tasks. Analyzing..."
        
        for task_arn in $STOPPED_TASKS; do
            TASK_INFO=$(aws ecs describe-tasks \
                --cluster "$CLUSTER_NAME" \
                --tasks "$task_arn" \
                --region "$REGION" \
                --output json 2>/dev/null || echo "{}")
            
            STOP_CODE=$(echo "$TASK_INFO" | jq -r '.tasks[0].stopCode // "unknown"')
            STOP_REASON=$(echo "$TASK_INFO" | jq -r '.tasks[0].stoppedReason // "unknown"')
            EXIT_CODE=$(echo "$TASK_INFO" | jq -r '.tasks[0].containers[0].exitCode // "N/A"')
            
            echo "  Task: $(basename $task_arn)"
            echo "    Stop Code: $STOP_CODE"
            echo "    Stop Reason: $STOP_REASON"
            echo "    Exit Code: $EXIT_CODE"
            
            if [ "$STOP_CODE" != "UserInitiated" ]; then
                print_error "Task stopped unexpectedly: $STOP_REASON"
            fi
        done
    done
}

# ============================================================================
# 3. Check Target Groups and Load Balancer Associations
# ============================================================================
check_target_groups() {
    print_header "3. Checking Target Groups and Load Balancer Associations"
    
    # Get all target groups (keep as JSON)
    TARGET_GROUPS_JSON=$(aws elbv2 describe-target-groups \
        --region "$REGION" \
        --output json 2>/dev/null | jq '[.TargetGroups[] | select(.TargetGroupName | startswith("dev-"))]' || echo "[]")
    
    if [ "$TARGET_GROUPS_JSON" = "[]" ] || [ -z "$TARGET_GROUPS_JSON" ]; then
        print_error "No target groups found"
        return
    fi
    
    # Process each target group
    echo "$TARGET_GROUPS_JSON" | jq -r '.[] | @json' | while read -r tg_json; do
        TG_NAME=$(echo "$tg_json" | jq -r '.TargetGroupName')
        TG_ARN=$(echo "$tg_json" | jq -r '.TargetGroupArn')
        TG_PORT=$(echo "$tg_json" | jq -r '.Port')
        TG_PROTOCOL=$(echo "$tg_json" | jq -r '.Protocol')
        TG_VPC=$(echo "$tg_json" | jq -r '.VpcId')
        
        echo ""
        print_info "Target Group: $TG_NAME"
        echo "  Port: $TG_PORT | Protocol: $TG_PROTOCOL | VPC: $TG_VPC"
        
        # Get all load balancers first
        ALL_LBS=$(aws elbv2 describe-load-balancers \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        # Check if target group is associated with any listener or rule
        ASSOCIATED=false
        LISTENER_INFO=""
        
        # Iterate through all load balancers
        for LB_ARN in $(echo "$ALL_LBS" | jq -r '.LoadBalancers[]?.LoadBalancerArn // empty'); do
            # Get listeners for this load balancer
            LISTENERS_JSON=$(aws elbv2 describe-listeners \
                --load-balancer-arn "$LB_ARN" \
                --region "$REGION" \
                --output json 2>/dev/null || echo "{}")
            
            # Check if target group is in default action of any listener
            DEFAULT_MATCH=$(echo "$LISTENERS_JSON" | jq -r --arg tg_arn "$TG_ARN" '[.Listeners[]? | select(.DefaultActions[]?.TargetGroupArn == $tg_arn or (.DefaultActions[]?.ForwardConfig.TargetGroups[]?.TargetGroupArn // "") == $tg_arn)] | length')
            
            if [ "$DEFAULT_MATCH" != "0" ] && [ -n "$DEFAULT_MATCH" ]; then
                ASSOCIATED=true
                LISTENER_INFO="default action"
                break
            fi
            
            # Check rules for each listener
            for LISTENER_ARN in $(echo "$LISTENERS_JSON" | jq -r '.Listeners[]?.ListenerArn // empty'); do
                RULES_JSON=$(aws elbv2 describe-rules \
                    --listener-arn "$LISTENER_ARN" \
                    --region "$REGION" \
                    --output json 2>/dev/null || echo "{}")
                
                RULE_MATCH=$(echo "$RULES_JSON" | jq -r --arg tg_arn "$TG_ARN" '[.Rules[]? | select(.Actions[]?.TargetGroupArn == $tg_arn or (.Actions[]?.ForwardConfig.TargetGroups[]?.TargetGroupArn // "") == $tg_arn)] | length')
                
                if [ "$RULE_MATCH" != "0" ] && [ -n "$RULE_MATCH" ]; then
                    ASSOCIATED=true
                    LISTENER_INFO="listener rule"
                    break
                fi
            done
            
            if [ "$ASSOCIATED" = "true" ]; then
                break
            fi
        done
        
        if [ "$ASSOCIATED" = "true" ]; then
            print_success "Target group is associated with a load balancer ($LISTENER_INFO)"
        else
            print_error "Target group is NOT associated with any load balancer listener"
        fi
        
        # Check target health
        HEALTH=$(aws elbv2 describe-target-health \
            --target-group-arn "$TG_ARN" \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        HEALTHY_COUNT=$(echo "$HEALTH" | jq -r '[.TargetHealthDescriptions[]? | select(.TargetHealth.State == "healthy")] | length')
        UNHEALTHY_COUNT=$(echo "$HEALTH" | jq -r '[.TargetHealthDescriptions[]? | select(.TargetHealth.State != "healthy")] | length')
        TOTAL_TARGETS=$(echo "$HEALTH" | jq -r '.TargetHealthDescriptions | length')
        
        echo "  Health: $HEALTHY_COUNT/$TOTAL_TARGETS healthy, $UNHEALTHY_COUNT unhealthy"
        
        if [ "$UNHEALTHY_COUNT" -gt 0 ]; then
            print_warning "Unhealthy targets found:"
            echo "$HEALTH" | jq -r '.TargetHealthDescriptions[]? | select(.TargetHealth.State != "healthy") | "    Target: \(.Target.Id) | State: \(.TargetHealth.State) | Reason: \(.TargetHealth.Reason // "N/A") | Description: \(.TargetHealth.Description // "N/A")"'
            
            # Show health check configuration
            HEALTH_CHECK=$(echo "$tg_json" | jq -r '.HealthCheckPath // "N/A"')
            echo "  Health Check Path: $HEALTH_CHECK"
        fi
        
        # Show health check configuration
        HC_PATH=$(echo "$tg_json" | jq -r '.HealthCheckPath // "N/A"')
        HC_PORT=$(echo "$tg_json" | jq -r '.HealthCheckPort // "N/A"')
        HC_PROTOCOL=$(echo "$tg_json" | jq -r '.HealthCheckProtocol // "N/A"')
        HC_INTERVAL=$(echo "$tg_json" | jq -r '.HealthCheckIntervalSeconds // "N/A"')
        HC_TIMEOUT=$(echo "$tg_json" | jq -r '.HealthCheckTimeoutSeconds // "N/A"')
        HC_THRESHOLD=$(echo "$tg_json" | jq -r '.HealthyThresholdCount // "N/A"')
        HC_UNHEALTHY_THRESHOLD=$(echo "$tg_json" | jq -r '.UnhealthyThresholdCount // "N/A"')
        
        echo "  Health Check Config:"
        echo "    Path: $HC_PATH | Port: $HC_PORT | Protocol: $HC_PROTOCOL"
        echo "    Interval: ${HC_INTERVAL}s | Timeout: ${HC_TIMEOUT}s"
        echo "    Healthy Threshold: $HC_THRESHOLD | Unhealthy Threshold: $HC_UNHEALTHY_THRESHOLD"
    done
}

# ============================================================================
# 4. Check Load Balancers and Listeners
# ============================================================================
check_load_balancers() {
    print_header "4. Checking Load Balancers and Listeners"
    
    # Get all load balancers (keep as JSON)
    ALBS_JSON=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --output json 2>/dev/null | jq '[.LoadBalancers[] | select(.LoadBalancerName | startswith("dev-"))]' || echo "[]")
    
    if [ "$ALBS_JSON" = "[]" ] || [ -z "$ALBS_JSON" ]; then
        print_error "No load balancers found"
        return
    fi
    
    # Process each load balancer
    echo "$ALBS_JSON" | jq -r '.[] | @json' | while read -r alb_json; do
        ALB_NAME=$(echo "$alb_json" | jq -r '.LoadBalancerName')
        ALB_DNS=$(echo "$alb_json" | jq -r '.DNSName')
        ALB_STATE=$(echo "$alb_json" | jq -r '.State.Code')
        ALB_ARN=$(echo "$alb_json" | jq -r '.LoadBalancerArn')
        
        echo ""
        print_info "Load Balancer: $ALB_NAME"
        echo "  DNS: $ALB_DNS | State: $ALB_STATE"
        
        # Check listeners
        LISTENERS=$(aws elbv2 describe-listeners \
            --load-balancer-arn "$ALB_ARN" \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        LISTENER_COUNT=$(echo "$LISTENERS" | jq -r '.Listeners | length')
        echo "  Listeners: $LISTENER_COUNT"
        
        if [ "$LISTENER_COUNT" -eq 0 ]; then
            print_error "No listeners configured for this load balancer"
        else
            echo "$LISTENERS" | jq -r '.Listeners[] | "    Port: \(.Port) | Protocol: \(.Protocol) | Rules: \(.DefaultActions | length)"'
        fi
    done
}

# ============================================================================
# 5. Check CloudWatch Logs
# ============================================================================
check_cloudwatch_logs() {
    print_header "5. Checking CloudWatch Logs (Last 10 lines per service)"
    
    for service in "${SERVICES[@]}"; do
        # Map service name to log group
        case "$service" in
            "dev-api-service")
                LOG_GROUP="/ecs/dev/api"
                ;;
            "dev-api_single-service")
                LOG_GROUP="/ecs/dev/api_single"
                ;;
            "dev-frontend-service")
                LOG_GROUP="/ecs/dev/frontend"
                ;;
            *)
                LOG_GROUP="/ecs/dev/${service#dev-}"
                ;;
        esac
        
        echo ""
        print_info "Service: $service (Log Group: $LOG_GROUP)"
        
        # Check if log group exists
        LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
            --log-group-name-prefix "$LOG_GROUP" \
            --region "$REGION" \
            --output json 2>/dev/null | jq -r --arg lg "$LOG_GROUP" '.logGroups[] | select(.logGroupName == $lg) | .logGroupName' || echo "")
        
        if [ -z "$LOG_GROUP_EXISTS" ]; then
            print_warning "Log group $LOG_GROUP does not exist"
            continue
        fi
        
        # Get recent log events
        LOG_STREAMS=$(aws logs describe-log-streams \
            --log-group-name "$LOG_GROUP" \
            --order-by LastEventTime \
            --descending \
            --max-items 1 \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        STREAM_NAME=$(echo "$LOG_STREAMS" | jq -r '.logStreams[0].logStreamName // empty')
        
        if [ -z "$STREAM_NAME" ]; then
            print_warning "No log streams found"
            continue
        fi
        
        # Get last 10 log events
        LOG_EVENTS=$(aws logs get-log-events \
            --log-group-name "$LOG_GROUP" \
            --log-stream-name "$STREAM_NAME" \
            --limit 10 \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        ERROR_COUNT=$(echo "$LOG_EVENTS" | jq -r '[.events[] | select(.message | test("(?i)(error|exception|fatal|failed)"))] | length')
        
        if [ "$ERROR_COUNT" -gt 0 ]; then
            print_error "Found $ERROR_COUNT error messages in recent logs"
            echo "$LOG_EVENTS" | jq -r '.events[] | select(.message | test("(?i)(error|exception|fatal|failed)")) | "    [\(.timestamp)] \(.message)"'
        else
            print_success "No errors in recent logs"
        fi
        
        echo "  Recent log entries:"
        echo "$LOG_EVENTS" | jq -r '.events[-3:] | .[] | "    [\(.timestamp)] \(.message)"' | head -3 || echo "    No recent logs"
    done
}

# ============================================================================
# 6. Check Task Definitions
# ============================================================================
check_task_definitions() {
    print_header "6. Checking Task Definitions"
    
    for service in "${SERVICES[@]}"; do
        echo ""
        print_info "Service: $service"
        
        SERVICE_INFO=$(aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$service" \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        TASK_DEF_ARN=$(echo "$SERVICE_INFO" | jq -r '.services[0].taskDefinition // empty')
        
        if [ -z "$TASK_DEF_ARN" ]; then
            print_error "No task definition found for service"
            continue
        fi
        
        echo "  Task Definition: $TASK_DEF_ARN"
        
        TASK_DEF=$(aws ecs describe-task-definition \
            --task-definition "$TASK_DEF_ARN" \
            --region "$REGION" \
            --output json 2>/dev/null || echo "{}")
        
        # Check container definitions
        CONTAINERS=$(echo "$TASK_DEF" | jq -r '.taskDefinition.containerDefinitions[] | "    Container: \(.name) | Image: \(.image) | CPU: \(.cpu // "N/A") | Memory: \(.memory // "N/A")"')
        
        if [ -n "$CONTAINERS" ]; then
            echo "$CONTAINERS"
        else
            print_error "No container definitions found"
        fi
        
        # Check if image exists (basic check)
        IMAGE=$(echo "$TASK_DEF" | jq -r '.taskDefinition.containerDefinitions[0].image // empty')
        if [ -n "$IMAGE" ]; then
            echo "  Image: $IMAGE"
            # Note: Full image validation would require authentication
        fi
    done
}

# ============================================================================
# 7. Check Network Connectivity
# ============================================================================
check_network() {
    print_header "7. Checking Network Configuration"
    
    # Get VPC ID from cluster
    CLUSTER_INFO=$(aws ecs describe-clusters \
        --clusters "$CLUSTER_NAME" \
        --region "$REGION" \
        --output json 2>/dev/null || echo "{}")
    
    # Get security groups
    print_info "Checking Security Groups"
    
    ALB_SG=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=group-name,Values=*-alb-sg*" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    ECS_SG=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --filters "Name=group-name,Values=*-ecs-tasks-sg*" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ALB_SG" ] && [ "$ALB_SG" != "None" ]; then
        print_success "ALB Security Group: $ALB_SG"
    else
        print_error "ALB Security Group not found"
    fi
    
    if [ -n "$ECS_SG" ] && [ "$ECS_SG" != "None" ]; then
        print_success "ECS Tasks Security Group: $ECS_SG"
        
        # Check if ECS SG allows traffic from ALB SG
        if [ -n "$ALB_SG" ] && [ "$ALB_SG" != "None" ]; then
            INGRESS_RULE=$(aws ec2 describe-security-groups \
                --group-ids "$ECS_SG" \
                --region "$REGION" \
                --query "SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId=='$ALB_SG']]" \
                --output json 2>/dev/null || echo "[]")
            
            if [ "$INGRESS_RULE" != "[]" ] && [ -n "$INGRESS_RULE" ]; then
                print_success "ECS SG allows traffic from ALB SG"
            else
                print_error "ECS SG does NOT allow traffic from ALB SG"
            fi
        fi
    else
        print_error "ECS Tasks Security Group not found"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================
main() {
    # Check prerequisites first
    check_prerequisites
    
    echo ""
    print_header "ECS Deployment Diagnostic Report"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $REGION"
    echo "Timestamp: $(date)"
    
    check_ecs_services
    check_stopped_tasks
    check_target_groups
    check_load_balancers
    check_cloudwatch_logs
    check_task_definitions
    check_network
    
    echo ""
    print_header "Diagnostic Complete"
    echo ""
    print_info "Review the output above to identify issues."
    echo "Common issues to look for:"
    echo "  - Tasks stopped with non-zero exit codes"
    echo "  - Target groups not associated with load balancers"
    echo "  - Unhealthy targets in target groups"
    echo "  - Errors in CloudWatch logs"
    echo "  - Security group misconfigurations"
}

# Run main function
main "$@"

