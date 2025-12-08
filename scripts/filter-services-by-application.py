#!/usr/bin/env python
"""
Filter services from services.generated.tfvars by application.

This script reads a Terraform tfvars file and extracts service names
that belong to a specific application (or all applications if "all" is specified).
"""

import argparse
import json
import re
import sys
from pathlib import Path


def extract_services_by_application(tfvars_path: Path, target_application: str) -> list[str]:
    """
    Extract service names from tfvars file filtered by application.
    
    Args:
        tfvars_path: Path to services.generated.tfvars file
        target_application: Application name to filter by, or "all" for all services
        
    Returns:
        List of service names matching the application filter
    """
    services = []
    current_service = None
    current_app = None
    in_service_block = False
    brace_count = 0
    
    if not tfvars_path.exists():
        raise FileNotFoundError(f"Terraform variables file not found: {tfvars_path}")
    
    with tfvars_path.open("r", encoding="utf-8") as f:
        for line in f:
            # Match service name: "service_name = {"
            service_match = re.match(r'^\s+(\w+)\s*=\s*\{', line)
            if service_match:
                current_service = service_match.group(1)
                in_service_block = True
                brace_count = 1
                current_app = None
                continue
            
            if in_service_block:
                # Count braces to track block depth
                brace_count += line.count('{') - line.count('}')
                
                # Match application field: application = "app-name"
                app_match = re.search(r'application\s*=\s*"([^"]+)"', line)
                if app_match:
                    current_app = app_match.group(1)
                
                # End of service block
                if brace_count == 0:
                    if current_service:
                        # Include service if:
                        # - target_application is "all", OR
                        # - current_app matches target_application, OR
                        # - current_app is None and target_application is "legacy" (backward compat)
                        if (
                            target_application == "all" or
                            current_app == target_application or
                            (current_app is None and target_application == "legacy")
                        ):
                            services.append(current_service)
                    in_service_block = False
                    current_service = None
                    current_app = None
    
    return services


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Filter services from tfvars by application"
    )
    parser.add_argument(
        "tfvars_path",
        type=Path,
        help="Path to services.generated.tfvars file"
    )
    parser.add_argument(
        "application",
        type=str,
        help='Application name to filter by, or "all" for all services'
    )
    parser.add_argument(
        "--format",
        choices=["json", "list"],
        default="json",
        help="Output format: json (default) or list (space-separated)"
    )
    
    args = parser.parse_args()
    
    try:
        services = extract_services_by_application(args.tfvars_path, args.application)
        
        if args.format == "json":
            print(json.dumps(services))
        else:
            print(" ".join(services))
        
        if not services:
            sys.exit(1)  # Exit with error if no services found
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

