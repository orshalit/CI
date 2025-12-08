# Composite Actions

This directory contains reusable composite actions for the deployment pipeline. These actions encapsulate complex deployment logic and make the main workflow more maintainable.

## Available Actions

### 1. `install-docker-ec2`

Installs Docker and Docker Compose on an EC2 instance via AWS SSM if not already present.

**Inputs:**
- `instance-id` (required): EC2 instance ID
- `region` (required): AWS region
- `timeout` (optional): Timeout in seconds (default: 300)

**Outputs:**
- `command-id`: SSM command ID for the installation
- `already-installed`: Whether Docker was already installed (true/false)

**Usage:**
```yaml
- name: Install Docker
  uses: ./.github/actions/install-docker-ec2
  with:
    instance-id: ${{ steps.find-instance.outputs.instance_id }}
    region: us-east-1
    timeout: '300'
```

**What it does:**
- Detects OS type (Ubuntu/Debian/Amazon Linux/RHEL/CentOS)
- Checks if Docker and Docker Compose are already installed
- Installs Docker using official repositories if needed
- Installs Docker Compose (plugin or standalone) if needed
- Adds user to docker group
- Verifies installation
- Waits for installation to complete

---

### 2. `copy-files-ssm`

Copies files from the GitHub Actions runner to an EC2 instance using AWS SSM with base64 encoding.

**Inputs:**
- `instance-id` (required): EC2 instance ID
- `region` (required): AWS region
- `source-files` (required): Space-separated list of source files to copy
- `destination-dir` (required): Destination directory on EC2 instance
- `timeout` (optional): Timeout in seconds (default: 60)

**Outputs:**
- `command-id`: SSM command ID for the file copy operation

**Usage:**
```yaml
- name: Copy files
  uses: ./.github/actions/copy-files-ssm
  with:
    instance-id: ${{ steps.find-instance.outputs.instance_id }}
    region: us-east-1
    source-files: 'scripts/deploy.sh docker-compose.prod.yml'
    destination-dir: '/opt/ci-app'
```

**What it does:**
- Verifies source files exist in the repository
- Base64-encodes files to avoid escaping issues
- Creates destination directory on EC2 if needed
- Transfers files via SSM SendCommand
- Sets appropriate permissions (.sh files get 755, others get 644)
- Verifies files were copied correctly
- Waits for copy operation to complete

---

### 3. `deploy-via-ssm`

Deploys the application on an EC2 instance by executing a deployment script via AWS SSM.

**Inputs:**
- `instance-id` (required): EC2 instance ID
- `region` (required): AWS region
- `deploy-script-path` (required): Path to deployment script on EC2 instance
- `deploy-version` (required): Version/tag to deploy
- `deploy-commit` (required): Git commit SHA
- `github-owner` (required): GitHub organization/user
- `github-repo` (required): GitHub repository name
- `github-token` (required): GitHub token for GHCR authentication
- `timeout` (optional): Timeout in seconds (default: 600)

**Outputs:**
- `command-id`: SSM command ID for the deployment
- `status`: Final deployment status (success/failed/timeout)

**Usage:**
```yaml
- name: Deploy
  uses: ./.github/actions/deploy-via-ssm
  with:
    instance-id: ${{ steps.find-instance.outputs.instance_id }}
    region: us-east-1
    deploy-script-path: '/opt/ci-app/deploy.sh'
    deploy-version: 'v1.0.0'
    deploy-commit: 'abc123'
    github-owner: 'my-org'
    github-repo: 'my-repo'
    github-token: ${{ secrets.GITHUB_TOKEN }}
    timeout: '600'
```

**What it does:**
- Executes the deployment script on EC2 via SSM
- Passes environment variables (version, commit, GitHub credentials)
- Uses `sg docker` for proper Docker group permissions
- Monitors deployment progress with status updates
- Retrieves and displays deployment logs
- Returns deployment status for conditional steps
- Waits for deployment to complete

---

## Architecture Benefits

### Before Refactoring
- **deploy.yml**: 759 lines (huge, hard to maintain)
- Large inline bash scripts in YAML
- Difficult to test and debug
- Hard to reuse logic
- Complex escaping for nested commands

### After Refactoring
- **deploy.yml**: ~280 lines (62% reduction)
- **Composite actions**: 3 reusable modules
- Clear separation of concerns
- Easier to test each component
- Simpler workflow orchestration
- Better error handling and logging

## Design Decisions

### Why Composite Actions vs. Separate Scripts?

**Composite actions were chosen because:**
1. **Self-contained**: Each action includes all logic (orchestration + execution)
2. **Reusable**: Can be used in multiple workflows
3. **GitHub Actions native**: Proper inputs/outputs, error handling
4. **AWS-specific**: Tightly coupled with SSM, no need for portability
5. **Good enough**: Balance between simplicity and maintainability

**Scripts NOT extracted from actions because:**
1. Current structure is maintainable at this scale
2. Actions are already well-documented
3. EC2-side scripts (deploy.sh) are separate files
4. Future extraction is easy if needed

### Future Improvements (Phase 2)

When needed, consider:
1. Extract Docker installation script for local testing
2. Add unit tests for EC2-side scripts
3. Create shared SSM polling utility
4. Add retry logic for transient failures
5. Implement blue-green deployment strategy

## Usage in Main Workflow

The main `deploy.yml` workflow now follows this pattern:

```yaml
jobs:
  deploy:
    steps:
      - name: Setup and Authentication
        # ... (AWS OIDC, instance discovery)

      - name: Install Docker
        uses: ./.github/actions/install-docker-ec2
        with: { instance-id, region }

      - name: Copy Files
        uses: ./.github/actions/copy-files-ssm
        with: { instance-id, region, source-files, destination-dir }

      - name: Deploy
        uses: ./.github/actions/deploy-via-ssm
        with: { instance-id, region, deploy-script-path, ... }

      - name: Verify and Report
        # ... (health checks, summary)
```

## Best Practices

1. **Inputs**: Always validate inputs and fail fast
2. **Outputs**: Provide actionable outputs for conditional steps
3. **Logging**: Use GitHub Actions annotations (::notice::, ::error::)
4. **Error Handling**: Return meaningful error messages
5. **Timeouts**: Make timeouts configurable with sensible defaults
6. **Idempotency**: Actions should be safe to run multiple times
7. **Documentation**: Keep this README updated as actions evolve

## Troubleshooting

### Action Fails with "File not found"
- Check that source files exist in the repository
- Verify paths are relative to repository root
- Ensure checkout action runs before using actions

### SSM Command Timeout
- Increase timeout value in action inputs
- Check EC2 instance has sufficient resources
- Verify SSM agent is running on EC2

### Docker Installation Fails
- Check EC2 instance OS is supported
- Verify instance has internet access
- Review SSM command logs in AWS Console

### Deployment Fails
- Check GITHUB_TOKEN has packages:read permission
- Verify Docker images exist in GHCR
- Review deployment script logs on EC2

## Contributing

When adding or modifying actions:
1. Update action.yml with clear inputs/outputs
2. Add usage example to this README
3. Test with manual workflow_dispatch
4. Document any breaking changes

