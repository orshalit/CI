# ECS Service Specs (CI-driven)

This directory defines **logical ECS services** in a simple YAML format.
The `create-ecs-service` workflow reads these specs and generates the
corresponding Terraform `services` blocks in the `DEVOPS` repo.

Each file describes one service, for example:

```yaml
name: api
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
    - "app.dev.example.com"
```

## Service Configuration

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


