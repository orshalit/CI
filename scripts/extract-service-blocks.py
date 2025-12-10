#!/usr/bin/env python3
"""
Extract full service blocks from services.generated.tfvars for specified service names.

This script reads a Terraform tfvars file and extracts complete service blocks
for the specified service names, preserving formatting and structure.
"""

import re
import sys
from pathlib import Path


def extract_service_blocks(tfvars_path: Path, service_names: list[str], output_path: Path) -> int:
    """
    Extract full service blocks for specified service names.
    
    Args:
        tfvars_path: Path to services.generated.tfvars file
        service_names: List of service names to extract
        output_path: Path to write filtered services file
        
    Returns:
        Number of services extracted
    """
    if not tfvars_path.exists():
        raise FileNotFoundError(f"Terraform variables file not found: {tfvars_path}")
    
    with tfvars_path.open("r", encoding="utf-8") as f:
        content = f.read()
    
    services_to_include = set(service_names)
    extracted_services = []
    
    # Match service blocks: "service-name" = { ... }
    pattern = r'^\s+("([^"]+)")\s*=\s*\{'
    for match in re.finditer(pattern, content, re.MULTILINE):
        service_key = match.group(2)
        if service_key in services_to_include:
            # Find the matching closing brace
            start_pos = match.end()
            brace_count = 1
            pos = start_pos
            while pos < len(content) and brace_count > 0:
                if content[pos] == '{':
                    brace_count += 1
                elif content[pos] == '}':
                    brace_count -= 1
                pos += 1
            
            # Extract the full service block
            service_block = content[match.start():pos]
            extracted_services.append(service_block)
    
    # Write extracted services to output file
    with output_path.open("a", encoding="utf-8") as f:
        for service_block in extracted_services:
            # Indent properly (add 2 spaces to each line)
            for line in service_block.split('\n'):
                if line.strip():
                    f.write('  ' + line + '\n')
                else:
                    f.write('\n')
        f.write('}\n')
    
    return len(extracted_services)


def main() -> None:
    if len(sys.argv) != 4:
        print("Usage: extract-service-blocks.py <services_file> <output_file> <service_names>", file=sys.stderr)
        print("  service_names: Space-separated list of service names", file=sys.stderr)
        sys.exit(1)
    
    services_file = Path(sys.argv[1])
    output_file = Path(sys.argv[2])
    service_names = sys.argv[3].split()
    
    try:
        count = extract_service_blocks(services_file, service_names, output_file)
        print(f"Extracted {count} service(s)")
        if count == 0:
            sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

