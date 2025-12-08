#!/usr/bin/env python
"""
Generate Terraform 'services' blocks for the ECS Fargate layer in DEVOPS
from simple YAML specs in the CI repo.

This script supports both old and new directory structures:
- Old: CI/services/*.yaml (defaults to application="legacy")
- New: CI/applications/{app}/services/*.yaml (uses app name from directory)

It intentionally focuses on attaching services to existing ALBs. ALB
definitions and Route 53 records remain managed manually in DEVOPS.
"""

import argparse
import pathlib
import re
import textwrap

import yaml


def validate_application_name(app_name: str, file_path: str) -> None:
    """
    Validate application name according to naming rules.
    
    Rules (enforced):
    - Lowercase only
    - Alphanumeric and hyphens only (no underscores, spaces, or special characters)
    
    Examples:
    - Valid: app1, customer-portal, admin-dashboard
    - Invalid: App1 (uppercase), customer_portal (underscore), customer portal (space)
    """
    if not app_name:
        raise ValueError(f"Application name cannot be empty (in {file_path})")
    
    # Check for lowercase only
    if app_name != app_name.lower():
        raise ValueError(
            f"Application name '{app_name}' must be lowercase only (in {file_path}). "
            f"Found uppercase characters."
        )
    
    # Check for valid characters: lowercase letters, numbers, and hyphens only
    if not re.match(r'^[a-z0-9-]+$', app_name):
        invalid_chars = set(re.findall(r'[^a-z0-9-]', app_name))
        raise ValueError(
            f"Application name '{app_name}' contains invalid characters: {invalid_chars} (in {file_path}). "
            f"Only lowercase letters, numbers, and hyphens are allowed."
        )
    
    # Check for leading/trailing hyphens
    if app_name.startswith('-') or app_name.endswith('-'):
        raise ValueError(
            f"Application name '{app_name}' cannot start or end with a hyphen (in {file_path})"
        )
    
    # Check for consecutive hyphens
    if '--' in app_name:
        raise ValueError(
            f"Application name '{app_name}' cannot contain consecutive hyphens (in {file_path})"
        )


def load_yaml_file(path: pathlib.Path) -> dict:
    """Load and parse a YAML file."""
    with path.open("r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    return data


def validate_alb_routing_conflicts(specs: list[dict]) -> None:
    """
    Validate that services using the same ALB don't have duplicate routing rules.
    
    ALB listener rules are matched by host pattern (if specified) and path pattern.
    If two services on the same ALB have the same host+path combination, they will
    conflict and cause unpredictable routing behavior.
    
    This validation checks:
    1. Duplicate path patterns on the same ALB (when no host patterns specified)
    2. Duplicate host+path combinations on the same ALB (when host patterns specified)
    
    Args:
        specs: List of service spec dictionaries
        
    Raises:
        ValueError: If duplicate routing rules are found for the same ALB
    """
    # Group services by ALB ID
    alb_services: dict[str, list[dict]] = {}
    
    for spec in specs:
        alb_config = spec.get("alb")
        if not alb_config:
            # Service without ALB - skip validation
            continue
        
        alb_id = alb_config.get("alb_id")
        if not alb_id:
            continue
        
        if alb_id not in alb_services:
            alb_services[alb_id] = []
        alb_services[alb_id].append(spec)
    
    # Check for conflicts within each ALB group
    for alb_id, services in alb_services.items():
        if len(services) < 2:
            # Only one service using this ALB - no conflicts possible
            continue
        
        # Track routing rule combinations (host + path)
        # Key: (host_pattern or None, normalized_path_pattern)
        # Value: list of services using this combination
        routing_rules: dict[tuple[str | None, str], list[dict]] = {}
        
        for service in services:
            service_name = service.get("name", "unknown")
            application = service.get("application", "unknown")
            alb_config = service.get("alb", {})
            
            path_patterns = alb_config.get("path_patterns") or []
            host_patterns = alb_config.get("host_patterns") or []
            
            # If no path patterns specified, skip (service won't have ALB routing)
            if not path_patterns:
                continue
            
            # Normalize host patterns (lowercase, strip)
            normalized_hosts = [h.lower().strip() if h else None for h in host_patterns] if host_patterns else [None]
            
            # Create routing rule combinations
            for path_pattern in path_patterns:
                # Normalize path pattern (handle trailing slashes for comparison)
                # Note: We keep the original for display, but normalize for comparison
                normalized_path = path_pattern.rstrip("/") or "/"
                
                # If host patterns are specified, each host+path combo must be unique
                # If no host patterns, just path must be unique
                for host_pattern in normalized_hosts:
                    rule_key = (host_pattern, normalized_path)
                    
                    if rule_key not in routing_rules:
                        routing_rules[rule_key] = []
                    
                    routing_rules[rule_key].append({
                        "name": service_name,
                        "application": application,
                        "path": path_pattern,
                        "host": host_pattern
                    })
        
        # Report conflicts
        conflicts = []
        for (host_pattern, path_pattern), conflicting_services in routing_rules.items():
            if len(conflicting_services) > 1:
                service_list = ", ".join(
                    f"{s['application']}::{s['name']}" 
                    for s in conflicting_services
                )
                
                if host_pattern:
                    conflicts.append(
                        f"  Host pattern '{host_pattern}' with path pattern '{path_pattern}' "
                        f"is used by multiple services on ALB '{alb_id}':\n"
                        f"    - {service_list}"
                    )
                else:
                    conflicts.append(
                        f"  Path pattern '{path_pattern}' is used by multiple services on ALB '{alb_id}':\n"
                        f"    - {service_list}"
                    )
        
        if conflicts:
            conflict_msg = "\n".join(conflicts)
            raise ValueError(
                f"ALB routing conflicts detected for ALB '{alb_id}':\n"
                f"{conflict_msg}\n\n"
                f"Each service on the same ALB must have unique routing rules (host + path combinations).\n"
                f"Please update the service definitions to use different path patterns or host patterns."
            )


def load_service_specs(base_dir: pathlib.Path) -> list[dict]:
    """
    Load service specs from both old and new directory structures.
    
    Supports:
    - Old: services/*.yaml (defaults to application="legacy" if not specified)
    - New: applications/{app}/services/*.yaml (uses app name from directory)
    
    Args:
        base_dir: Path to CI repository root
        
    Returns:
        List of service spec dictionaries, each with an 'application' field
    """
    specs: list[dict] = []
    
    # Load from old structure (services/)
    services_dir = base_dir / "services"
    if services_dir.exists():
        for path in sorted(services_dir.glob("*.y*ml")):
            spec = load_yaml_file(path)
            if not spec.get("name"):
                raise ValueError(f"Service spec {path} is missing required 'name'")
            
            # Get application from spec or default to "legacy"
            app_name = spec.get("application", "legacy")
            
            # Validate application name
            validate_application_name(app_name, str(path))
            
            spec["application"] = app_name
            spec["_file"] = str(path)
            specs.append(spec)
    
    # Load from new structure (applications/{app}/services/)
    applications_dir = base_dir / "applications"
    if applications_dir.exists():
        for app_dir in sorted(applications_dir.iterdir()):
            if not app_dir.is_dir():
                continue
            
            app_name = app_dir.name
            
            # Validate directory name (application name)
            validate_application_name(app_name, str(app_dir))
            
            services_dir = app_dir / "services"
            if services_dir.exists():
                for path in sorted(services_dir.glob("*.y*ml")):
                    spec = load_yaml_file(path)
                    if not spec.get("name"):
                        raise ValueError(f"Service spec {path} is missing required 'name'")
                    
                    # Get application from spec or use directory name
                    spec_app_name = spec.get("application", app_name)
                    
                    # Validate application name
                    validate_application_name(spec_app_name, str(path))
                    
                    # Ensure application matches directory name (enforce consistency)
                    if spec_app_name != app_name:
                        raise ValueError(
                            f"Service spec {path} has application='{spec_app_name}' but is in "
                            f"directory 'applications/{app_name}/'. Application name must match directory name."
                        )
                    
                    spec["application"] = app_name
                    spec["_file"] = str(path)
                    specs.append(spec)
    
    return specs


def hcl_string(value: str) -> str:
    """Escape a string for HCL output."""
    return '"' + value.replace('"', '\\"') + '"'


def render_services_map(specs: list[dict]) -> str:
    """
    Render the Terraform 'services' map expected by the ecs-fargate module.
    
    Args:
        specs: List of service specs, each with an 'application' field
    """
    lines: list[str] = []
    lines.append("# Generated by CI from CI/services/*.yaml or CI/applications/*/services/*.yaml")
    lines.append("# DO NOT EDIT MANUALLY; changes will be overwritten.")
    lines.append("#")
    lines.append("# To add or modify services:")
    lines.append("# 1. Edit CI/services/*.yaml (old structure) or CI/applications/{app}/services/*.yaml (new structure)")
    lines.append("# 2. Run the 'Create / Update ECS Service' workflow in the CI repository")
    lines.append("#")
    lines.append("# Services can attach to any ALB defined in terraform.tfvars by")
    lines.append("# referencing the ALB's key in the 'alb_id' field.")
    lines.append("#")
    lines.append("# Each service includes an 'application' field for multi-application support.")
    lines.append("")
    lines.append("services = {")

    for spec in specs:
        name = spec["name"]
        application = spec.get("application", "legacy")  # Should always be present after load_service_specs
        
        # Validate that application field is present (required)
        if not application:
            raise ValueError(f"Service '{name}' is missing required 'application' field")
        
        image_repo = spec.get("image_repo")
        if not image_repo:
            raise ValueError(f"Service '{name}' is missing required 'image_repo'")

        container_port = int(spec.get("container_port", 80))
        cpu = int(spec.get("cpu", 256))
        memory = int(spec.get("memory", 512))
        desired_count = int(spec.get("desired_count", 1))

        env = spec.get("env", {}) or {}
        alb = spec.get("alb", {}) or {}
        autoscaling = spec.get("autoscaling") or None
        deployment = spec.get("deployment") or None

        lines.append(f"  {name} = {{")
        lines.append(f"    container_image = {hcl_string(image_repo)}")
        # The actual tag normally comes from service_image_tags at deploy time.
        lines.append(f"    image_tag       = \"latest\"")
        lines.append(f"    container_port  = {container_port}")
        lines.append(f"    cpu             = {cpu}")
        lines.append(f"    memory          = {memory}")
        lines.append(f"    desired_count   = {desired_count}")
        # Store application for future use in Terraform (Phase 2)
        lines.append(f"    application     = {hcl_string(application)}")
        lines.append("")

        # Environment variables
        if env:
            lines.append("    environment_variables = {")
            for k, v in env.items():
                lines.append(f"      {k} = {hcl_string(str(v))}")
            lines.append("    }")
            lines.append("")

        # Optional ALB attachment
        if alb:
            required_alb_fields = ["alb_id", "listener_protocol", "listener_port"]
            missing = [f for f in required_alb_fields if f not in alb]
            if missing:
                raise ValueError(
                    f"Service '{name}' alb block missing required fields: {', '.join(missing)}"
                )

            lines.append("    alb = {")
            lines.append(f"      alb_id            = {hcl_string(alb['alb_id'])}")
            lines.append(
                f"      listener_protocol = {hcl_string(str(alb['listener_protocol']))}"
            )
            lines.append(f"      listener_port     = {int(alb['listener_port'])}")

            path_patterns = alb.get("path_patterns") or []
            host_patterns = alb.get("host_patterns") or []

            if path_patterns:
                rendered = ", ".join(hcl_string(p) for p in path_patterns)
                lines.append(f"      path_patterns = [{rendered}]")
            if host_patterns:
                rendered = ", ".join(hcl_string(h) for h in host_patterns)
                lines.append(f"      host_patterns = [{rendered}]")

            # Optional health check overrides
            health_check_fields = [
                "health_check_path",
                "health_check_matcher",
                "health_check_interval",
                "health_check_timeout",
                "health_check_healthy_thr",
                "health_check_unhealthy_thr",
            ]
            for field in health_check_fields:
                if field in alb:
                    value = alb[field]
                    if isinstance(value, str):
                        lines.append(f"      {field} = {hcl_string(value)}")
                    else:
                        lines.append(f"      {field} = {value}")

            lines.append("    }")
            lines.append("")

        # Optional autoscaling configuration
        if autoscaling:
            min_cap = autoscaling.get("min_capacity")
            max_cap = autoscaling.get("max_capacity")
            if min_cap is None or max_cap is None:
                raise ValueError(
                    f"Service '{name}' autoscaling block must include min_capacity and max_capacity"
                )

            lines.append("    autoscaling = {")
            lines.append(f"      min_capacity  = {int(min_cap)}")
            lines.append(f"      max_capacity  = {int(max_cap)}")
            if "cpu_target" in autoscaling:
                lines.append(f"      cpu_target    = {int(autoscaling['cpu_target'])}")
            if "memory_target" in autoscaling:
                lines.append(
                    f"      memory_target = {int(autoscaling['memory_target'])}"
                )
            lines.append("    }")
            lines.append("")

        # Optional deployment configuration
        if deployment:
            lines.append("    deployment = {")
            if "minimum_healthy_percent" in deployment:
                lines.append(f"      minimum_healthy_percent = {int(deployment['minimum_healthy_percent'])}")
            if "maximum_percent" in deployment:
                lines.append(f"      maximum_percent = {int(deployment['maximum_percent'])}")
            lines.append("    }")
            lines.append("")

        lines.append("  }")
        lines.append("")

    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate ECS services.generated.tfvars for DEVOPS from CI service specs",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""
            Examples:
              # Generate from CI repository root (supports both old and new structures)
              python generate_ecs_services_tfvars.py \\
                --base-dir . \\
                --devops-dir ../DEVOPS \\
                --environment dev
              
              # Filter by application
              python generate_ecs_services_tfvars.py \\
                --base-dir . \\
                --devops-dir ../DEVOPS \\
                --environment dev \\
                --application legacy
              
              # Legacy: Use old services-dir argument (backward compatibility)
              python generate_ecs_services_tfvars.py \\
                --services-dir services \\
                --devops-dir ../DEVOPS \\
                --environment dev
        """)
    )
    
    # New primary argument: base directory
    parser.add_argument(
        "--base-dir",
        type=pathlib.Path,
        help="Path to CI repository root (default: current directory). "
             "Script will look for services/ and applications/ directories.",
    )
    
    # Legacy argument: services directory (for backward compatibility)
    parser.add_argument(
        "--services-dir",
        type=pathlib.Path,
        help="[DEPRECATED] Path to CI services spec directory (e.g. ./services). "
             "Use --base-dir instead. This option is kept for backward compatibility.",
    )
    
    parser.add_argument(
        "--devops-dir",
        type=pathlib.Path,
        required=True,
        help="Path to DEVOPS repo root (as checked out in CI, e.g. ./DEVOPS)",
    )
    parser.add_argument(
        "--environment",
        type=str,
        required=True,
        help="Target environment (e.g. dev, staging, production)",
    )
    parser.add_argument(
        "--module-path",
        type=str,
        default="04-ecs-fargate",
        help="Terraform module path under live/<env> (default: 04-ecs-fargate)",
    )
    parser.add_argument(
        "--application",
        type=str,
        help="Filter services by application name (omit to include all applications)",
    )

    args = parser.parse_args()

    # Determine base directory
    if args.services_dir:
        # Legacy mode: use services-dir (backward compatibility)
        import warnings
        warnings.warn(
            "--services-dir is deprecated. Use --base-dir instead.",
            DeprecationWarning,
            stacklevel=2
        )
        base_dir = args.services_dir.parent
        # Load only from services directory
        specs = []
        for path in sorted(args.services_dir.glob("*.y*ml")):
            spec = load_yaml_file(path)
            if not spec.get("name"):
                raise ValueError(f"Service spec {path} is missing required 'name'")
            app_name = spec.get("application", "legacy")
            validate_application_name(app_name, str(path))
            spec["application"] = app_name
            spec["_file"] = str(path)
            specs.append(spec)
    else:
        # New mode: use base-dir
        base_dir = args.base_dir or pathlib.Path(".")
        if not base_dir.exists():
            raise SystemExit(f"Base directory does not exist: {base_dir}")
        specs = load_service_specs(base_dir)
    
    if not specs:
        raise SystemExit(
            f"No service specs found. "
            "At least one *.yaml spec is required in services/ or applications/*/services/."
        )
    
    # Filter by application if specified
    if args.application:
        validate_application_name(args.application, "command-line")
        specs = [s for s in specs if s.get("application") == args.application]
        if not specs:
            raise SystemExit(
                f"No services found for application '{args.application}'. "
                f"Available applications: {', '.join(sorted(set(s.get('application', 'legacy') for s in specs)))}"
            )
    
    # Validate all services have application field
    for spec in specs:
        if not spec.get("application"):
            raise ValueError(
                f"Service '{spec.get('name', 'unknown')}' is missing required 'application' field. "
                f"This is required for multi-application support."
            )
    
    # Validate ALB routing conflicts (duplicate path/host patterns)
    try:
        validate_alb_routing_conflicts(specs)
    except ValueError as e:
        raise SystemExit(str(e))
    
    # Group by application for summary
    apps = {}
    for spec in specs:
        app = spec.get("application", "legacy")
        if app not in apps:
            apps[app] = []
        apps[app].append(spec["name"])
    
    content = render_services_map(specs)

    target_dir = (
        args.devops_dir / "live" / args.environment / args.module_path
    )
    target_dir.mkdir(parents=True, exist_ok=True)
    target_file = target_dir / "services.generated.tfvars"

    target_file.write_text(content, encoding="utf-8")

    # Print summary
    total_services = len(specs)
    app_summary = ", ".join(f"{app} ({len(services)} service(s))" for app, services in sorted(apps.items()))
    
    print(
        textwrap.dedent(
            f"""
            ✓ Wrote services map for environment '{args.environment}' to:
              {target_file}
            
            Generated {total_services} service(s) across {len(apps)} application(s):
              {app_summary}
            """
        ).strip()
    )


if __name__ == "__main__":
    main()
