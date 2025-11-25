# Virtual Environment Setup Guide

This guide will help you set up and use a Python virtual environment for the CI backend project.

## Why Use a Virtual Environment?

A virtual environment:
- ✅ Isolates project dependencies from system Python packages
- ✅ Prevents version conflicts between projects
- ✅ Makes deployment more predictable
- ✅ Follows Python best practices
- ✅ Eliminates PATH warnings from pip

## Quick Setup (Recommended)

### Option 1: Automated Setup Script

**From Windows PowerShell:**
```powershell
cd E:\CI\backend
.\setup-venv.bat
```

**From WSL:**
```bash
cd /mnt/e/CI/backend
chmod +x setup-venv.sh
./setup-venv.sh
```

This will:
1. Install `python3-venv` if needed
2. Create the virtual environment
3. Install all requirements
4. Display activation instructions

### Option 2: Using Make

```bash
cd /mnt/e/CI/backend
make venv          # Create virtual environment
source venv/bin/activate  # Activate it
make install       # Install dependencies
```

### Option 3: Manual Setup

```bash
cd /mnt/e/CI/backend

# Create virtual environment
python3 -m venv venv

# Activate it
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt
```

## Using the Virtual Environment

### Activating

**In WSL/Linux:**
```bash
source venv/bin/activate
```

**In Windows PowerShell:** (if using venv in Windows)
```powershell
.\venv\Scripts\Activate.ps1
```

You'll know it's activated when you see `(venv)` at the start of your prompt.

### Deactivating

```bash
deactivate
```

### Checking if Activated

```bash
echo $VIRTUAL_ENV
# Should show the path to your venv directory
```

## Running Commands

Once activated, all commands use the virtual environment's Python:

```bash
# Run tests
pytest tests/

# Or use make commands
make test
make test-cov
make test-unit

# Start the server
uvicorn main:app --reload
```

## Adding New Dependencies

When you add new packages:

```bash
# Install the package
pip install package-name

# Update requirements.txt
pip freeze > requirements.txt
```

## Common Issues

### Issue: `python3-venv` not installed

**Solution:**
```bash
sudo apt update
sudo apt install python3.10-venv
```

### Issue: Scripts not found (uvicorn, pytest, etc.)

**Solution:** Make sure your virtual environment is activated:
```bash
source venv/bin/activate
which pytest  # Should show path in venv/bin/
```

### Issue: Wrong Python version

**Solution:** Specify Python version when creating venv:
```bash
python3.10 -m venv venv
```

## Cleaning Up

### Remove virtual environment
```bash
make clean-venv
# or manually: rm -rf venv
```

### Clean temporary files
```bash
make clean
```

## IDE Integration

### VS Code

Add to `.vscode/settings.json`:
```json
{
  "python.defaultInterpreterPath": "${workspaceFolder}/backend/venv/bin/python",
  "python.terminal.activateEnvironment": true
}
```

### PyCharm

1. File → Settings → Project → Python Interpreter
2. Click gear icon → Add
3. Select "Existing environment"
4. Browse to `backend/venv/bin/python`

## Best Practices

1. ✅ **Always activate** the venv before working on the project
2. ✅ **Never commit** the `venv/` directory to git (it's in `.gitignore`)
3. ✅ **Update requirements.txt** when adding/removing packages
4. ✅ **Use `pip freeze`** carefully - only freeze what you actually use
5. ✅ **Document** any special setup steps for other developers

## CI/CD Integration

The virtual environment works seamlessly with Docker:

```dockerfile
# In Dockerfile
RUN python -m venv venv
RUN . venv/bin/activate && pip install -r requirements.txt
```

The current `Dockerfile` already handles dependencies correctly, so no changes needed there.

## Quick Reference

| Command | Purpose |
|---------|---------|
| `make venv` | Create virtual environment |
| `source venv/bin/activate` | Activate venv |
| `deactivate` | Deactivate venv |
| `make install` | Install dependencies |
| `make test` | Run tests |
| `make clean-venv` | Remove venv |
| `which python` | Check which Python is active |

## Need Help?

- Check if venv is activated: `echo $VIRTUAL_ENV`
- Check Python location: `which python`
- Check pip location: `which pip`
- List installed packages: `pip list`
- Verify requirements: `pip check`

---

**Pro Tip:** Add this alias to your `~/.bashrc` for quick activation:
```bash
alias venv='source venv/bin/activate'
```

Then you can just type `venv` to activate!

