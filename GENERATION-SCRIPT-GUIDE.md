# Generation Script Guide: `generate_ecs_services_tfvars.py`

## Use Case

The `generate_ecs_services_tfvars.py` script is the **bridge between CI and DEVOPS repositories**. It transforms simple YAML service definitions (developer-friendly) into Terraform-compatible `.tfvars` files that define ECS services.

### Problem It Solves

1. **Separation of Concerns**: 
   - **CI repo**: Developers define services in simple YAML (what they want)
   - **DEVOPS repo**: Terraform consumes generated `.tfvars` (infrastructure as code)

2. **Multi-Application Support**:
   - Supports both old structure (`services/*.yaml`) and new structure (`applications/{app}/services/*.yaml`)
   - Enforces application naming conventions
   - Allows filtering by application for targeted deployments

3. **Validation & Safety**:
   - Validates application names (lowercase, alphanumeric, hyphens only)
   - Ensures all services have required `application` field
   - Validates service definitions before generating Terraform config

## Usage

### Basic Usage (Generate All Services)

```bash
python scripts/generate_ecs_services_tfvars.py \
  --base-dir . \
  --devops-dir ../DEVOPS \
  --environment dev
```

**What it does:**
- Scans `services/` (old structure) and `applications/*/services/` (new structure)
- Loads all service YAML files
- Generates `DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars`
- Prints summary of generated services

### Filter by Application

```bash
python scripts/generate_ecs_services_tfvars.py \
  --base-dir . \
  --devops-dir ../DEVOPS \
  --environment dev \
  --application legacy
```

**What it does:**
- Only generates services for the specified application
- Useful for testing or deploying a single application
- Validates that the application exists

### Output Example

The script generates a Terraform variables file like this:

```hcl
services = {
  api = {
    container_image = "ghcr.io/orshalit/ci-backend"
    image_tag       = "latest"
    container_port  = 8000
    cpu             = 256
    memory          = 512
    desired_count   = 2
    application     = "legacy"  # ← Application field included
    
    environment_variables = {
      LOG_LEVEL = "INFO"
      DATABASE_URL = ""
    }
    
    alb = {
      alb_id            = "app_shared"
      listener_protocol = "HTTPS"
      listener_port     = 443
      path_patterns = ["/legacy-api/*"]
      host_patterns = ["app.dev.example.com"]
      health_check_path = "/health"
    }
  }
  
  # ... more services
}
```

## How It Works

### 1. **Service Discovery**

The script searches for service definitions in two locations:

**Old Structure (Backward Compatible):**
```
CI/services/
├── api.yaml          # application: legacy (default)
└── frontend.yaml     # application: legacy (default)
```

**New Structure (Multi-Application):**
```
CI/applications/
├── legacy/
│   └── services/
│       ├── api.yaml          # application: legacy (from directory)
│       └── frontend.yaml     # application: legacy (from directory)
└── test-app/
    └── services/
        ├── api.yaml          # application: test-app (from directory)
        └── frontend.yaml     # application: test-app (from directory)
```

### 2. **Application Name Validation**

The script enforces strict naming rules:
- ✅ Valid: `legacy`, `test-app`, `customer-portal`
- ❌ Invalid: `Legacy` (uppercase), `test_app` (underscore), `test app` (space)

### 3. **Service Processing**

For each service YAML file:
1. Loads and parses YAML
2. Validates required fields (`name`, `application`)
3. Validates application name format
4. Ensures `application` field matches directory name (for new structure)
5. Converts to Terraform HCL format

### 4. **Filtering (Optional)**

If `--application` is specified:
- Filters services to only include the specified application
- Validates that at least one service exists for that application
- Shows available applications if filter returns no results

### 5. **Output Generation**

Generates `services.generated.tfvars` in:
```
DEVOPS/live/{environment}/04-ecs-fargate/services.generated.tfvars
```

## Integration with CI/CD

### GitHub Actions Workflow

The script is typically called by the `create-ecs-service` workflow:

```yaml
- name: Generate services.generated.tfvars
  run: |
    python scripts/generate_ecs_services_tfvars.py \
      --base-dir . \
      --devops-dir ./DEVOPS \
      --environment ${{ inputs.environment }}
```

### When It Runs

1. **When creating a new service**: Developer creates YAML → PR → Workflow runs script → Generates tfvars
2. **When updating a service**: Developer modifies YAML → PR → Workflow runs script → Updates tfvars
3. **Before deployment**: Ensures tfvars is up-to-date with latest service definitions

## Current Service Structure

After migration to multi-application structure:

### Legacy Application
- **Location**: `applications/legacy/services/`
- **Services**: `api`, `frontend`
- **Path Patterns**: 
  - API: `/legacy-api/*`
  - Frontend: `/legacy/*`

### Test Application
- **Location**: `applications/test-app/services/`
- **Services**: `api`, `frontend`
- **Path Patterns**:
  - API: `/test-api/*`
  - Frontend: `/test/*`

## Command-Line Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `--base-dir` | No* | Path to CI repository root (default: current directory) |
| `--devops-dir` | Yes | Path to DEVOPS repository root |
| `--environment` | Yes | Target environment (dev, staging, production) |
| `--module-path` | No | Terraform module path (default: `04-ecs-fargate`) |
| `--application` | No | Filter by application name (omit for all) |
| `--services-dir` | No | [DEPRECATED] Legacy option for backward compatibility |

*`--base-dir` is required unless using deprecated `--services-dir`

## Error Handling

The script will exit with an error if:
- No service specs found
- Service missing required `name` field
- Service missing required `application` field
- Application name violates naming rules
- Application name in YAML doesn't match directory name (new structure)
- Filtered application has no services
- Invalid YAML syntax
- **ALB routing conflicts**: Duplicate path patterns or host+path combinations on the same ALB

## Best Practices

1. **Always commit service YAML files** before running the script
2. **Use descriptive application names**: `customer-portal`, not `cp` or `app1`
3. **Keep path patterns unique** per application to avoid ALB routing conflicts
4. **Test locally** before creating PR:
   ```bash
   python scripts/generate_ecs_services_tfvars.py \
     --base-dir . \
     --devops-dir ../DEVOPS \
     --environment dev \
     --application test-app
   ```
5. **Review generated tfvars** in PR to ensure correct translation

## ALB Routing Conflict Validation

The script automatically validates that services using the same ALB don't have duplicate routing rules. This prevents conflicts where multiple services would compete for the same ALB listener rule.

### How It Works

1. **Groups services by ALB ID**: Services are grouped by their `alb.alb_id` value
2. **Checks routing rule uniqueness**: For each ALB, validates that:
   - If no host patterns: Path patterns must be unique
   - If host patterns specified: Each host+path combination must be unique

### Examples

**✅ Valid Configuration:**
```yaml
# Service 1
alb:
  alb_id: app_shared
  path_patterns: ["/api/*"]

# Service 2
alb:
  alb_id: app_shared
  path_patterns: ["/frontend/*"]  # Different path - OK
```

**✅ Valid with Host Patterns:**
```yaml
# Service 1
alb:
  alb_id: app_shared
  host_patterns: ["api.example.com"]
  path_patterns: ["/v1/*"]

# Service 2
alb:
  alb_id: app_shared
  host_patterns: ["api.example.com"]
  path_patterns: ["/v2/*"]  # Same host, different path - OK
```

**❌ Invalid Configuration:**
```yaml
# Service 1
alb:
  alb_id: app_shared
  path_patterns: ["/api/*"]

# Service 2
alb:
  alb_id: app_shared
  path_patterns: ["/api/*"]  # Same path on same ALB - CONFLICT!
```

**Error Message:**
```
ALB routing conflicts detected for ALB 'app_shared':
  Path pattern '/api/*' is used by multiple services on ALB 'app_shared':
    - legacy::api, test-app::api

Each service on the same ALB must have unique routing rules (host + path combinations).
Please update the service definitions to use different path patterns or host patterns.
```

## Troubleshooting

### "No service specs found"
- Check that `services/` or `applications/*/services/` directories exist
- Verify YAML files have `.yaml` or `.yml` extension

### "Application name validation failed"
- Ensure application name is lowercase
- Use hyphens, not underscores or spaces
- Check for leading/trailing hyphens or consecutive hyphens

### "Application name doesn't match directory"
- For new structure, `application` field in YAML must match directory name
- Example: `applications/test-app/services/api.yaml` must have `application: test-app`

### "ALB routing conflicts detected"
- Check that services on the same ALB have unique path patterns
- If using host patterns, ensure each host+path combination is unique
- Consider using different ALBs for services that need the same path patterns
- Example fix: Change one service's path from `/api/*` to `/legacy-api/*` or `/v2-api/*`

