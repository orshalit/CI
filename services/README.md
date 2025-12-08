# ECS Service Specs (Legacy - Deprecated)

> **⚠️ DEPRECATED**: This directory is no longer used. All services have been moved to
> `applications/{app}/services/` structure. See `applications/README.md` for details.
>
> Legacy services are now in `applications/legacy/services/`.

Each file describes one service, for example:

```yaml
name: api
application: legacy  # REQUIRED - Application namespace (lowercase, alphanumeric, hyphens only)
image_repo: ghcr.io/orshalit/ci-backend
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
    - "/api/*"
  host_patterns:
    - "app.dev.example.com"  # ⚠️ Replace with actual domain or remove for ALB DNS access
```

## Service Configuration

### Required Fields

- `name`: Service name (unique within application)
- `application`: **REQUIRED** - Application namespace identifier
  - Must be lowercase, alphanumeric, and hyphens only
  - Examples: `legacy`, `customer-portal`, `admin-dashboard`
  - Invalid: `App1` (uppercase), `customer_portal` (underscore), `customer portal` (space)
- `image_repo`: Base image name (without tag)

### Optional Fields

- `image_repo` is the base image name; the actual tag is normally supplied
  at deploy time via `service_image_tags` from the CI pipeline.
- Services **attach to existing ALBs** defined in DEVOPS by referencing the ALB's key in `alb_id`.
- Creating new ALBs or Route 53 records still happens manually in the DEVOPS repo.

## ALB Topology Support

The generator supports all common ALB/service topologies:

- **Multiple services on one ALB**: Set the same `alb_id` for different services
- **Different services on different ALBs**: Use different `alb_id` values
- **Service without ALB**: Omit the `alb` block entirely (service will use Cloud Map only)

Example: Two services sharing one ALB:

```yaml
# services/api.yaml
name: api
alb:
  alb_id: app_shared
  path_patterns: ["/api/*"]

# services/frontend.yaml
name: frontend
alb:
  alb_id: app_shared  # Same ALB
  path_patterns: ["/"]
```

## Ownership Model

- **CI owns all services**: All ECS services are defined here and generated into `services.generated.tfvars`
- **DEVOPS owns ALBs/DNS**: ALB definitions, certificates, Route 53 records are managed in `terraform.tfvars`
- **No conflicts**: Services reference ALBs by key (`alb_id`), ensuring clean separation

## Environment-Specific Configuration

### Dev Environment (HTTPS Disabled)

- **listener_protocol**: Can be set to `HTTPS` in YAML, but will automatically fall back to `HTTP` if HTTPS is disabled on the ALB
- **host_patterns**: Optional - can be removed to allow access via ALB DNS name directly
- **BACKEND_API_URL**: Use `http://` (not `https://`) when HTTPS is disabled
- **Example domains**: `app.dev.example.com` is a placeholder - replace with actual domain or remove `host_patterns` to use ALB DNS

### Production Environment (HTTPS Enabled)

- **listener_protocol**: Use `HTTPS` with proper certificate configured in DEVOPS
- **host_patterns**: Set to actual production domain
- **BACKEND_API_URL**: Use `https://` with proper domain


