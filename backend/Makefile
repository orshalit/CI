.PHONY: help venv install test test-unit test-integration test-cov test-fast
.PHONY: lint lint-ruff lint-black lint-security lint-bandit lint-safety
.PHONY: format fix clean clean-venv

# Default target
help:
	@echo "Available commands:"
	@echo ""
	@echo "Environment:"
	@echo "  make venv             - Create and setup virtual environment"
	@echo "  make install          - Install dependencies (in active venv)"
	@echo ""
	@echo "Testing:"
	@echo "  make test             - Run all tests"
	@echo "  make test-unit        - Run unit tests only"
	@echo "  make test-integration - Run integration tests only"
	@echo "  make test-fast        - Run fast tests (exclude slow tests)"
	@echo "  make test-cov         - Run tests with coverage report"
	@echo ""
  @echo "Code Quality:"
	@echo "  make lint             - Run all linters (Ruff + Black) ⚡"
	@echo "  make lint-ruff        - Run Ruff linter"
	@echo "  make lint-black       - Check formatting with Black"
	@echo "  make lint-security    - Run security scans (Bandit + Safety)"
	@echo "  make lint-bandit      - Run Bandit security scan"
	@echo "  make lint-safety      - Check dependency security"
	@echo "  make format           - Auto-format code (Black + Ruff)"
	@echo "  make fix              - Fix all auto-fixable issues"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean            - Clean generated files"
	@echo "  make clean-venv       - Remove virtual environment"

# Create and setup virtual environment
venv:
	@if [ ! -d "venv" ]; then \
		echo "Creating virtual environment..."; \
		python3 -m venv venv; \
		echo "Virtual environment created!"; \
		echo ""; \
		echo "To activate it, run:"; \
		echo "  source venv/bin/activate"; \
		echo ""; \
		echo "Then run 'make install' to install dependencies."; \
	else \
		echo "Virtual environment already exists at ./venv"; \
		echo "To activate it, run: source venv/bin/activate"; \
	fi

# Install dependencies
install:
	@if [ -z "$$VIRTUAL_ENV" ]; then \
		echo "Warning: No virtual environment detected!"; \
		echo "It's recommended to activate venv first: source venv/bin/activate"; \
		echo ""; \
	fi
	pip install -r requirements.txt

# Run all tests
test:
	pytest tests/

# Run unit tests only
test-unit:
	pytest -m unit tests/

# Run integration tests only  
test-integration:
	pytest -m integration tests/

# Run fast tests (exclude slow tests)
test-fast:
	pytest -m "not slow" tests/

# Run tests with coverage
test-cov:
	pytest --cov=. --cov-report=html --cov-report=term tests/

# Run specific test file
test-file:
	@echo "Usage: make test-file FILE=tests/test_main.py"
	@if [ -z "$(FILE)" ]; then echo "Error: FILE parameter is required"; exit 1; fi
	pytest -v $(FILE)

# Run all linters (FAST - using Ruff)
lint:
	@echo "Running Ruff ⚡ (replaces Flake8, Pylint, isort)..."
	ruff check .
	@echo ""
	@echo "Running Black check..."
	black --check .
	@echo ""
	@echo "✅ All linters passed!"

# Run individual linters
lint-ruff:
	ruff check .

lint-black:
	black --check .

# Security scans (slower - run as needed or nightly in CI)
lint-security:
	@echo "Running Bandit security scan..."
	bandit -r . -f screen
	@echo ""
	@echo "Checking dependencies with Safety..."
	safety check

lint-bandit:
	bandit -r . -f screen

lint-safety:
	safety check

# Format code automatically
format:
	@echo "Formatting code with Black..."
	black .
	@echo "Fixing auto-fixable issues with Ruff..."
	ruff check --fix .
	@echo "✨ Code formatted!"

# Fix all auto-fixable issues
fix:
	ruff check --fix .
	black .

# Clean generated files
clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .coverage -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name htmlcov -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.db" -delete

# Remove virtual environment
clean-venv:
	@if [ -d "venv" ]; then \
		echo "Removing virtual environment..."; \
		rm -rf venv; \
		echo "Virtual environment removed!"; \
	else \
		echo "No virtual environment found."; \
	fi

