# Service Defaults Control Guide

## Overview

The `generate_ecs_services_tfvars.py` script **no longer uses hardcoded defaults**. All required fields must be explicitly defined in your service YAML files.

## Required Fields

Every service definition **must** include these fields:

```yaml
name: my-service
application: my-app
image_repo: ghcr.io/owner/image-name
container_port: 8000    # Required: 1-65535
cpu: 256                 # Required: 256-4096, must be multiple of 256
memory: 512              # Required: 512-30720 MB
desired_count: 2         # Required: 0-1000
```

## How to Control Defaults

### Option 1: Define in Each Service YAML (Recommended)

Explicitly set values in each service definition:

```yaml
name: api
application: legacy
image_repo: ghcr.io/orshalit/ci-backend
container_port: 8000
cpu: 256
memory: 512
desired_count: 2
```

**Benefits:**
- Clear and explicit configuration
- Easy to see what each service uses
- No hidden defaults

### Option 2: Use YAML Anchors (For Shared Defaults)

If you have multiple services with similar configurations, use YAML anchors:

```yaml
# Define defaults once
x-defaults: &defaults
  cpu: 256
  memory: 512
  desired_count: 2

# Use in services
services:
  - name: api
    <<: *defaults
    container_port: 8000
  
  - name: frontend
    <<: *defaults
    container_port: 3000
```

**Note:** The generation script processes individual YAML files, so anchors work within a single file but not across files.

### Option 3: Template Service Definitions

Create a template service definition and copy it for new services:

```yaml
# template-service.yaml
name: SERVICE_NAME
application: APP_NAME
image_repo: ghcr.io/owner/image-name
container_port: 8000
cpu: 256
memory: 512
desired_count: 2

env:
  LOG_LEVEL: INFO

alb:
  alb_id: app_shared
  listener_protocol: HTTPS
  listener_port: 443
  path_patterns:
    - "/path/*"
  health_check_path: "/health"
```

## Validation Rules

The script validates:

1. **Required Fields**: All must be present (no defaults)
2. **Type Validation**: Correct data types (int, string, etc.)
3. **Range Validation**: Values within acceptable ranges
4. **ECS Fargate Constraints**:
   - CPU must be multiple of 256
   - CPU/memory must match valid Fargate combinations
5. **ALB Configuration**: Valid protocols, ports, patterns

## Error Messages

If a required field is missing, you'll get a helpful error:

```
Service 'my-service' (application: my-app) is missing required field 'cpu'.
  CPU units (256-4096, must be multiple of 256 for Fargate)
  Add 'cpu' to the service definition.
```

## Migration from Old Script

If you have services that relied on old defaults:

1. **Check existing services**: They likely already have explicit values
2. **Add missing fields**: If any are missing, add them explicitly
3. **Validate**: Run the generation script to check for issues

## Best Practices

1. **Be Explicit**: Always define all required fields
2. **Document**: Add comments explaining why specific values are chosen
3. **Validate Early**: Run the generation script in CI/CD to catch issues
4. **Use Consistent Values**: For similar services, use the same defaults across your YAML files

## Example: Complete Service Definition

```yaml
name: api
application: legacy

# Docker image repository (without tag)
image_repo: ghcr.io/orshalit/ci-backend

# Container configuration (all required)
container_port: 8000
cpu: 256
memory: 512
desired_count: 2

# Environment variables (optional)
env:
  LOG_LEVEL: INFO
  DATABASE_URL: ""

# ALB configuration (optional)
alb:
  alb_id: app_shared
  listener_protocol: HTTPS
  listener_port: 443
  path_patterns:
    - "/api/*"
  host_patterns:
    - "app.dev.example.com"
  health_check_path: "/health"
```

