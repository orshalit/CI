#!/usr/bin/env python
"""
Update image_tag values in services.generated.tfvars file.

This script updates the image_tag field for specified services in a Terraform
tfvars file. It preserves the file structure and formatting while updating
only the image_tag values.

Usage:
    python update_service_image_tags.py \
        --tfvars-file path/to/services.generated.tfvars \
        --service-tags '{"service1": "v1.0.0", "service2": "v2.0.0"}'
"""

import argparse
import json
import re
import sys
from pathlib import Path


def update_image_tags(tfvars_file: Path, service_tags: dict[str, str]) -> bool:
    """
    Update image_tag values in services.generated.tfvars file.
    
    Args:
        tfvars_file: Path to services.generated.tfvars file
        service_tags: Dictionary mapping service keys to image tags
        
    Returns:
        True if any changes were made, False otherwise
    """
    if not tfvars_file.exists():
        print(f"Error: File not found: {tfvars_file}", file=sys.stderr)
        return False
    
    content = tfvars_file.read_text(encoding="utf-8")
    original_content = content
    changes_made = False
    
    # Pattern to match service blocks: "service_key" = {
    service_pattern = re.compile(r'^\s*"([^"]+)"\s*=\s*\{', re.MULTILINE)
    
    # Find all service keys and their positions
    service_matches = list(service_pattern.finditer(content))
    
    if not service_matches:
        print(f"Warning: No services found in {tfvars_file}", file=sys.stderr)
        return False
    
    # Process from end to start to preserve positions
    for match in reversed(service_matches):
        service_key = match.group(1)
        
        if service_key not in service_tags:
            continue
        
        new_tag = service_tags[service_key]
        
        # Find the image_tag line within this service block
        # Look for the next service block or end of services map
        start_pos = match.end()
        
        # Find the end of this service block (next service or closing brace)
        next_service_match = None
        for next_match in service_matches:
            if next_match.start() > start_pos:
                next_service_match = next_match
                break
        
        if next_service_match:
            end_pos = next_service_match.start()
        else:
            # Last service, find the closing brace of services map
            brace_count = 1
            end_pos = start_pos
            while end_pos < len(content) and brace_count > 0:
                if content[end_pos] == '{':
                    brace_count += 1
                elif content[end_pos] == '}':
                    brace_count -= 1
                end_pos += 1
        
        service_block = content[start_pos:end_pos]
        
        # Find and replace image_tag in this service block
        # Pattern: image_tag = "old_value"
        image_tag_pattern = re.compile(
            r'(image_tag\s*=\s*)"([^"]+)"',
            re.MULTILINE
        )
        
        tag_match = image_tag_pattern.search(service_block)
        if tag_match:
            old_tag = tag_match.group(2)
            if old_tag != new_tag:
                # Replace in the full content
                full_match_start = start_pos + tag_match.start()
                full_match_end = start_pos + tag_match.end()
                content = (
                    content[:full_match_start] +
                    f'{tag_match.group(1)}"{new_tag}"' +
                    content[full_match_end:]
                )
                changes_made = True
                print(f"Updated {service_key}: {old_tag} -> {new_tag}")
        else:
            print(f"Warning: image_tag not found for service '{service_key}'", file=sys.stderr)
    
    if changes_made:
        tfvars_file.write_text(content, encoding="utf-8")
        print(f"✓ Updated {tfvars_file}")
        return True
    else:
        print("No changes needed - all image tags are already up to date")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Update image_tag values in services.generated.tfvars"
    )
    parser.add_argument(
        "--tfvars-file",
        type=Path,
        required=True,
        help="Path to services.generated.tfvars file"
    )
    parser.add_argument(
        "--service-tags",
        type=str,
        required=True,
        help="JSON object mapping service keys to image tags, e.g. '{\"service1\": \"v1.0.0\"}'"
    )
    
    args = parser.parse_args()
    
    try:
        service_tags = json.loads(args.service_tags)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in --service-tags: {e}", file=sys.stderr)
        sys.exit(1)
    
    if not isinstance(service_tags, dict):
        print("Error: --service-tags must be a JSON object", file=sys.stderr)
        sys.exit(1)
    
    update_image_tags(args.tfvars_file, service_tags)
    # Always exit 0 for idempotency; "no changes needed" is success.
    sys.exit(0)


if __name__ == "__main__":
    main()

