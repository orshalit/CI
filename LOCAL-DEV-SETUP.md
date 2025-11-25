# Local Development Setup Guide

This guide ensures your local development environment matches CI exactly, preventing "works locally but fails in CI" issues.

## 🎯 Quick Start

```bash
# 1. Install dependencies
make install

# 2. Install pre-commit hooks (recommended)
pip install pre-commit
pre-commit install

# 3. Before pushing, run CI checks locally
make ci-local
```

## 📋 Prerequisites

**Exact versions required:**
- Python 3.11 (not 3.10, not 3.12)
- Node.js 20 (not 19, not 21)
- Docker & Docker Compose

**Verify versions:**
```bash
python3 --version  # Should show 3.11.x
node --version     # Should show v20.x.x
```

## 🔧 Setup Steps

### 1. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv venv

# Activate (Linux/Mac)
source venv/bin/activate

# Activate (Windows)
venv\Scripts\activate

# Install dependencies (exact versions from requirements.txt)
pip install --upgrade pip
pip install -r requirements.txt
```

**Key tools installed:**
- `ruff==0.14.6` - Linter (exact version)
- `black==23.12.1` - Formatter
- `pytest==7.4.3` - Test framework

### 2. Frontend Setup

```bash
cd frontend

# Install dependencies (uses package-lock.json for exact versions)
npm ci
```

**Note:** Always use `npm ci` (not `npm install`) to ensure exact versions match CI.

### 3. Pre-commit Hooks (Recommended)

Pre-commit hooks automatically run linters before each commit:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Test hooks
pre-commit run --all-files
```

**What it does:**
- Runs Ruff and Black on Python files
- Runs ESLint on JavaScript files
- Checks for trailing whitespace, YAML/JSON validity
- Prevents committing code that would fail CI

## ✅ Before Committing

**Always run this before pushing:**

```bash
make ci-local
```

This runs:
1. Version checks
2. Backend linting (Ruff)
3. Backend formatting check (Black)
4. Backend tests
5. Frontend linting (ESLint)
6. Frontend formatting check (Prettier)
7. Frontend tests

**If any check fails, fix it locally before pushing!**

## 🛠️ Common Commands

### Using Makefile (Recommended)

```bash
make help              # Show all available commands
make install           # Install all dependencies
make lint              # Run all linters
make format            # Format all code
make test              # Run all tests
make ci-local          # Run full CI simulation
make check-versions    # Verify tool versions match CI
```

### Manual Commands

**Backend:**
```bash
cd backend
source venv/bin/activate

# Lint
ruff check .

# Format
black .
ruff format .

# Test
pytest
```

**Frontend:**
```bash
cd frontend

# Lint
npm run lint

# Format
npm run format

# Test
npm test
```

## 🔍 Troubleshooting

### "Tool version mismatch" errors

**Problem:** Local tool version doesn't match CI.

**Solution:**
```bash
# Backend - reinstall exact versions
cd backend
source venv/bin/activate
pip install --force-reinstall -r requirements.txt

# Frontend - reinstall exact versions
cd frontend
rm -rf node_modules package-lock.json
npm ci
```

### "Works locally but fails in CI"

**Common causes:**
1. Different tool versions
2. Different Python/Node versions
3. Uncommitted formatting changes
4. Missing dependencies

**Solution:**
```bash
# Run local CI simulation
make ci-local

# If it passes locally but fails in CI, check:
make check-versions  # Verify versions match
git status           # Check for uncommitted changes
```

### Pre-commit hooks not running

```bash
# Reinstall hooks
pre-commit install

# Run manually
pre-commit run --all-files

# Skip hooks (not recommended)
git commit --no-verify
```

## 📝 Best Practices

1. **Always use exact versions** - Don't use `>=` or `~` in requirements.txt
2. **Run `make ci-local` before pushing** - Catch issues early
3. **Use pre-commit hooks** - Automatic checks before commit
4. **Use `npm ci` not `npm install`** - Ensures exact versions
5. **Commit `package-lock.json`** - Already done ✓
6. **Keep requirements.txt pinned** - Exact versions only

## 🎓 Workflow

**Recommended daily workflow:**

```bash
# Morning: Pull latest changes
git pull

# Before coding: Ensure environment is set up
make check-versions

# While coding: Let pre-commit hooks catch issues automatically

# Before committing: Run full CI check
make ci-local

# If all passes: Commit and push
git add .
git commit -m "your message"
git push
```

## 🔗 Related Files

- `Makefile` - Common commands
- `.pre-commit-config.yaml` - Pre-commit hooks configuration
- `scripts/test-local.sh` - Local CI simulation script
- `backend/requirements.txt` - Python dependencies (exact versions)
- `frontend/package-lock.json` - JavaScript dependencies (exact versions)

## 📚 Additional Resources

- [Pre-commit documentation](https://pre-commit.com/)
- [Ruff documentation](https://docs.astral.sh/ruff/)
- [Black documentation](https://black.readthedocs.io/)
- [ESLint documentation](https://eslint.org/)

