# Applications Directory

This directory contains service definitions organized by application. Each application has its own namespace and can be deployed independently.

## Directory Structure

```
applications/
├── legacy/              # Legacy application (migrated from services/)
│   └── services/
│       ├── api.yaml
│       ├── api_single.yaml
│       └── frontend.yaml
└── {app-name}/          # New applications
    └── services/
        └── {service}.yaml
```

## Application Naming Rules

Application names must follow these rules (enforced by validation):
- **Lowercase only**: `app1`, `customer-portal`, `admin-dashboard`
- **Alphanumeric and hyphens only**: No underscores, spaces, or special characters
- **Examples**:
  - ✅ Valid: `app1`, `customer-portal`, `admin-dashboard`, `api-gateway`
  - ❌ Invalid: `App1` (uppercase), `customer_portal` (underscore), `customer portal` (space)

## Service Definition Schema

Each service YAML file must include:

```yaml
name: {service-name}
application: {application-name}  # REQUIRED - must match directory name

image_repo: ghcr.io/owner/repo
container_port: 8000
cpu: 256
memory: 512
desired_count: 2

# ... rest of configuration
```

### Required Fields

- `name`: Service name (unique within application)
- `application`: Application namespace (must match parent directory name)

The `application` field is **required** and must match the directory structure. For example:
- `applications/customer-portal/services/api.yaml` → `application: customer-portal`
- `applications/legacy/services/api.yaml` → `application: legacy`

## Migration from Old Structure

The old `services/` directory structure is still supported for backward compatibility, but all services must now include the `application` field:

```yaml
# services/api.yaml (old structure)
name: api
application: legacy  # REQUIRED
# ... rest of config
```

## Adding a New Application

1. Create application directory:
   ```bash
   mkdir -p applications/{app-name}/services
   ```

2. Create service definition:
   ```yaml
   # applications/{app-name}/services/api.yaml
   name: api
   application: {app-name}  # Must match directory name
   # ... rest of config
   ```

3. Generate Terraform config:
   ```bash
   python scripts/generate_ecs_services_tfvars.py \
     --base-dir . \
     --devops-dir ../DEVOPS \
     --environment dev
   ```

## Best Practices

1. **One application per directory**: Keep all services for an application in one directory
2. **Consistent naming**: Use consistent naming conventions across services
3. **Application isolation**: Each application should be independently deployable
4. **Shared services**: If services need to be shared across applications, consider creating a `shared` application

