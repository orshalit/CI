#!/usr/bin/env python
"""
Detect which Docker images need to be built based on application structure.

This script scans the applications/ directory to determine:
- Which applications have app-specific code (backend/frontend directories)
- Which images should be built (shared vs app-specific)
- Returns a JSON matrix for CI/CD workflows
"""

import argparse
import json
import pathlib
import sys
from typing import Dict, List, Set


def detect_application_code_directories(base_dir: pathlib.Path) -> Dict[str, Dict[str, bool]]:
    """
    Detect which applications have app-specific code directories.
    
    Returns:
        {
            "legacy": {"backend": False, "frontend": False},
            "test-app": {"backend": True, "frontend": False},
            ...
        }
    """
    applications_dir = base_dir / "applications"
    if not applications_dir.exists():
        return {}
    
    app_code_map: Dict[str, Dict[str, bool]] = {}
    
    for app_dir in sorted(applications_dir.iterdir()):
        if not app_dir.is_dir():
            continue
        
        app_name = app_dir.name
        app_code_map[app_name] = {
            "backend": (app_dir / "backend").exists() and (app_dir / "backend").is_dir(),
            "frontend": (app_dir / "frontend").exists() and (app_dir / "frontend").is_dir(),
        }
    
    return app_code_map


def generate_build_matrix(
    base_dir: pathlib.Path,
    include_shared: bool = True
) -> Dict[str, List[Dict[str, str]]]:
    """
    Generate build matrix for CI/CD workflow.
    
    Returns:
        {
            "include": [
                {"service": "backend", "type": "shared", "context": "./backend", ...},
                {"service": "frontend", "type": "shared", "context": "./frontend", ...},
                {"service": "backend", "type": "app-specific", "app": "test-app", "context": "./applications/test-app/backend", ...},
            ]
        }
    """
    app_code_map = detect_application_code_directories(base_dir)
    build_matrix: List[Dict[str, str]] = []
    
    # Always include shared images if they exist
    if include_shared:
        shared_backend = base_dir / "backend"
        shared_frontend = base_dir / "frontend"
        
        if shared_backend.exists() and shared_backend.is_dir():
            build_matrix.append({
                "service": "backend",
                "type": "shared",
                "context": "./backend",
                "image_name": "ci-backend",
                "dockerfile": "./backend/Dockerfile"
            })
        
        if shared_frontend.exists() and shared_frontend.is_dir():
            build_matrix.append({
                "service": "frontend",
                "type": "shared",
                "context": "./frontend",
                "image_name": "ci-frontend",
                "dockerfile": "./frontend/Dockerfile"
            })
    
    # Add app-specific images
    for app_name, code_dirs in app_code_map.items():
        if code_dirs["backend"]:
            backend_dir = base_dir / "applications" / app_name / "backend"
            build_matrix.append({
                "service": "backend",
                "type": "app-specific",
                "app": app_name,
                "context": f"./applications/{app_name}/backend",
                "image_name": f"{app_name}-backend",
                "dockerfile": f"./applications/{app_name}/backend/Dockerfile"
            })
        
        if code_dirs["frontend"]:
            frontend_dir = base_dir / "applications" / app_name / "frontend"
            build_matrix.append({
                "service": "frontend",
                "type": "app-specific",
                "app": app_name,
                "context": f"./applications/{app_name}/frontend",
                "image_name": f"{app_name}-frontend",
                "dockerfile": f"./applications/{app_name}/frontend/Dockerfile"
            })
    
    return {"include": build_matrix}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Detect application-specific code and generate build matrix"
    )
    parser.add_argument(
        "--base-dir",
        type=pathlib.Path,
        default=pathlib.Path("."),
        help="Path to CI repository root (default: current directory)"
    )
    parser.add_argument(
        "--format",
        choices=["json", "matrix", "list"],
        default="json",
        help="Output format: json (full matrix), matrix (GitHub Actions format), list (simple list)"
    )
    parser.add_argument(
        "--no-shared",
        action="store_true",
        help="Exclude shared images from output"
    )
    
    args = parser.parse_args()
    
    if not args.base_dir.exists():
        print(f"Error: Base directory does not exist: {args.base_dir}", file=sys.stderr)
        sys.exit(1)
    
    matrix = generate_build_matrix(args.base_dir, include_shared=not args.no_shared)
    
    if args.format == "json":
        print(json.dumps(matrix, indent=2))
    elif args.format == "matrix":
        # GitHub Actions matrix format
        print(json.dumps(matrix))
    elif args.format == "list":
        # Simple list of image names
        images = [item["image_name"] for item in matrix["include"]]
        print("\n".join(images))


if __name__ == "__main__":
    main()

