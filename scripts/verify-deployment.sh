#!/bin/bash
# Verify what's actually deployed and running in ECS

set -e

ENVIRONMENT="${1:-dev}"
CLUSTER_NAME="${ENVIRONMENT}-ecs-cluster"

echo "=========================================="
echo "ECS Deployment Verification"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Cluster: $CLUSTER_NAME"
echo ""

# Check ECS services
echo "📋 ECS Services:"
aws ecs list-services --cluster "$CLUSTER_NAME" --query 'serviceArns[]' --output table || echo "  Error: Could not list services"
echo ""

# Check running tasks and their image tags
echo "🐳 Running Tasks (showing image tags):"
SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --query 'serviceArns[]' --output text 2>/dev/null || echo "")

if [ -z "$SERVICES" ]; then
  echo "  No services found"
else
  for SERVICE_ARN in $SERVICES; do
    SERVICE_NAME=$(echo "$SERVICE_ARN" | awk -F'/' '{print $NF}')
    echo ""
    echo "  Service: $SERVICE_NAME"
    
    # Get running tasks
    TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --service-name "$SERVICE_NAME" --desired-status RUNNING --query 'taskArns[]' --output text 2>/dev/null || echo "")
    
    if [ -z "$TASKS" ]; then
      echo "    ⚠️  No running tasks"
    else
      TASK_COUNT=$(echo "$TASKS" | wc -w)
      echo "    Running tasks: $TASK_COUNT"
      
      # Get image URI from first task
      FIRST_TASK=$(echo "$TASKS" | awk '{print $1}')
      if [ -n "$FIRST_TASK" ]; then
        IMAGE_URI=$(aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks "$FIRST_TASK" \
          --query 'tasks[0].containers[0].image' --output text 2>/dev/null || echo "unknown")
        echo "    Image: $IMAGE_URI"
        
        # Extract tag
        TAG=$(echo "$IMAGE_URI" | awk -F':' '{print $NF}')
        if [ "$TAG" = "latest" ]; then
          echo "    ⚠️  Warning: Using 'latest' tag (not immutable)"
        else
          echo "    ✓ Using immutable tag: $TAG"
        fi
      fi
    fi
    
    # Check service status
    SERVICE_STATUS=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" \
      --query 'services[0].{Running:runningCount,Desired:desiredCount,Status:status}' --output text 2>/dev/null || echo "")
    if [ -n "$SERVICE_STATUS" ]; then
      echo "    Status: $SERVICE_STATUS"
    fi
  done
fi

echo ""
echo "=========================================="
echo "Service Discovery (Cloud Map)"
echo "=========================================="

# Get namespace ID
NAMESPACE_ID=$(aws servicediscovery list-namespaces --query "Namespaces[?Name=='local'].Id" --output text 2>/dev/null || echo "")

if [ -z "$NAMESPACE_ID" ]; then
  echo "⚠️  Namespace 'local' not found"
else
  echo "Namespace ID: $NAMESPACE_ID"
  echo ""
  echo "Services registered in Service Discovery:"
  
  SERVICES=$(aws servicediscovery list-services --filters "Name=NAMESPACE_ID,Values=$NAMESPACE_ID" \
    --query 'Services[].[Name,Id]' --output text 2>/dev/null || echo "")
  
  if [ -z "$SERVICES" ]; then
    echo "  ⚠️  No services found (this is why AWS console shows 0 services)"
    echo "  Note: Services appear here only when ECS tasks are running and registered"
  else
    echo "$SERVICES" | while read -r NAME ID; do
      echo "  - $NAME (ID: $ID)"
      
      # Check if service has instances (running tasks)
      INSTANCES=$(aws servicediscovery list-instances --service-id "$ID" \
        --query 'Instances[]' --output text 2>/dev/null || echo "")
      if [ -z "$INSTANCES" ]; then
        echo "    ⚠️  No instances registered (tasks may not be running)"
      else
        INSTANCE_COUNT=$(echo "$INSTANCES" | wc -w)
        echo "    ✓ $INSTANCE_COUNT instance(s) registered"
      fi
    done
  fi
fi

echo ""
echo "=========================================="
echo "ALB Target Groups"
echo "=========================================="

# Get ALB ARNs
ALBS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `dev-app-shared`)].LoadBalancerArn' --output text 2>/dev/null || echo "")

if [ -z "$ALBS" ]; then
  echo "⚠️  No ALBs found"
else
  for ALB_ARN in $ALBS; do
    ALB_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
      --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null || echo "unknown")
    echo "ALB: $ALB_NAME"
    
    # Get target groups
    TARGET_GROUPS=$(aws elbv2 describe-target-groups --load-balancer-arn "$ALB_ARN" \
      --query 'TargetGroups[].[TargetGroupName,HealthCheckPath,Targets[].{Id:Id,Port:Port,State:State}]' --output json 2>/dev/null || echo "[]")
    
    if [ "$TARGET_GROUPS" != "[]" ] && [ -n "$TARGET_GROUPS" ]; then
      echo "$TARGET_GROUPS" | python3 -m json.tool 2>/dev/null || echo "$TARGET_GROUPS"
    else
      echo "  No target groups found"
    fi
    echo ""
  done
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "To verify what's actually serving traffic:"
echo "1. Check ALB DNS name and test URLs:"
echo "   - test-frontend.app.dev.light-solutions.org"
echo "   - test-api.app.dev.light-solutions.org"
echo ""
echo "2. Check ECS console for running tasks and their image tags"
echo ""
echo "3. Service Discovery shows 0 because tasks need to be RUNNING"
echo "   and registered. Check ECS tasks status above."
echo ""

