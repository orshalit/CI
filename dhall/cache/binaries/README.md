# Dhall Binaries Cache

This directory contains cached Dhall binaries (`dhall` and `dhall-to-json`) as a fallback when GitHub releases are unavailable.

## Official Sources

- **Documentation**: https://docs.dhall-lang.org/
- **Installation Guide**: https://docs.dhall-lang.org/tutorials/Getting-started_Generate-JSON-or-YAML.html#installation
- **GitHub Releases**: https://github.com/dhall-lang/dhall-haskell/releases
- **Repository**: https://github.com/dhall-lang/dhall-haskell

## Purpose

- **Resilience**: Provides a stable fallback if GitHub releases are down or unreachable
- **Speed**: GitHub Actions cache speeds up subsequent runs
- **Reliability**: Ensures CI/CD pipelines continue working even during external outages

## How It Works

1. **Primary**: Download from GitHub releases (always latest, official source)
2. **Fallback 1**: Use GitHub Actions cache (fast, persists across runs, auto-managed by GitHub)
3. **Fallback 2**: Use repository cache (stable, pre-populated, committed binaries)

**Important**: The repository cache is NOT updated automatically. It's a stable fallback that you manually update when needed.

## Updating the Cache

To update the cached binaries to a new version:

1. Check the latest version on GitHub releases: https://github.com/dhall-lang/dhall-haskell/releases
2. Download the new binaries manually from the release page
3. Replace the binaries in this directory
4. Commit the updated binaries:
   ```bash
   git add dhall/cache/binaries/{dhall,dhall-to-json}
   git commit -m "chore: Update Dhall binaries cache to vX.Y.Z"
   ```

The populate script downloads binaries directly from the official GitHub releases, matching the official installation documentation.

## Current Version

- **Dhall**: 1.41.2
- **Source**: Official GitHub releases (dhall-lang/dhall-haskell)
- **Last Updated**: See git history

## Files

- `dhall` - Dhall interpreter binary (Linux x86_64)
- `dhall-to-json` - Dhall to JSON converter binary (Linux x86_64)

These binaries are Linux x86_64 executables downloaded from the official GitHub releases and are automatically used by the installation script when GitHub releases are unavailable.

