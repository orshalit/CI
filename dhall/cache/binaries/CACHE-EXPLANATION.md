# How the Dhall Binaries Cache Works

## Overview

The cache is a **pre-populated, committed fallback** - not a runtime cache. Binaries are downloaded once, committed to git, and then used as a fallback when GitHub releases are unavailable.

## Three-Tier Fallback System

### Tier 1: GitHub Releases (Primary)
- **When**: Every workflow run
- **What**: Downloads latest binaries from GitHub releases
- **Speed**: Fast (if GitHub is available)
- **Auto-updates**: Yes (always gets latest version)

### Tier 2: GitHub Actions Cache (Secondary)
- **When**: If GitHub download fails
- **What**: Uses GitHub Actions' built-in cache (auto-managed)
- **Speed**: Very fast (local cache)
- **Auto-updates**: Yes (GitHub Actions manages this automatically)

### Tier 3: Repository Cache (Tertiary - Last Resort)
- **When**: If both GitHub download AND Actions cache fail
- **What**: Uses pre-populated binaries committed to this repo
- **Speed**: Fast (committed files)
- **Auto-updates**: **NO** - Manual only

## How to Pre-Populate the Cache

### Step 1: Run the populate script
```bash
bash scripts/populate-dhall-binaries-cache.sh
```

This script:
1. Downloads `dhall` and `dhall-to-json` binaries from GitHub
2. Saves them to `dhall/cache/binaries/`
3. Makes them executable

### Step 2: Commit the binaries
```bash
git add dhall/cache/binaries/
git commit -m "chore: Add Dhall binaries cache v1.41.2"
git push
```

### Step 3: Done!
Now the binaries are committed to the repo and will be used as a fallback automatically.

## When to Update the Cache

Update the cache when:
- You want to upgrade to a new Dhall version
- The current cached version becomes outdated
- You want to ensure a specific stable version is always available

**You do NOT need to update it every run** - it's a stable fallback that persists.

## Current Status

- **Cache directory**: `dhall/cache/binaries/`
- **Current version**: 1.41.2 (see `scripts/install-dhall-with-fallback.sh`)
- **Status**: Empty (needs initial population)

## Installation Flow in Workflows

When `scripts/install-dhall-with-fallback.sh` runs:

1. **Try GitHub** → Download from releases
   - ✅ Success: Use it, done!
   - ❌ Fail: Continue to step 2

2. **Try Actions Cache** → Check GitHub Actions cache
   - ✅ Success: Use it, done!
   - ❌ Fail: Continue to step 3

3. **Try Repository Cache** → Read from `dhall/cache/binaries/`
   - ✅ Success: Use it, done!
   - ❌ Fail: Error (no binaries available)

## Key Points

- ✅ Cache is **read-only** during workflow runs
- ✅ Cache is **pre-populated** manually and committed
- ✅ Cache provides **resilience** against GitHub outages
- ✅ No runtime overhead - only reads when needed
- ✅ Stable and predictable - same binaries every time

