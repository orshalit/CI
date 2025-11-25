#!/bin/bash
# Quick activation helper for the virtual environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PATH="$SCRIPT_DIR/venv"

if [ ! -d "$VENV_PATH" ]; then
    echo "❌ Virtual environment not found at: $VENV_PATH"
    echo ""
    echo "Please create it first by running:"
    echo "  ./setup-venv.sh"
    echo "  or: make venv"
    exit 1
fi

echo "✓ Activating virtual environment..."
source "$VENV_PATH/bin/activate"

echo ""
echo "🐍 Virtual environment activated!"
echo ""
echo "Quick commands:"
echo "  make test       - Run tests"
echo "  make test-cov   - Run tests with coverage"
echo "  make help       - See all available commands"
echo "  deactivate      - Exit virtual environment"
echo ""

