#!/bin/bash
# Setup script for CI Backend Virtual Environment

set -e  # Exit on any error

echo "=========================================="
echo "CI Backend - Virtual Environment Setup"
echo "=========================================="
echo ""

# Check if python3-venv is installed
if ! dpkg -l | grep -q python3.*-venv; then
    echo "Installing python3-venv package..."
    sudo apt update
    sudo apt install -y python3.10-venv
    echo "✓ python3-venv installed"
else
    echo "✓ python3-venv already installed"
fi

echo ""

# Navigate to backend directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Remove old venv if exists
if [ -d "venv" ]; then
    echo "Removing old virtual environment..."
    rm -rf venv
fi

# Create virtual environment
echo "Creating virtual environment..."
python3 -m venv venv

# Ensure pip is available
if [ ! -f "venv/bin/pip" ]; then
    echo "pip not found in venv, installing..."
    venv/bin/python -m ensurepip --upgrade
    venv/bin/python -m pip install --upgrade pip
fi

echo "✓ Virtual environment created"

echo ""

# Activate and install requirements
echo "Installing Python packages..."
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements-dev.txt
echo "✓ Packages installed"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "To activate the virtual environment, run:"
echo "  source venv/bin/activate"
echo ""
echo "To deactivate, run:"
echo "  deactivate"
echo ""


