# Code Quality & Linting Guide

This project uses comprehensive linting and code quality tools to ensure code consistency, catch bugs early, and maintain security standards.

## 📋 Table of Contents

- [Backend (Python)](#backend-python)
- [Frontend (JavaScript/React)](#frontend-javascriptreact)
- [CI/CD Integration](#cicd-integration)
- [Quick Commands](#quick-commands)
- [Configuration Files](#configuration-files)

---

## Backend (Python)

### Tools Used

1. **Flake8** - Python linting (PEP 8 compliance)
2. **Black** - Code formatting
3. **isort** - Import sorting
4. **Pylint** - Advanced static analysis
5. **Bandit** - Security vulnerability scanning
6. **Safety** - Dependency security checks

### Setup

```bash
cd backend

# Install linting tools (included in requirements.txt)
pip install -r requirements.txt

# Or install individually
pip install flake8 black isort pylint bandit safety
```

### Running Linters

```bash
# Run all linters at once
make lint

# Run individual linters
make lint-flake8      # PEP 8 compliance
make lint-black       # Check code formatting
make lint-isort       # Check import ordering
make lint-bandit      # Security scan
make lint-pylint      # Detailed code analysis
make lint-safety      # Check for vulnerable dependencies

# Auto-fix issues
make format           # Auto-format with Black and isort
```

### Manual Commands

```bash
# Flake8 - Check code style
flake8 .
flake8 main.py  # Check specific file

# Black - Format code
black --check .      # Check without modifying
black .              # Format all files
black main.py        # Format specific file

# isort - Sort imports
isort --check-only . # Check without modifying
isort .              # Sort all imports
isort main.py        # Sort specific file

# Bandit - Security scan
bandit -r .                           # Scan all files
bandit -r . -f json -o report.json   # Generate JSON report

# Pylint - Detailed analysis
pylint main.py
pylint *.py

# Safety - Dependency check
safety check
safety check --json
```

### Configuration Files

- **`.flake8`** - Flake8 configuration
  - Max line length: 100
  - Ignores: E203, E501, W503, W504
  - Excludes: venv, build, tests

- **`pyproject.toml`** - Black, isort, Pylint, Bandit config
  - Black: 100 char line length, Python 3.11 target
  - isort: Black-compatible profile
  - Pylint: Reasonable defaults, disabled overly strict rules

### Common Issues & Fixes

#### Line too long
```python
# Bad
some_very_long_function_call_with_many_arguments(arg1, arg2, arg3, arg4, arg5, arg6)

# Good
some_very_long_function_call_with_many_arguments(
    arg1, arg2, arg3,
    arg4, arg5, arg6
)
```

#### Import ordering
```python
# Bad
from myapp import something
import os
from third_party import lib

# Good (auto-fixed by isort)
import os

from third_party import lib

from myapp import something
```

---

## Frontend (JavaScript/React)

### Tools Used

1. **ESLint** - JavaScript/React linting
2. **Prettier** - Code formatting

### Setup

```bash
cd frontend

# Install dependencies (includes linting tools)
npm install

# Or install globally
npm install -g eslint prettier
```

### Running Linters

```bash
# ESLint
npm run lint          # Check all files
npm run lint:fix      # Auto-fix issues

# Prettier
npm run format        # Format all files
npm run format:check  # Check without modifying
```

### Manual Commands

```bash
# ESLint
npx eslint src                    # Check all source files
npx eslint src/App.jsx            # Check specific file
npx eslint src --fix              # Auto-fix issues

# Prettier
npx prettier --write "src/**/*.{js,jsx,json,css}"   # Format all
npx prettier --check "src/**/*.{js,jsx,json,css}"   # Check only
npx prettier --write src/App.jsx                     # Format specific file
```

### Configuration Files

- **`.eslintrc.cjs`** - ESLint configuration
  - React 18.2 rules
  - Hooks rules enabled
  - Max warnings: 0 (no warnings allowed)

- **`.prettierrc`** - Prettier configuration
  - Single quotes for JS
  - 100 char line width
  - 2 space indentation
  - Semicolons enabled

- **`.prettierignore`** - Files to exclude from formatting

### Common Issues & Fixes

#### Unused variables
```javascript
// Bad
const MyComponent = ({ data, unused }) => {
  return <div>{data}</div>;
};

// Good - prefix with underscore if intentionally unused
const MyComponent = ({ data, _unused }) => {
  return <div>{data}</div>;
};
```

#### Missing dependencies in useEffect
```javascript
// Bad
useEffect(() => {
  fetchData(userId);
}, []); // Missing userId dependency

// Good
useEffect(() => {
  fetchData(userId);
}, [userId]);
```

#### Console statements
```javascript
// Bad in production
console.log('Debug info');

// Good - use proper logging or remove
console.error('Error occurred:', error);  // Allowed
console.warn('Warning:', message);        // Allowed
```

---

## CI/CD Integration

Linters run automatically in the CI pipeline on every push and pull request.

### Workflow Steps

1. **Code Quality Job** (`.github/workflows/ci.yml`)
   - Runs all Python linters
   - Runs all JavaScript linters
   - Uploads security reports as artifacts

2. **Failure Handling**
   - Python linting: Fails build on errors
   - JavaScript linting: Fails build on errors
   - Security scans: Continue on error (warns only)

### Bypassing CI (Not Recommended)

```bash
# Skip linting in CI (NOT RECOMMENDED)
git commit -m "fix: urgent hotfix" --no-verify
```

**Note:** Linting failures in CI must be fixed before merging.

---

## Quick Commands

### Backend Quick Reference

```bash
cd backend

# Check everything
make lint

# Fix auto-fixable issues
make format

# Individual checks
make lint-flake8    # Style
make lint-black     # Format
make lint-isort     # Imports
make lint-bandit    # Security
```

### Frontend Quick Reference

```bash
cd frontend

# Check everything
npm run lint && npm run format:check

# Fix auto-fixable issues
npm run lint:fix && npm run format

# Individual checks
npm run lint         # Code quality
npm run format:check # Formatting
```

### Pre-commit Checks (Recommended)

```bash
# Backend
cd backend && make lint && make test-fast

# Frontend
cd frontend && npm run lint && npm test

# Or run from root for both
cd backend && make lint && cd ../frontend && npm run lint
```

---

## Configuration Files

### Backend

```
backend/
├── .flake8              # Flake8 config
├── pyproject.toml       # Black, isort, Pylint, Bandit config
├── requirements.txt     # Includes linter dependencies
└── Makefile            # Convenience commands
```

### Frontend

```
frontend/
├── .eslintrc.cjs       # ESLint config
├── .prettierrc         # Prettier config
├── .prettierignore     # Prettier exclusions
└── package.json        # Scripts and dependencies
```

---

## Best Practices

### 1. **Run Linters Before Committing**
```bash
# Backend
cd backend && make lint

# Frontend
cd frontend && npm run lint
```

### 2. **Use Auto-Formatting**
```bash
# Backend
make format

# Frontend
npm run format
```

### 3. **Fix Security Issues Immediately**
- Bandit flags are security risks
- Safety warnings indicate vulnerable dependencies
- Update packages: `pip install --upgrade <package>`

### 4. **Configure Your IDE**
- **VS Code**: Install ESLint and Prettier extensions
- **PyCharm**: Enable Black and Flake8 integrations
- **Vim/Neovim**: Use ALE or CoC plugins

### 5. **Incremental Adoption**
If fixing all issues at once is overwhelming:
```bash
# Fix one file at a time
black main.py
flake8 main.py
# Fix issues, commit, repeat
```

---

## Troubleshooting

### "Command not found: flake8"
```bash
# Ensure you're in the virtual environment
source venv/bin/activate  # Linux/Mac
.\venv\Scripts\activate   # Windows

# Or install globally (not recommended)
pip install --user flake8
```

### "Module not found in pylint"
```bash
# Run pylint in the same environment as your app
source venv/bin/activate
pylint main.py
```

### ESLint/Prettier conflicts
- Already handled via `eslint-config-prettier`
- If issues persist, Prettier takes precedence
- Run `npm run format` after `npm run lint:fix`

### Too many linter errors
```bash
# Backend: Fix formatting first (easiest)
make format

# Then tackle remaining issues
make lint-flake8

# Frontend: Auto-fix what's possible
npm run lint:fix
npm run format
```

---

## Additional Resources

- **Flake8**: https://flake8.pycqa.org/
- **Black**: https://black.readthedocs.io/
- **isort**: https://pycqa.github.io/isort/
- **Pylint**: https://pylint.pycqa.org/
- **Bandit**: https://bandit.readthedocs.io/
- **ESLint**: https://eslint.org/
- **Prettier**: https://prettier.io/

---

## Summary

✅ **Backend**: Flake8 + Black + isort + Bandit + Safety  
✅ **Frontend**: ESLint + Prettier  
✅ **CI/CD**: Automated checks on every push  
✅ **Commands**: `make lint` (backend), `npm run lint` (frontend)  
✅ **Auto-fix**: `make format` (backend), `npm run format` (frontend)

**Remember**: Linters are your friends! They catch bugs before they reach production. 🐛→💥→✅

