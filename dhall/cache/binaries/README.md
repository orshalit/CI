# Dhall Binaries Cache

This directory contains cached Dhall binaries (`dhall` and `dhall-to-json`) as a fallback when GitHub releases are unavailable.

## Purpose

- **Resilience**: Provides a stable fallback if GitHub releases are down or unreachable
- **Speed**: GitHub Actions cache speeds up subsequent runs
- **Reliability**: Ensures CI/CD pipelines continue working even during external outages

## How It Works

1. **Primary**: Download from GitHub releases (always latest)
2. **Fallback 1**: Use GitHub Actions cache (fast, persists across runs)
3. **Fallback 2**: Use repository cache (stable, committed binaries)

## Updating the Cache

To update the cached binaries to a new version:

```bash
# Update the version in scripts/install-dhall-with-fallback.sh
# Then run:
bash scripts/populate-dhall-binaries-cache.sh

# Commit the updated binaries:
git add dhall/cache/binaries/
git commit -m "chore: Update Dhall binaries cache to vX.Y.Z"
```

## Current Version

- **Dhall**: 1.41.2
- **Last Updated**: See git history

## Files

- `dhall` - Dhall interpreter binary
- `dhall-to-json` - Dhall to JSON converter binary

These binaries are Linux x86_64 executables and are automatically used by the installation script when GitHub releases are unavailable.

