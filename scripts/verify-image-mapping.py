#!/usr/bin/env python
"""
Verify that each service is mapped to the correct Docker image.

This script checks:
1. Service definitions have image_repo specified
2. Generated tfvars correctly map image_repo → container_image
3. Each application's services use the correct image repositories
4. Image repositories match expected patterns (shared vs app-specific)
"""

import argparse
import json
import pathlib
import re
import sys
from typing import Dict, List, Tuple

import yaml


def load_service_specs(base_dir: pathlib.Path) -> List[Dict]:
    """Load all service specs from applications directory."""
    specs = []
    applications_dir = base_dir / "applications"
    
    if not applications_dir.exists():
        return specs
    
    for app_dir in sorted(applications_dir.iterdir()):
        if not app_dir.is_dir():
            continue
        
        app_name = app_dir.name
        services_dir = app_dir / "services"
        
        if services_dir.exists():
            for path in sorted(services_dir.glob("*.y*ml")):
                with path.open("r", encoding="utf-8") as f:
                    spec = yaml.safe_load(f) or {}
                
                spec["_app"] = app_name
                spec["_file"] = str(path)
                specs.append(spec)
    
    return specs


def load_generated_tfvars(tfvars_path: pathlib.Path) -> Dict[str, Dict]:
    """Parse services.generated.tfvars to extract service configurations."""
    services = {}
    
    if not tfvars_path.exists():
        return services
    
    current_service = None
    in_service_block = False
    brace_count = 0
    
    with tfvars_path.open("r", encoding="utf-8") as f:
        for line in f:
            # Match service name: "service_name = {"
            service_match = re.match(r'^\s+(\w+)\s*=\s*\{', line)
            if service_match:
                current_service = service_match.group(1)
                in_service_block = True
                brace_count = 1
                services[current_service] = {
                    "container_image": None,
                    "image_tag": None,
                    "application": None,
                }
                continue
            
            if in_service_block and current_service:
                brace_count += line.count('{') - line.count('}')
                
                # Extract container_image
                img_match = re.search(r'container_image\s*=\s*"([^"]+)"', line)
                if img_match:
                    services[current_service]["container_image"] = img_match.group(1)
                
                # Extract image_tag
                tag_match = re.search(r'image_tag\s*=\s*"([^"]+)"', line)
                if tag_match:
                    services[current_service]["image_tag"] = tag_match.group(1)
                
                # Extract application
                app_match = re.search(r'application\s*=\s*"([^"]+)"', line)
                if app_match:
                    services[current_service]["application"] = app_match.group(1)
                
                # End of service block
                if brace_count == 0:
                    in_service_block = False
                    current_service = None
    
    return services


def verify_image_mapping(
    base_dir: pathlib.Path,
    tfvars_path: pathlib.Path
) -> Tuple[bool, List[str]]:
    """
    Verify that service definitions correctly map to images.
    
    Returns:
        (is_valid, list_of_issues)
    """
    issues = []
    specs = load_service_specs(base_dir)
    tfvars_services = load_generated_tfvars(tfvars_path)
    
    # Check 1: All service specs have image_repo
    for spec in specs:
        name = spec.get("name")
        app = spec.get("_app")
        image_repo = spec.get("image_repo")
        
        if not image_repo:
            issues.append(
                f"❌ Service '{name}' (app: {app}) missing 'image_repo' field"
            )
            continue
        
        # Check 2: image_repo matches expected pattern
        expected_shared_backend = f"ghcr.io/orshalit/ci-backend"
        expected_shared_frontend = f"ghcr.io/orshalit/ci-frontend"
        expected_app_backend = f"ghcr.io/orshalit/{app}-backend"
        expected_app_frontend = f"ghcr.io/orshalit/{app}-frontend"
        
        service_type = "backend"
        if "frontend" in name.lower():
            service_type = "frontend"
        
        # Check if app has app-specific code
        app_backend_dir = base_dir / "applications" / app / "backend"
        app_frontend_dir = base_dir / "applications" / app / "frontend"
        
        has_app_backend = app_backend_dir.exists() and app_backend_dir.is_dir()
        has_app_frontend = app_frontend_dir.exists() and app_frontend_dir.is_dir()
        
        # Validate image_repo choice
        if service_type == "backend":
            if has_app_backend and image_repo != expected_app_backend:
                issues.append(
                    f"⚠️  Service '{name}' (app: {app}) has app-specific backend code "
                    f"but uses '{image_repo}' instead of '{expected_app_backend}'"
                )
            elif not has_app_backend and image_repo != expected_shared_backend:
                issues.append(
                    f"⚠️  Service '{name}' (app: {app}) uses '{image_repo}' but no app-specific backend. "
                    f"Consider using '{expected_shared_backend}'"
                )
        else:  # frontend
            if has_app_frontend and image_repo != expected_app_frontend:
                issues.append(
                    f"⚠️  Service '{name}' (app: {app}) has app-specific frontend code "
                    f"but uses '{image_repo}' instead of '{expected_app_frontend}'"
                )
            elif not has_app_frontend and image_repo != expected_shared_frontend:
                issues.append(
                    f"⚠️  Service '{name}' (app: {app}) uses '{image_repo}' but no app-specific frontend. "
                    f"Consider using '{expected_shared_frontend}'"
                )
        
        # Check 3: tfvars matches service spec
        if name in tfvars_services:
            tfvars_img = tfvars_services[name]["container_image"]
            if tfvars_img != image_repo:
                issues.append(
                    f"❌ Service '{name}': YAML has '{image_repo}' but tfvars has '{tfvars_img}'"
                )
        else:
            issues.append(
                f"⚠️  Service '{name}' found in YAML but not in generated tfvars"
            )
    
    # Check 4: All services in tfvars have valid image references
    for service_name, config in tfvars_services.items():
        if not config["container_image"]:
            issues.append(
                f"❌ Service '{service_name}' in tfvars missing 'container_image'"
            )
        elif "/" not in config["container_image"]:
            issues.append(
                f"❌ Service '{service_name}' has invalid container_image format: '{config['container_image']}'"
            )
    
    # Summary
    is_valid = len([i for i in issues if i.startswith("❌")]) == 0
    
    return is_valid, issues


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Verify image mapping for all services"
    )
    parser.add_argument(
        "--base-dir",
        type=pathlib.Path,
        default=pathlib.Path("."),
        help="Path to CI repository root"
    )
    parser.add_argument(
        "--tfvars",
        type=pathlib.Path,
        help="Path to services.generated.tfvars (default: DEVOPS/live/dev/04-ecs-fargate/services.generated.tfvars)"
    )
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format"
    )
    
    args = parser.parse_args()
    
    if args.tfvars:
        tfvars_path = args.tfvars
    else:
        # Try to find it in DEVOPS repo
        tfvars_path = args.base_dir.parent / "DEVOPS" / "live" / "dev" / "04-ecs-fargate" / "services.generated.tfvars"
    
    is_valid, issues = verify_image_mapping(args.base_dir, tfvars_path)
    
    if args.format == "json":
        output = {
            "valid": is_valid,
            "issues": issues,
            "issue_count": len(issues),
            "error_count": len([i for i in issues if i.startswith("❌")]),
            "warning_count": len([i for i in issues if i.startswith("⚠️")])
        }
        print(json.dumps(output, indent=2))
    else:
        if issues:
            print("Image Mapping Verification Results:\n")
            for issue in issues:
                print(f"  {issue}")
            print()
        
        if is_valid:
            print("✅ All image mappings are valid!")
            sys.exit(0)
        else:
            print("❌ Some image mapping issues found. Please fix the errors above.")
            sys.exit(1)


if __name__ == "__main__":
    main()

