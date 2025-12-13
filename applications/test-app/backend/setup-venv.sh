#!/bin/bash
# Setup script for CI Backend Virtual Environment
# Uses uv for fast dependency management

set -e  # Exit on any error

echo "=========================================="
echo "CI Backend - Virtual Environment Setup"
echo "=========================================="
echo ""

# Install uv if not present
if ! command -v uv &> /dev/null; then
    echo "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "✓ uv installed"
else
    echo "✓ uv already installed"
fi

echo ""

# Navigate to backend directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Remove old venv if exists
if [ -d ".venv" ]; then
    echo "Removing old virtual environment..."
    rm -rf .venv
fi

# Create virtual environment using uv
echo "Creating virtual environment with uv..."
uv venv

echo "✓ Virtual environment created"

echo ""

# Install dependencies using uv
echo "Installing Python packages with uv..."
uv sync
echo "✓ Packages installed"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "To activate the virtual environment, run:"
echo "  source .venv/bin/activate"
echo ""
echo "To deactivate, run:"
echo "  deactivate"
echo ""
echo "Note: uv uses .venv by default (not venv)"
echo ""

