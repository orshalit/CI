# Multi-Application Testing & Quality Support

## Overview

The CI/CD pipeline now fully supports multi-application architecture with:
- ✅ **App-specific tests** (backend and frontend)
- ✅ **App-specific code quality checks**
- ✅ **Dynamic detection** of applications
- ✅ **Modular design** - works out of the box for any new application

---

## What Was Fixed

### 1. **Security Scan Workflow** (`security-scan.yml`)
- ❌ **Before**: Used invalid `exists()` function (caused workflow failures)
- ✅ **After**: Uses `hashFiles()` to check if directories/files exist
- ✅ Now properly scans both shared and app-specific code

### 2. **Change Detection** (`ci.yml`)
- ❌ **Before**: Only detected changes in `backend/` and `frontend/`
- ✅ **After**: Also detects changes in `applications/**`
- ✅ Tests now run when app-specific code changes

### 3. **App-Specific Tests**
- ❌ **Before**: Only tested shared `backend/` and `frontend/`
- ✅ **After**: Dynamically detects and tests all app backends/frontends
- ✅ Each app can have its own test configuration

### 4. **Code Quality Checks**
- ❌ **Before**: Only checked shared code
- ✅ **After**: Scans all app-specific code directories
- ✅ Supports app-specific linting/formatting configs

---

## How It Works

### Dynamic Application Detection

The system automatically detects applications by scanning:
```
applications/
├── legacy/
│   ├── backend/     ← Detected if exists
│   └── frontend/    ← Detected if exists
└── test-app/
    ├── backend/     ← Detected if exists
    └── frontend/    ← Detected if exists
```

### Test Execution Flow

1. **Shared Tests** (always run if shared code changed):
   - `backend/tests/` → Backend unit/integration tests
   - `frontend/tests/` → Frontend tests

2. **App-Specific Tests** (run if app code changed):
   - `applications/{app}/backend/tests/` → App backend tests
   - `applications/{app}/frontend/tests/` → App frontend tests

### Test Requirements

For an app to have its tests run:

**Backend:**
- Directory: `applications/{app}/backend/`
- Tests directory: `applications/{app}/backend/tests/` OR
- Config file: `applications/{app}/backend/pytest.ini`
- Dependencies: `requirements.txt` or `requirements-dev.txt` (optional)

**Frontend:**
- Directory: `applications/{app}/frontend/`
- Package file: `applications/{app}/frontend/package.json`
- Test script: `"test"` in `package.json` scripts (optional)

---

## Example: Adding Tests for a New App

### Backend Tests

1. **Create test directory:**
   ```bash
   mkdir -p applications/my-app/backend/tests
   ```

2. **Add test file:**
   ```python
   # applications/my-app/backend/tests/test_main.py
   import pytest
   
   def test_my_app_feature():
       assert True  # Your test here
   ```

3. **Add pytest config (optional):**
   ```ini
   # applications/my-app/backend/pytest.ini
   [pytest]
   testpaths = tests
   python_files = test_*.py
   ```

4. **That's it!** Tests will run automatically when:
   - Code in `applications/my-app/backend/` changes
   - On version tags
   - Manual workflow dispatch

### Frontend Tests

1. **Ensure package.json has test script:**
   ```json
   {
     "scripts": {
       "test": "jest --coverage"
     }
   }
   ```

2. **Add test files:**
   ```javascript
   // applications/my-app/frontend/src/__tests__/App.test.js
   import { render } from '@testing-library/react';
   import App from '../App';
   
   test('renders app', () => {
     const { getByText } = render(<App />);
     expect(getByText(/my app/i)).toBeInTheDocument();
   });
   ```

3. **That's it!** Tests will run automatically.

---

## Code Quality Checks

### Automatic Scanning

The pipeline automatically scans:

**Python (Backend):**
- Shared: `backend/` → Ruff + Black
- Apps: `applications/*/backend/` → Ruff + Black (with app-specific configs if present)

**JavaScript (Frontend):**
- Shared: `frontend/` → ESLint + Prettier
- Apps: `applications/*/frontend/` → ESLint + Prettier (with app-specific configs if present)

### App-Specific Configs

Each app can have its own configuration:

**Backend:**
- `applications/{app}/backend/ruff.toml` → Custom linting rules
- `applications/{app}/backend/pyproject.toml` → Black/other tool configs

**Frontend:**
- `applications/{app}/frontend/.eslintrc.js` → Custom ESLint rules
- `applications/{app}/frontend/.prettierrc` → Custom Prettier config

If no app-specific config exists, defaults are used.

---

## Workflow Behavior

### When Tests Run

Tests run when:
1. ✅ Code in `applications/{app}/backend/` or `applications/{app}/frontend/` changes
2. ✅ On version tags (`v*`)
3. ✅ Manual workflow dispatch

### When Tests Are Skipped

Tests are skipped when:
- ❌ Only workflow files changed (`.github/workflows/**`)
- ❌ Only documentation changed (`*.md`)
- ❌ Only infrastructure code changed (`DEVOPS/**`)

### Test Results

- **Shared tests**: Uploaded as `backend-test-results-*` and `frontend-test-results`
- **App tests**: Uploaded as `app-backend-test-results` and `app-frontend-test-results`
- **Coverage**: Uploaded to Codecov (shared only, app coverage in artifacts)

---

## Modularity Features

### ✅ Works Out of the Box

- No configuration needed for new apps
- Automatically detects new applications
- Runs tests if test directories exist
- Skips gracefully if no tests found

### ✅ Flexible Test Configurations

- Each app can have different test frameworks
- Supports pytest, jest, vitest, etc.
- App-specific test commands in `package.json`

### ✅ Independent Test Execution

- App tests run in parallel
- One app's test failure doesn't block others
- `continue-on-error: true` for app tests (warnings, not failures)

### ✅ Change-Based Optimization

- Only runs tests for changed apps
- Skips unchanged apps automatically
- Reduces CI time and costs

---

## Current Status

### ✅ Fully Supported

- Shared backend/frontend tests
- App-specific backend tests
- App-specific frontend tests
- Code quality checks (shared + apps)
- Security scanning (shared + apps)
- Dynamic image building

### 📝 Best Practices

1. **Test Structure:**
   ```
   applications/{app}/
   ├── backend/
   │   ├── tests/          ← Tests here
   │   ├── pytest.ini      ← Optional config
   │   └── requirements.txt
   └── frontend/
       ├── src/
       │   └── __tests__/  ← Tests here
       └── package.json    ← Must have test script
   ```

2. **Test Commands:**
   - Backend: Uses `pytest` (detected automatically)
   - Frontend: Uses `npm test` (from package.json)

3. **Dependencies:**
   - Backend: Install from `requirements.txt` or `requirements-dev.txt`
   - Frontend: Install from `package.json` (via `npm ci`)

---

## Troubleshooting

### Tests Not Running

**Check:**
- ✅ Code changed in `applications/{app}/backend/` or `applications/{app}/frontend/`
- ✅ Test directory exists: `applications/{app}/backend/tests/` or `applications/{app}/frontend/src/__tests__/`
- ✅ For frontend: `package.json` has `test` script

### Tests Failing

**Check:**
- ✅ Dependencies installed correctly
- ✅ Test configuration files present
- ✅ Test files follow naming convention (`test_*.py` or `*.test.js`)

### Code Quality Checks Failing

**Check:**
- ✅ Linting/formatting configs are correct
- ✅ Run `ruff check` or `npm run lint` locally first
- ✅ Fix formatting with `black` or `npm run format`

---

## Summary

The system is now **fully modular** and **works out of the box** for multi-application support:

✅ **Automatic detection** of applications  
✅ **App-specific tests** with flexible configurations  
✅ **Code quality checks** for all apps  
✅ **Change-based optimization** (only test what changed)  
✅ **No configuration needed** for new apps  
✅ **Graceful handling** of missing tests/configs  

Just add your app code and tests - the pipeline handles the rest! 🚀

