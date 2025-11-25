#!/bin/bash
# Local CI simulation script
# Run this before pushing to ensure code passes CI checks

set -e  # Exit on any error

echo "=========================================="
echo "Running local CI simulation..."
echo "=========================================="
echo ""

# Check versions first
echo "1. Checking tool versions..."
python3 --version | grep -q "3.11" || { echo "ERROR: Python 3.11 required"; exit 1; }
node --version | grep -q "v20" || { echo "ERROR: Node 20 required"; exit 1; }
echo "✓ Versions OK"
echo ""

# Backend checks
echo "2. Running backend checks..."
cd backend

# Activate venv if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo "Creating virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
fi

echo "  - Installing dependencies..."
pip install -r requirements.txt > /dev/null 2>&1

echo "  - Running Ruff linter..."
ruff check . --output-format=github || { echo "❌ Ruff check failed"; exit 1; }

echo "  - Checking Black formatting..."
black --check . || { echo "❌ Black formatting check failed. Run 'black .' to fix"; exit 1; }

echo "  - Running tests..."
pytest || { echo "❌ Backend tests failed"; exit 1; }

cd ..
echo "✓ Backend checks passed"
echo ""

# Frontend checks
echo "3. Running frontend checks..."
cd frontend

echo "  - Installing dependencies..."
npm ci > /dev/null 2>&1

echo "  - Running ESLint..."
npm run lint || { echo "❌ ESLint check failed"; exit 1; }

echo "  - Checking Prettier formatting..."
npm run format:check || { echo "❌ Prettier formatting check failed. Run 'npm run format' to fix"; exit 1; }

echo "  - Running tests..."
npm test || { echo "❌ Frontend tests failed"; exit 1; }

cd ..
echo "✓ Frontend checks passed"
echo ""

echo "=========================================="
echo "✓ All CI checks passed locally!"
echo "=========================================="

