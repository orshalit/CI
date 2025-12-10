# Docker Compose File Location - Best Practices

## Options Comparison

### Option 1: Per-Application Directory (✅ **RECOMMENDED**)

```
CI/
├── docker-compose.base.yml              # Shared infrastructure
├── docker-compose.yml                   # Legacy: all-in-one
├── applications/
│   ├── test-app/
│   │   ├── docker-compose.yml          # ✅ App-specific compose
│   │   ├── backend/
│   │   └── frontend/
│   └── app2/
│       ├── docker-compose.yml          # ✅ App-specific compose
│       └── ...
```

**Pros:**
- ✅ **Self-contained**: Each app owns its compose file
- ✅ **Co-location**: Compose file lives with the code it orchestrates
- ✅ **Best Practice**: Follows Docker/industry recommendations
- ✅ **Discoverability**: Developers find it in the app directory
- ✅ **Portability**: App can be moved/extracted easily
- ✅ **Clear ownership**: App team owns the file

**Cons:**
- ⚠️ Slightly longer paths when referencing from root
- ⚠️ Need to specify full path: `-f applications/test-app/docker-compose.yml`

**Usage:**
```bash
docker compose -f docker-compose.base.yml \
               -f applications/test-app/docker-compose.yml up
```

---

### Option 2: Root Level (Current)

```
CI/
├── docker-compose.base.yml              # Shared infrastructure
├── docker-compose.yml                   # Legacy: all-in-one
├── docker-compose.test-app.yml          # App-specific compose
├── docker-compose.app2.yml              # App-specific compose
└── applications/
    ├── test-app/
    └── app2/
```

**Pros:**
- ✅ **Centralized**: All compose files in one place
- ✅ **Easy discovery**: All compose files visible at root
- ✅ **Shorter paths**: `-f docker-compose.test-app.yml`
- ✅ **Glob patterns**: Easy to reference all: `docker-compose.*.yml`

**Cons:**
- ❌ **Not self-contained**: Compose file separated from app code
- ❌ **Less portable**: Harder to extract app as standalone
- ❌ **Clutter**: Root directory gets crowded with many apps

**Usage:**
```bash
docker compose -f docker-compose.base.yml \
               -f docker-compose.test-app.yml up
```

---

### Option 3: Dedicated Directory

```
CI/
├── docker-compose.base.yml
├── docker-compose.yml
├── docker-compose/
│   ├── test-app.yml
│   └── app2.yml
└── applications/
```

**Pros:**
- ✅ Organized separation
- ✅ Keeps root clean

**Cons:**
- ❌ **Not discoverable**: Hidden in subdirectory
- ❌ **Not co-located**: Separated from app code
- ❌ **Extra nesting**: More complex paths

---

## Recommendation: **Option 1 - Per-Application Directory** ✅

### Why?

1. **Self-Containment**: Each app is truly self-contained
   - App code, Dockerfile, and docker-compose.yml all together
   - Easy to understand what the app needs
   - Can be extracted/moved as a unit

2. **Best Practice**: Industry standard
   - Docker documentation recommends co-location
   - Microservices pattern: each service owns its config
   - Monorepo best practice: keep related files together

3. **Developer Experience**:
   - Developer working on `test-app` finds everything in `applications/test-app/`
   - No need to look at root for app-specific config
   - Clear boundaries and ownership

4. **Scalability**:
   - As you add more apps, root stays clean
   - Each app directory is complete and independent

### Migration Path

**Current (Root Level):**
```bash
docker compose -f docker-compose.base.yml -f docker-compose.test-app.yml up
```

**Recommended (Per-App Directory):**
```bash
docker compose -f docker-compose.base.yml \
               -f applications/test-app/docker-compose.yml up
```

### Updated Structure

```
CI/
├── docker-compose.base.yml              # Shared infrastructure (database, etc.)
├── docker-compose.yml                   # Legacy: all-in-one (backward compat)
├── docker-compose.prod.yml              # Legacy: production all-in-one
├── applications/
│   ├── test-app/
│   │   ├── docker-compose.yml          # ✅ App-specific (recommended location)
│   │   ├── docker-compose.prod.yml    # ✅ Production overrides (optional)
│   │   ├── backend/
│   │   │   └── Dockerfile
│   │   └── frontend/
│   │       └── Dockerfile
│   └── app2/
│       ├── docker-compose.yml          # ✅ App-specific
│       └── ...
└── scripts/
    └── generate-app-compose.sh         # Generates to app directory
```

### Benefits of Per-App Location

1. **Self-Documenting**: 
   - `applications/test-app/docker-compose.yml` clearly belongs to test-app
   - New developers immediately understand structure

2. **Portability**:
   - Can copy `applications/test-app/` to another repo
   - Everything needed is in one place

3. **Version Control**:
   - Changes to app compose file are in same directory as code changes
   - Easier to review: "What changed in test-app?" → check `applications/test-app/`

4. **CI/CD Friendly**:
   - Can detect changes: `git diff applications/test-app/`
   - Only regenerate compose for changed apps

### Implementation

Update generation script to output to app directory:
```bash
# Generate to app directory (recommended)
./scripts/generate-app-compose.sh test-app
# Creates: applications/test-app/docker-compose.yml

# Or generate all apps
./scripts/generate-app-compose.sh
# Creates: applications/*/docker-compose.yml
```

### Usage Examples

**Development - Single App:**
```bash
cd applications/test-app
docker compose -f ../../docker-compose.base.yml \
               -f docker-compose.yml up
```

**Development - From Root:**
```bash
docker compose -f docker-compose.base.yml \
               -f applications/test-app/docker-compose.yml up
```

**CI/CD - All Apps:**
```bash
docker compose -f docker-compose.base.yml \
               -f applications/*/docker-compose.yml up
```

---

## Final Recommendation

**Use Option 1: Per-Application Directory**

- ✅ Best practice
- ✅ Self-contained apps
- ✅ Better developer experience
- ✅ More maintainable long-term
- ✅ Scales better with many apps

Move compose files to `applications/{app-name}/docker-compose.yml` and update generation script accordingly.

