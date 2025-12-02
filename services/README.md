# ECS Service Specs (CI-driven)

This directory defines **logical ECS services** in a simple YAML format.
The `create-ecs-service` workflow reads these specs and generates the
corresponding Terraform `services` blocks in the `DEVOPS` repo.

Each file describes one service, for example:

```yaml
name: api
image_repo: ghcr.io/orshalit/CI/ci-backend
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

Notes:

- `image_repo` is the base image name; the actual tag is normally supplied
  at deploy time via `service_image_tags` from the CI pipeline.
- This first version focuses on **attaching services to existing ALBs**.
  Creating new ALBs or Route 53 records still happens in the DEVOPS repo.


