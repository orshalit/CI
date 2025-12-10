# Docker Compose Architecture - Best Practices

## Current Architecture: Hybrid Approach ✅

We use a **hybrid approach** that combines the best of both worlds:

### Structure

```
docker-compose.base.yml          # Shared infrastructure (database, redis, etc.)
docker-compose.{app-name}.yml    # Per-application services (one per app)
docker-compose.yml               # Legacy: All-in-one (auto-generated for backward compatibility)
```

### Why This Approach?

#### ✅ **Best Practice: Separation of Concerns**

1. **Shared Infrastructure** (`docker-compose.base.yml`)
   - Database, Redis, Message Queues
   - Shared by all applications
   - Managed centrally

2. **Application-Specific** (`docker-compose.{app-name}.yml`)
   - Each app has its own compose file
   - Independent scaling and management
   - Clear ownership and boundaries

#### ✅ **Benefits**

1. **Modularity**: Each app is self-contained
2. **Selective Startup**: Start only what you need
   ```bash
   # Start only test-app
   docker compose -f docker-compose.base.yml -f docker-compose.test-app.yml up
   
   # Start multiple apps
   docker compose -f docker-compose.base.yml \
                  -f docker-compose.test-app.yml \
                  -f docker-compose.other-app.yml up
   ```

3. **Isolation**: Apps don't interfere with each other
4. **Scalability**: Scale apps independently
5. **Maintainability**: Changes to one app don't affect others

### Usage Examples

#### Development - Single App
```bash
# Work on test-app only
docker compose -f docker-compose.base.yml -f docker-compose.test-app.yml up --build
```

#### Development - Multiple Apps
```bash
# Work on multiple apps
docker compose -f docker-compose.base.yml \
               -f docker-compose.test-app.yml \
               -f docker-compose.app2.yml up
```

#### CI/CD - All Apps
```bash
# Test all apps together (like production)
docker compose -f docker-compose.base.yml \
               -f docker-compose.*.yml up --build
```

#### Production-like Testing
```bash
# Use production images
export TEST_APP_BACKEND_IMAGE=ghcr.io/orshalit/test-app-backend:v1.0.0
docker compose -f docker-compose.base.yml \
               -f docker-compose.test-app.yml up
```

### Migration Path

**Current State:**
- `docker-compose.yml` - All apps in one file (auto-generated)
- Used for backward compatibility and CI/CD

**Future State (Recommended):**
- Use per-app files for development
- Use base + all apps for CI/CD
- Gradually migrate workflows

### Regeneration

Files are auto-generated:
```bash
# Generate base (shared infrastructure)
# (manual, rarely changes)

# Generate per-app compose files
./scripts/generate-app-compose.sh test-app
./scripts/generate-app-compose.sh test-app --prod

# Generate all apps
./scripts/generate-app-compose.sh
```

### Comparison: Single vs Multiple Files

| Aspect | Single File (Current) | Multiple Files (Recommended) |
|--------|----------------------|------------------------------|
| **Simplicity** | ✅ One command | ⚠️ Multiple files |
| **Modularity** | ❌ All or nothing | ✅ Per-app control |
| **Scalability** | ❌ Hard to scale | ✅ Independent scaling |
| **Isolation** | ❌ Shared namespace | ✅ Clear boundaries |
| **CI/CD** | ✅ Simple | ✅ Flexible |
| **Development** | ⚠️ Starts everything | ✅ Start what you need |

### Recommendation

**For Development:** Use per-app files
```bash
docker compose -f docker-compose.base.yml -f docker-compose.test-app.yml up
```

**For CI/CD:** Use base + all apps (or single file for simplicity)
```bash
docker compose -f docker-compose.base.yml -f docker-compose.*.yml up
```

**For Production:** Use orchestration (ECS/Kubernetes), not docker-compose

### Next Steps

1. ✅ Base file created (`docker-compose.base.yml`)
2. ✅ Per-app generation script created (`generate-app-compose.sh`)
3. ⏳ Migrate CI/CD to use base + per-app files
4. ⏳ Update documentation and developer guides
5. ⏳ Deprecate single-file approach gradually

