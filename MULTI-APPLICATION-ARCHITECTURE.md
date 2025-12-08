# Multi-Application Architecture Plan

## Overview

This document outlines the architecture and migration plan for transitioning from a single-application deployment to a multi-application deployment system that supports deploying multiple independent applications while maintaining best practices for isolation, scalability, and maintainability.

## Current State

### Current Structure
```
CI/
├── services/              # All services in flat structure
│   ├── api.yaml
│   ├── api_single.yaml
│   └── frontend.yaml
├── backend/               # Single backend application
├── frontend/              # Single frontend application
└── .github/workflows/
    └── app-deploy-ecs.yml # Single deployment workflow

DEVOPS/
└── live/dev/
    └── 04-ecs-fargate/    # Single ECS cluster for all services
        ├── terraform.tfvars
        └── services.generated.tfvars
```

### Current Limitations
- All services belong to one application
- No application-level isolation
- Single deployment workflow for all services
- No way to deploy different applications independently
- Shared infrastructure (ALBs, ECS cluster) for all services

## Target Architecture

### Design Principles

1. **Application Isolation**: Each application should be independently deployable
2. **Shared Infrastructure**: Common infrastructure (VPC, OIDC) shared across applications
3. **Flexible Deployment**: Support both shared and dedicated infrastructure per application
4. **Scalability**: Easy to add new applications without modifying existing ones
5. **Backward Compatibility**: Existing single-application setup should continue to work

### Proposed Structure

#### Option A: Application-Level Organization (Recommended)

```
CI/
├── applications/
│   ├── app1/                    # Application 1
│   │   ├── services/
│   │   │   ├── api.yaml
│   │   │   └── frontend.yaml
│   │   ├── backend/            # Application-specific backend
│   │   ├── frontend/           # Application-specific frontend
│   │   └── config/
│   │       └── app-config.yaml # Application-level config
│   ├── app2/                    # Application 2
│   │   └── services/
│   │       └── api.yaml
│   └── shared/                  # Shared services (optional)
│       └── services/
│           └── monitoring.yaml
├── .github/workflows/
│   ├── app-deploy-ecs.yml      # Generic workflow (uses app input)
│   └── app1-deploy.yml         # App-specific workflow (optional)
└── scripts/
    └── generate_ecs_services_tfvars.py  # Updated to support apps

DEVOPS/
└── live/
    ├── dev/
    │   ├── 04-ecs-fargate/     # Shared ECS cluster (default)
    │   │   ├── terraform.tfvars
    │   │   └── services.generated.tfvars  # All apps combined
    │   ├── 04-ecs-fargate-app1/ # Dedicated cluster for app1 (optional)
    │   └── 04-ecs-fargate-app2/ # Dedicated cluster for app2 (optional)
    └── staging/
        └── ...
```

#### Option B: Shared Cluster with Application Tags

```
CI/
├── applications/
│   ├── app1/
│   │   └── services/
│   │       ├── api.yaml        # Contains app: app1
│   │       └── frontend.yaml
│   └── app2/
│       └── services/
│           └── api.yaml         # Contains app: app2
└── ...

DEVOPS/
└── live/dev/
    └── 04-ecs-fargate/          # Single shared cluster
        ├── terraform.tfvars
        └── services.generated.tfvars  # All apps, tagged by application
```

**Recommendation**: Start with **Option B** (shared cluster with tags) for simplicity, then migrate to **Option A** if isolation requirements emerge.

## Implementation Plan

### Phase 1: Service Definition Enhancement

#### 1.1 Update Service Schema

Add `application` field to service YAML:

```yaml
# applications/app1/services/api.yaml
name: api
application: app1  # New field

image_repo: ghcr.io/orshalit/app1-backend
container_port: 8000
# ... rest of config
```

#### 1.2 Migration Path

- Keep existing `services/` directory for backward compatibility
- New applications use `applications/{app}/services/`
- Scripts support both structures during transition

### Phase 2: Infrastructure Updates

#### 2.1 Terraform Module Updates

Add application-level tags and naming:

```hcl
# In ECS Fargate module
resource "aws_ecs_service" "services" {
  for_each = local.services
  
  name = "${var.environment}-${each.value.application}-${each.key}-service"
  
  tags = merge(
    var.tags,
    {
      Application = each.value.application
      Service     = each.key
    }
  )
}
```

#### 2.2 Service Discovery Namespace

Options:
- **Shared namespace**: All apps in same namespace (simpler)
- **Per-app namespace**: One namespace per app (better isolation)

Recommendation: Start with shared namespace, add per-app namespaces later if needed.

### Phase 3: Deployment Workflow Updates

#### 3.1 Generic Deployment Workflow

Update `app-deploy-ecs.yml` to accept application parameter:

```yaml
workflow_dispatch:
  inputs:
    application:
      description: 'Application name'
      required: true
      type: choice
      options: [app1, app2, all]  # 'all' for backward compatibility
    environment:
      description: 'Target environment'
      # ...
```

#### 3.2 Application-Specific Workflows (Optional)

Create per-application workflows for convenience:

```yaml
# .github/workflows/app1-deploy.yml
name: Deploy App1
on:
  workflow_dispatch:
    inputs:
      environment:
        # ...
jobs:
  deploy:
    uses: ./.github/workflows/app-deploy-ecs.yml
    with:
      application: app1
      environment: ${{ inputs.environment }}
```

### Phase 4: Script Updates

#### 4.1 Update `generate_ecs_services_tfvars.py`

```python
def load_service_specs(applications_dir: pathlib.Path) -> list[dict]:
    """Load service specs from applications directory structure."""
    specs = []
    
    # Support both old structure (services/) and new (applications/)
    if (applications_dir / "services").exists():
        # Old structure
        for path in sorted((applications_dir / "services").glob("*.y*ml")):
            spec = load_yaml(path)
            spec["application"] = spec.get("application", "default")
            specs.append(spec)
    
    # New structure
    for app_dir in sorted(applications_dir.glob("applications/*")):
        app_name = app_dir.name
        services_dir = app_dir / "services"
        if services_dir.exists():
            for path in sorted(services_dir.glob("*.y*ml")):
                spec = load_yaml(path)
                spec["application"] = app_name
                specs.append(spec)
    
    return specs
```

#### 4.2 Filter by Application

Add filtering capability:

```python
parser.add_argument(
    "--application",
    type=str,
    help="Filter services by application (omit to include all)",
)
```

### Phase 5: Infrastructure Isolation Options

#### 5.1 Shared Cluster (Default)

- All applications share one ECS cluster
- Services tagged by application
- Cost-effective, simpler management
- Good for most use cases

#### 5.2 Dedicated Clusters (Optional)

- Per-application ECS clusters
- Better isolation, independent scaling
- Higher cost, more complex
- Use when strict isolation required

#### 5.3 Hybrid Approach

- Default: Shared cluster
- Option to create dedicated clusters for specific apps
- Configured via Terraform variables

## Migration Strategy

### Step 1: Add Application Field (Non-Breaking)

1. Update service YAML schema to include optional `application` field
2. Default to `"default"` if not specified (backward compatible)
3. Update generation script to handle both old and new structures

### Step 2: Update Infrastructure (Non-Breaking)

1. Add application tags to Terraform resources
2. Update naming conventions to include application
3. Deploy and verify existing services still work

### Step 3: Migrate Existing Services

1. Create `applications/default/services/` directory
2. Move existing services with `application: default`
3. Update workflows to use new structure

### Step 4: Add New Applications

1. Create new application directories
2. Add services with application identifier
3. Deploy and verify

## Configuration Management

### Application-Level Configuration

```yaml
# applications/app1/config/app-config.yaml
application: app1
environment: dev

infrastructure:
  cluster_type: shared  # or dedicated
  alb_id: app1-alb      # or shared ALB
  
deployment:
  auto_deploy: true
  notification_channels:
    - slack: app1-deployments
```

### Service-Level Configuration

```yaml
# applications/app1/services/api.yaml
name: api
application: app1

# Service-specific config
image_repo: ghcr.io/orshalit/app1-backend
# ...
```

## Best Practices

### 1. Naming Conventions

- Application names: lowercase, alphanumeric, hyphens (`app1`, `customer-portal`)
- Service names: lowercase, alphanumeric, hyphens (`api`, `frontend`, `worker`)
- Resource names: `{env}-{app}-{service}-{resource-type}`

### 2. Resource Isolation

- Use tags for logical isolation
- Use separate ALBs if needed for network isolation
- Use separate clusters only if required for compliance/security

### 3. Deployment Strategy

- Deploy applications independently
- Support deploying all applications (for infrastructure updates)
- Support deploying specific application services

### 4. Monitoring and Logging

- CloudWatch log groups: `/ecs/{env}/{app}/{service}`
- Service discovery: `{app}.{service}.{namespace}`
- Metrics: Tagged by application and service

## Example: Adding a New Application

### 1. Create Application Structure

```bash
mkdir -p CI/applications/customer-portal/services
```

### 2. Define Services

```yaml
# CI/applications/customer-portal/services/api.yaml
name: api
application: customer-portal

image_repo: ghcr.io/orshalit/customer-portal-api
container_port: 8000
cpu: 512
memory: 1024
desired_count: 2

alb:
  alb_id: customer-portal-alb
  listener_protocol: HTTPS
  path_patterns:
    - "/api/*"
  health_check_path: "/health"
```

### 3. Generate Terraform Config

```bash
python scripts/generate_ecs_services_tfvars.py \
  --applications-dir . \
  --devops-dir ../DEVOPS \
  --environment dev \
  --application customer-portal
```

### 4. Deploy Infrastructure

```bash
# Deploy ALB (if needed)
gh workflow run deploy-infra.yml \
  -f environment=dev \
  -f module_path=04-ecs-fargate \
  -f action=apply

# Deploy services
gh workflow run app-deploy-ecs.yml \
  -f application=customer-portal \
  -f environment=dev
```

## Rollback Plan

If issues arise:
1. Keep old `services/` directory structure working
2. Support both old and new workflows during transition
3. Can revert to single-application structure if needed

## Next Steps

1. Review and approve architecture
2. Implement Phase 1 (service schema updates)
3. Test with existing services
4. Migrate existing services
5. Add first new application
6. Document and train team

