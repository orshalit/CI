.PHONY: help install install-backend install-frontend lint lint-backend lint-frontend format format-backend format-frontend test test-backend test-frontend ci-local check-versions audit audit-backend audit-frontend clean

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: install-backend install-frontend ## Install all dependencies

install-backend: ## Install Python dependencies (dev)
	@echo "Installing backend dependencies..."
	cd backend && python3 -m venv venv || true
	cd backend && source venv/bin/activate && pip install --upgrade pip && pip install -r requirements-dev.txt

install-frontend: ## Install Node.js dependencies
	@echo "Installing frontend dependencies..."
	cd frontend && npm ci

lint: lint-backend lint-frontend ## Run all linters

lint-backend: ## Run Ruff linter on backend
	@echo "Running Ruff linter..."
	cd backend && source venv/bin/activate && ruff check . --output-format=github

lint-frontend: ## Run ESLint on frontend
	@echo "Running ESLint..."
	cd frontend && npm run lint

format: format-backend format-frontend ## Format all code

format-backend: ## Format Python code with Black and Ruff
	@echo "Formatting backend code..."
	cd backend && source venv/bin/activate && black . && ruff format .

format-frontend: ## Format JavaScript code with Prettier
	@echo "Formatting frontend code..."
	@echo "Note: Requires Node.js 20+. Using Docker if local Node is older..."
	@cd frontend && (npm run format 2>/dev/null || docker run --rm -v $$(pwd):/app -w /app node:20-alpine sh -c 'npm ci && npm run format' || echo "⚠️  Formatting failed. Ensure Node.js 20+ or Docker is available.")

test: test-backend test-frontend ## Run all tests

test-backend: ## Run Python tests
	@echo "Running backend tests..."
	cd backend && source venv/bin/activate && pytest

test-frontend: ## Run JavaScript tests
	@echo "Running frontend tests..."
	cd frontend && npm test

audit: audit-backend audit-frontend ## Run security audit on all dependencies

audit-backend: ## Audit Python dependencies for vulnerabilities
	@echo "Auditing Python dependencies..."
	cd backend && source venv/bin/activate && pip-audit -r requirements.txt --desc on || echo "⚠️  Vulnerabilities found"

audit-frontend: ## Audit Node.js dependencies for vulnerabilities
	@echo "Auditing Node.js dependencies..."
	cd frontend && npm audit --audit-level=high || echo "⚠️  Vulnerabilities found"

check-versions: ## Verify tool versions match CI requirements
	@echo "Checking tool versions..."
	@python3 --version | grep -q "3.11" || (echo "ERROR: Python 3.11 required" && exit 1)
	@node --version | grep -q "v20" || (echo "ERROR: Node 20 required" && exit 1)
	@cd backend && source venv/bin/activate && ruff --version | grep -q "0.14" || (echo "ERROR: Ruff 0.14.x required" && exit 1)
	@echo "All versions match CI requirements ✓"

ci-local: check-versions lint format test ## Run all CI checks locally
	@echo ""
	@echo "✓ All CI checks passed locally!"

clean: ## Clean up generated files and caches
	@echo "Cleaning up..."
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .ruff_cache -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	cd frontend && rm -rf node_modules/.cache 2>/dev/null || true
	@echo "Done!"
