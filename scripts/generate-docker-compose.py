#!/usr/bin/env python3
"""
Generate docker-compose.yml dynamically from application structure.

This script scans applications/ directory and generates docker-compose.yml
that works for local development with any number of applications.
"""

import argparse
import json
import pathlib
import sys
from typing import Dict, List, Optional


def detect_applications(base_dir: pathlib.Path) -> Dict[str, Dict[str, bool]]:
    """Detect all applications and their backend/frontend directories."""
    applications_dir = base_dir / "applications"
    if not applications_dir.exists():
        return {}
    
    apps = {}
    for app_dir in sorted(applications_dir.iterdir()):
        if not app_dir.is_dir():
            continue
        
        app_name = app_dir.name
        apps[app_name] = {
            "backend": (app_dir / "backend").exists() and (app_dir / "backend" / "Dockerfile").exists(),
            "frontend": (app_dir / "frontend").exists() and (app_dir / "frontend" / "Dockerfile").exists(),
        }
    
    return apps


def generate_docker_compose(
    base_dir: pathlib.Path,
    output_file: pathlib.Path,
    prod: bool = False
) -> None:
    """Generate docker-compose.yml file."""
    apps = detect_applications(base_dir)
    
    # Check if database exists (shared resource)
    has_database = True  # Always include database
    
    services = {}
    
    # Add database service (shared)
    if has_database:
        services["database"] = {
            "image": "postgres:15-alpine",
            "container_name": "database",
            "environment": {
                "POSTGRES_USER": "${POSTGRES_USER:-appuser}",
                "POSTGRES_PASSWORD": "${POSTGRES_PASSWORD:-apppassword}" if prod else "${POSTGRES_PASSWORD:-apppassword}",
                "POSTGRES_DB": "${POSTGRES_DB:-appdb}",
            },
            "ports": ["${POSTGRES_PORT:-5432}:5432"],
            "volumes": ["postgres_data:/var/lib/postgresql/data"],
            "healthcheck": {
                "test": ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-appuser} -d ${POSTGRES_DB:-appdb}"],
                "interval": "10s" if prod else "5s",
                "timeout": "5s" if prod else "3s",
                "retries": 5,
                "start_period": "30s" if prod else "10s",
            },
            "networks": ["app-network"],
            "restart": "unless-stopped",
            "deploy": {
                "resources": {
                    "limits": {"cpus": "1.0", "memory": "512M"},
                    "reservations": {"cpus": "0.5" if prod else "0.25", "memory": "256M" if prod else "128M"},
                }
            },
        }
        
        if prod:
            services["database"]["logging"] = {
                "driver": "json-file",
                "options": {"max-size": "10m", "max-file": "3"},
            }
    
    # Add application services dynamically
    for app_name, has_services in apps.items():
        if has_services["backend"]:
            backend_context = f"./applications/{app_name}/backend"
            service_name = f"{app_name}-backend"
            
            if prod:
                # Production: use image from registry
                services[service_name] = {
                    "image": f"${{{app_name.upper().replace('-', '_')}_BACKEND_IMAGE:-ghcr.io/orshalit/{app_name}-backend:latest}}",
                    "container_name": service_name,
                    "ports": [f"${{{app_name.upper().replace('-', '_')}_BACKEND_PORT:-8000}}:8000"],
                    "environment": {
                        "DATABASE_URL": "postgresql://${POSTGRES_USER:-appuser}:${POSTGRES_PASSWORD}@database:5432/${POSTGRES_DB:-appdb}",
                        "LOG_LEVEL": "${LOG_LEVEL:-INFO}",
                        "LOG_FORMAT": "${LOG_FORMAT:-json}",
                    },
                    "depends_on": {
                        "database": {"condition": "service_healthy"},
                    },
                    "healthcheck": {
                        "test": ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"],
                        "interval": "30s",
                        "timeout": "5s",
                        "retries": 3,
                        "start_period": "40s",
                    },
                    "networks": ["app-network"],
                    "restart": "unless-stopped",
                    "deploy": {
                        "resources": {
                            "limits": {"cpus": "1.0", "memory": "512M"},
                            "reservations": {"cpus": "0.5", "memory": "256M"},
                        }
                    },
                    "logging": {
                        "driver": "json-file",
                        "options": {"max-size": "10m", "max-file": "3"},
                    },
                }
            else:
                # Development: build from source
                services[service_name] = {
                    "build": {
                        "context": backend_context,
                        "dockerfile": "Dockerfile",
                        "args": {
                            "BUILD_DATE": "${BUILD_DATE:-2024-01-01T00:00:00Z}",
                            "BUILD_VERSION": "${BUILD_VERSION:-dev}",
                            "GIT_COMMIT": "${GIT_COMMIT:-unknown}",
                            "GIT_BRANCH": "${GIT_BRANCH:-main}",
                        },
                    },
                    "image": f"{app_name}-backend:${BUILD_VERSION:-dev}",
                    "container_name": service_name,
                    "ports": [f"${{{app_name.upper().replace('-', '_')}_BACKEND_PORT:-8000}}:8000"],
                    "environment": {
                        "DATABASE_URL": "postgresql://${POSTGRES_USER:-appuser}:${POSTGRES_PASSWORD:-apppassword}@database:5432/${POSTGRES_DB:-appdb}",
                        "LOG_LEVEL": "${LOG_LEVEL:-INFO}",
                        "RATE_LIMIT_ENABLED": "${RATE_LIMIT_ENABLED:-false}",
                    },
                    "depends_on": {
                        "database": {"condition": "service_healthy"},
                    },
                    "healthcheck": {
                        "test": ["CMD", "curl", "-f", "http://localhost:8000/health"],
                        "interval": "10s",
                        "timeout": "3s",
                        "retries": 3,
                        "start_period": "30s",
                    },
                    "networks": ["app-network"],
                    "restart": "unless-stopped",
                    "deploy": {
                        "resources": {
                            "limits": {"cpus": "1.0", "memory": "512M"},
                            "reservations": {"cpus": "0.25", "memory": "128M"},
                        }
                    },
                }
        
        if has_services["frontend"]:
            frontend_context = f"./applications/{app_name}/frontend"
            service_name = f"{app_name}-frontend"
            
            if prod:
                # Production: use image from registry
                services[service_name] = {
                    "image": f"${{{app_name.upper().replace('-', '_')}_FRONTEND_IMAGE:-ghcr.io/orshalit/{app_name}-frontend:latest}}",
                    "container_name": service_name,
                    "ports": [f"${{{app_name.upper().replace('-', '_')}_FRONTEND_PORT:-3000}}:3000"],
                    "environment": {
                        "VITE_BACKEND_URL": f"${{{app_name.upper().replace('-', '_')}_BACKEND_URL:-http://{app_name}-backend:8000}}",
                    },
                    "depends_on": {
                        f"{app_name}-backend": {"condition": "service_healthy"},
                    },
                    "healthcheck": {
                        "test": ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/"],
                        "interval": "30s",
                        "timeout": "5s",
                        "retries": 3,
                        "start_period": "20s",
                    },
                    "networks": ["app-network"],
                    "restart": "unless-stopped",
                    "deploy": {
                        "resources": {
                            "limits": {"cpus": "0.5", "memory": "256M"},
                            "reservations": {"cpus": "0.25", "memory": "128M"},
                        }
                    },
                    "logging": {
                        "driver": "json-file",
                        "options": {"max-size": "10m", "max-file": "3"},
                    },
                }
            else:
                # Development: build from source
                services[service_name] = {
                    "build": {
                        "context": frontend_context,
                        "dockerfile": "Dockerfile",
                        "args": {
                            "BUILD_DATE": "${BUILD_DATE:-2024-01-01T00:00:00Z}",
                            "BUILD_VERSION": "${BUILD_VERSION:-dev}",
                            "GIT_COMMIT": "${GIT_COMMIT:-unknown}",
                            "GIT_BRANCH": "${GIT_BRANCH:-main}",
                        },
                    },
                    "image": f"{app_name}-frontend:${BUILD_VERSION:-dev}",
                    "container_name": service_name,
                    "ports": [f"${{{app_name.upper().replace('-', '_')}_FRONTEND_PORT:-3000}}:3000"],
                    "environment": {
                        "VITE_BACKEND_URL": f"${{{app_name.upper().replace('-', '_')}_BACKEND_URL:-http://{app_name}-backend:8000}}",
                    },
                    "depends_on": {
                        f"{app_name}-backend": {"condition": "service_healthy"},
                    },
                    "healthcheck": {
                        "test": ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000/"],
                        "interval": "10s",
                        "timeout": "3s",
                        "retries": 3,
                        "start_period": "10s",
                    },
                    "networks": ["app-network"],
                    "restart": "unless-stopped",
                    "deploy": {
                        "resources": {
                            "limits": {"cpus": "0.5", "memory": "256M"},
                            "reservations": {"cpus": "0.1", "memory": "64M"},
                        }
                    },
                }
    
    # Generate YAML content
    yaml_content = f"""# {'Production' if prod else 'Development'} docker-compose.yml
# Auto-generated by scripts/generate-docker-compose.py
# DO NOT EDIT MANUALLY - regenerate with: python scripts/generate-docker-compose.py {'--prod' if prod else ''}

version: '3.8'

services:
"""
    
    # Convert services dict to YAML (simplified - using json for now, could use pyyaml)
    import yaml
    yaml_content += yaml.dump({"services": services}, default_flow_style=False, sort_keys=False)
    
    yaml_content += """
networks:
  app-network:
    driver: bridge"""
    
    if prod:
        yaml_content += """
    ipam:
      config:
        - subnet: 172.20.0.0/16"""
    
    yaml_content += """

volumes:
  postgres_data:"""
    
    if prod:
        yaml_content += """
    driver: local"""
    
    yaml_content += "\n"
    
    # Write to file
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(yaml_content)
    print(f"✓ Generated {output_file}")


def main():
    parser = argparse.ArgumentParser(description="Generate docker-compose.yml dynamically")
    parser.add_argument(
        "--base-dir",
        type=pathlib.Path,
        default=pathlib.Path("."),
        help="Path to CI repository root",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        help="Output file path (default: docker-compose.yml or docker-compose.prod.yml)",
    )
    parser.add_argument(
        "--prod",
        action="store_true",
        help="Generate production docker-compose.prod.yml",
    )
    
    args = parser.parse_args()
    
    if args.output:
        output_file = args.output
    else:
        output_file = args.base_dir / ("docker-compose.prod.yml" if args.prod else "docker-compose.yml")
    
    try:
        import yaml
    except ImportError:
        print("Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
        sys.exit(1)
    
    generate_docker_compose(args.base_dir, output_file, prod=args.prod)


if __name__ == "__main__":
    main()

