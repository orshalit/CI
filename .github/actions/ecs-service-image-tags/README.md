## `ecs-service-image-tags`: service generation & handling (multi-application ECS deployments)

This document defines the **contract** and **runtime behavior** for how ECS services are generated from Dhall, how `services.generated.json` is normalized, and how per-service Docker image tags are resolved during deploy.

### End-to-end flow

```mermaid
flowchart TD
  A[CI repo: dhall/applications/*/*.dhall\nService records] --> B[CI repo: dhall/services.dhall\nAggregates Service list]
  B --> C[CI repo: dhall/toTerraformJSON.dhall\nBuilds Terraform service keys\napplication::service-name]
  C --> D[CI repo: dhall/services.tfvarsJSON.dhall\nProduces Terraform tfvars JSON structure]
  D --> E[deploy.yml: dhall-to-json\n-> DEVOPS/live/<env>/04-ecs-fargate/services.generated.json]

  F[CI/CD Pipeline: Docker build jobs\n-> built-images.txt + build-version.txt artifacts] --> G[deploy.yml: download artifacts]

  E --> H[composite action: ecs-service-image-tags\n1) normalize .services\n2) select updated services\n3) resolve tags\n4) write back canonical JSON]
  G --> H

  H --> I[terraform plan/apply\nvar-files: terraform.tfvars.json + services.generated.json]
```

### Canonical `services.generated.json` contract (Terraform-friendly)

Terraform expects `services` to be a **JSON object map** (i.e., `map(object(...))`), not an array.

Canonical shape:

```json
{
  "services": {
    "test-app::test-app-api": {
      "container_image": "ghcr.io/orshalit/test-app-backend",
      "image_tag": "main-<sha>",
      "container_port": 8000,
      "cpu": 256,
      "memory": 512,
      "desired_count": 2,
      "application": "test-app",
      "environment_variables": {"LOG_LEVEL": "INFO"},
      "secrets": {},
      "service_discovery_name": null,
      "alb": {
        "alb_id": "app_shared",
        "listener_protocol": "HTTPS",
        "listener_port": 443,
        "path_patterns": ["/*"],
        "host_patterns": ["test-api.app.dev.light-solutions.org"],
        "priority": null,
        "health_check_path": "/health",
        "health_check_port": "traffic-port",
        "health_check_matcher": "200",
        "health_check_interval": 30,
        "health_check_timeout": 5,
        "health_check_healthy_thr": 2,
        "health_check_unhealthy_thr": 2
      }
    }
  }
}
```

**Invariants enforced by deploy tooling**:
- `services` **must be an object map** by the time Terraform runs.
- Every service must end up with a **non-empty** `image_tag`.

### Source of truth: Dhall → service keys

- **Service definitions** live under `dhall/applications/<app>/*.dhall` as `Service` records.
- `dhall/services.dhall` aggregates the list.
- `dhall/toTerraformJSON.dhall` generates the **Terraform service key**:
  - `mapKey = "${application}::${name}"`
  - This is the core **multi-application namespacing rule**.

### Normalization: why `.services` can arrive in different shapes

Depending on the generator and tooling, `.services` may be encoded in multiple ways.
The composite action normalizes it up-front and **writes back the canonical object map**.

Supported input encodings for `.services`:
- **object** (already canonical): `{ "svc": {..}, ... }`
- **array of Dhall Map entries**: `[{"mapKey":"svc","mapValue":{..}}, ...]`
- **array of jq entries**: `[{"key":"svc","value":{..}}, ...]`
- **array of tuple entries**: `[["svc", {..}], ...]`

During deploy you’ll see notices like:
- `::notice::.services type detected: array`
- `::notice::Normalized services keys count: <N>`

### How image tag resolution works

The action resolves **which services should receive the new tag** and **pins all other services** to the currently deployed tag.

- **Selection (updated service keys)**:
  - `workflow_run` (automatic deploy):
    - Reads `built-images.txt` from the CI workflow run.
    - Matches service updates by comparing **image basename**:
      - `basename(container_image)` must exist in `built-images.txt`.
    - Fails if `built-images.txt` is empty or if **zero services match** (prevents silent no-op / mismatched deploys).
  - `workflow_dispatch` (manual deploy):
    - If `update_images=false`: updates none (infra-only)
    - Else:
      - `application=all`: updates all services
      - `application=<name>`: updates only services with `.application == <name>`

- **Tag resolution**:
  - For **updated** services: `image_tag = desired_tag`.
  - For **non-updated** services: action queries AWS to discover the currently deployed tag:
    - `terraform output -raw ecs_cluster_name`
    - `terraform output -json service_names` (map: terraform service key → ECS service name)
    - `aws ecs describe-services` → active task definition
    - `aws ecs describe-task-definition` → container image → tag

- **Safety checks**:
  - If `updated_count > 0`, `desired_tag` must be non-empty.
  - After patching, any service with empty/null `image_tag` fails the run.

- **Optional registry verification**:
  - When enabled, the action verifies each updated image exists in GHCR using `docker manifest inspect`.

### Outputs produced by the action

- `updated_services_count`: number of services updated to `desired_tag`
- `updated_services_keys_file`: JSON array of updated service keys
- `updated_services_images_file`: JSON object map of updated services (subset of `services`)

### Operational checklist (what to verify for multi-app deployments)

- **Key uniqueness**: service keys follow `application::service` and never collide across applications.
- **CI ↔ deploy mapping**: `built-images.txt` entries match `basename(container_image)`.
- **Idempotency**:
  - Unchanged services are pinned to their currently deployed tag.
  - A deploy triggered by a backend-only change should not retag frontend services.
- **Terraform compatibility**: `services.generated.json` passed to Terraform contains `services` as an **object map**, never an array.
