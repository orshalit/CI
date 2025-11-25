# CI/CD Pipeline Guide

This document provides a comprehensive guide to the production-grade CI/CD pipeline implemented for this project.

## Overview

The CI/CD pipeline is built using GitHub Actions and provides:

✅ **Continuous Integration**
- Automated testing (unit, integration, E2E)
- Code quality checks
- Security scanning
- Build verification

✅ **Continuous Delivery**
- Automated Docker image building
- Version management
- Artifact publishing
- Release automation

✅ **Quality Gates**
- Test coverage requirements
- Code linting
- Security vulnerability scanning
- Build verification

## Workflow Files

### 1. `ci.yml` - Main CI/CD Pipeline

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`
- Version tags (`v*`)
- Manual workflow dispatch

**Jobs:**

#### a) Code Quality (Runs in parallel)
- Secret scanning (TruffleHog)
- Code linting (Python/JavaScript)
- Security analysis

#### b) Backend Tests (Matrix strategy)
- **Unit Tests:** Fast, isolated tests with coverage
- **Integration Tests:** Full stack with database

#### c) Frontend Tests
- Unit tests with Jest
- Coverage reporting
- React Testing Library tests

#### d) Build Metadata Preparation
- Automatic version detection
- Git metadata extraction
- Build timestamp generation

#### e) Docker Image Building (Matrix strategy)
- Backend and frontend images
- Multi-platform support
- GitHub Container Registry publishing
- Layer caching optimization

#### f) End-to-End Tests
- Full docker-compose deployment
- Health check verification
- API endpoint testing
- Version metadata verification

#### g) Security Scanning
- Trivy vulnerability scanner
- SARIF report upload to GitHub Security

#### h) Release Automation
- Changelog generation
- GitHub release creation
- Artifact publishing

### 2. `pr-validation.yml` - Fast PR Feedback

**Purpose:** Provide quick feedback on pull requests

**Features:**
- Fast unit tests only
- Build verification
- Concurrent cancellation for new commits
- Focused on speed (< 5 minutes)

### 3. `codeql.yml` - Security Analysis

**Purpose:** Advanced security and code quality analysis

**Features:**
- Weekly scheduled scans
- JavaScript and Python analysis
- Security and quality queries
- SARIF integration

## Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Code Push/PR                              │
└──────────────┬──────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 1: Parallel Quality Checks (~ 2-3 min)                   │
├─────────────────────────────────────────────────────────────────┤
│  • Code Quality & Security                                       │
│  • Backend Unit Tests                                            │
│  • Backend Integration Tests                                     │
│  • Frontend Tests                                                │
│  • Build Metadata Preparation                                    │
└──────────────┬──────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 2: Docker Image Building (~ 3-5 min)                     │
├─────────────────────────────────────────────────────────────────┤
│  • Build backend image with metadata                             │
│  • Build frontend image with metadata                            │
│  • Tag with version, commit SHA, branch                          │
│  • Push to registry (if not PR)                                  │
└──────────────┬──────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 3: End-to-End Validation (~ 3-4 min)                     │
├─────────────────────────────────────────────────────────────────┤
│  • Deploy full stack with docker-compose                         │
│  • Wait for health checks                                        │
│  • Run E2E API tests                                             │
│  • Verify version metadata                                       │
│  • Collect logs on failure                                       │
└──────────────┬──────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stage 4: Security & Release (if applicable)                    │
├─────────────────────────────────────────────────────────────────┤
│  • Security scanning (Trivy)                                     │
│  • Create GitHub release (on tag)                                │
│  • Generate changelog                                            │
│  • Publish artifacts                                             │
└─────────────────────────────────────────────────────────────────┘
```

**Total Pipeline Time:** ~10-15 minutes for full run

## Versioning Strategy

### Automatic Version Detection

The pipeline automatically determines versions based on context:

| Trigger | Version Format | Example |
|---------|---------------|---------|
| Git Tag | `{tag}` | `v1.2.3` |
| Main Branch | `main-{commit}` | `main-abc1234` |
| Develop Branch | `develop-{commit}` | `develop-abc1234` |
| Other Branch | `{branch}-{commit}` | `feature-abc1234` |
| PR | `pr-{number}-{commit}` | `pr-42-abc1234` |

### Image Tags

Each build creates multiple Docker image tags:

```bash
# For version v1.2.3:
ghcr.io/username/ci-backend:v1.2.3      # Exact version
ghcr.io/username/ci-backend:v1.2        # Minor version
ghcr.io/username/ci-backend:v1          # Major version
ghcr.io/username/ci-backend:latest      # Latest (main branch)
ghcr.io/username/ci-backend:main-abc123 # Branch + commit
```

## Build Metadata

Every image includes comprehensive metadata:

```json
{
  "version": "v1.2.3",
  "commit": "abc1234",
  "branch": "main",
  "build_date": "2024-01-15T10:30:00Z",
  "python_version": "3.11",
  "environment": "production"
}
```

**Access Methods:**
1. **API:** `curl http://localhost:8000/version`
2. **File:** `docker run --rm image cat /app/version.json`
3. **Labels:** `docker inspect image --format='{{json .Config.Labels}}'`

## Environment Variables

### Required Secrets

Configure these in GitHub Settings → Secrets:

| Secret | Description | Required For |
|--------|-------------|--------------|
| `GITHUB_TOKEN` | Auto-provided by GitHub | Image publishing, releases |
| `CODECOV_TOKEN` | Codecov integration (optional) | Coverage reporting |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PYTHON_VERSION` | Python version | `3.11` |
| `NODE_VERSION` | Node.js version | `20` |
| `DOCKER_BUILDKIT` | Enable BuildKit | `1` |

## Test Coverage

### Coverage Requirements

- **Backend:** Target 90%+ coverage
- **Frontend:** Target 80%+ coverage

### Coverage Reports

Uploaded to:
- GitHub Actions artifacts
- Codecov (optional integration)
- PR comments (with Codecov app)

### View Coverage Locally

```bash
# Backend
cd backend
pytest --cov=. --cov-report=html
open htmlcov/index.html

# Frontend
cd frontend
npm test -- --coverage
open coverage/lcov-report/index.html
```

## Caching Strategy

The pipeline uses multiple caching mechanisms:

### 1. Dependency Caching
```yaml
uses: actions/setup-python@v5
with:
  cache: 'pip'
  cache-dependency-path: backend/requirements.txt
```

### 2. Docker Layer Caching
```yaml
cache-from: type=gha,scope=backend
cache-to: type=gha,mode=max,scope=backend
```

### 3. Build Artifact Caching
- Test results
- Coverage reports
- Build logs

**Cache Benefits:**
- 50-70% faster builds on cache hits
- Reduced GitHub Actions minutes usage
- Faster feedback cycles

## Failure Handling

### Automatic Actions on Failure

1. **Test Failures:**
   - Upload test results as artifacts
   - Generate failure report
   - Link to failed test output

2. **Build Failures:**
   - Capture build logs
   - Show detailed error messages
   - Suggest possible fixes

3. **E2E Failures:**
   - Collect service logs
   - Show docker-compose status
   - Capture health check outputs

### Debugging Failed Builds

```bash
# View failed job logs in GitHub Actions UI

# Download artifacts
gh run download <run-id>

# Re-run specific job
gh run rerun <run-id> --job <job-id>

# Run locally (approximate)
act -j backend-tests  # Using nektos/act
```

## Performance Optimization

### Current Optimizations

1. ✅ **Parallel job execution** - Run tests concurrently
2. ✅ **Matrix strategy** - Test multiple configurations
3. ✅ **Dependency caching** - Pip and npm caches
4. ✅ **Docker layer caching** - GitHub Actions cache
5. ✅ **Selective testing** - Fast unit tests in PRs
6. ✅ **Concurrent cancellation** - Cancel outdated runs

### Timing Breakdown

| Stage | Duration | Can be parallelized |
|-------|----------|-------------------|
| Code Quality | 2-3 min | ✅ Yes |
| Backend Unit Tests | 1-2 min | ✅ Yes |
| Backend Integration Tests | 2-3 min | ✅ Yes |
| Frontend Tests | 1-2 min | ✅ Yes |
| Docker Builds | 3-5 min | ✅ Yes (matrix) |
| E2E Tests | 3-4 min | ❌ No (sequential) |
| Security Scan | 2-3 min | ✅ Yes |

**Total:** ~10-15 minutes with parallelization

## Security Features

### 1. Secret Scanning
- TruffleHog scans for exposed secrets
- Runs on every commit
- Blocks PRs with secrets

### 2. Dependency Scanning
- Trivy scans for vulnerabilities
- SARIF reports to GitHub Security
- Automated security advisories

### 3. CodeQL Analysis
- Weekly security scans
- Advanced code analysis
- Vulnerability detection

### 4. Image Scanning
- Container vulnerability scanning
- Base image analysis
- CVE tracking

## Best Practices

### For Contributors

1. ✅ **Run tests locally** before pushing
   ```bash
   cd backend && pytest -m unit
   cd frontend && npm test
   ```

2. ✅ **Use semantic commit messages**
   ```
   feat: add new endpoint
   fix: resolve race condition
   docs: update API documentation
   test: add integration tests
   ```

3. ✅ **Keep PRs small and focused**
   - < 500 lines of changes
   - Single logical change
   - Comprehensive tests

4. ✅ **Wait for CI to pass** before requesting review

### For Maintainers

1. ✅ **Use protected branches**
   - Require status checks to pass
   - Require code review
   - Enforce linear history

2. ✅ **Tag releases properly**
   ```bash
   git tag -a v1.2.3 -m "Release v1.2.3"
   git push origin v1.2.3
   ```

3. ✅ **Monitor CI metrics**
   - Build success rate
   - Average build time
   - Test coverage trends

4. ✅ **Keep dependencies updated**
   - Regular Dependabot PRs
   - Security patch updates
   - Breaking change reviews

## Monitoring & Metrics

### Key Metrics to Track

1. **Build Success Rate**
   - Target: > 95%
   - Track per branch

2. **Build Duration**
   - Target: < 15 minutes
   - Monitor for regressions

3. **Test Coverage**
   - Backend: > 90%
   - Frontend: > 80%
   - Track trends

4. **Deployment Frequency**
   - Track releases
   - Monitor velocity

### GitHub Actions Insights

View in: Repository → Actions → Insights

- Workflow runs
- Job duration
- Success rates
- Billing usage

## Troubleshooting

### Common Issues

#### 1. Cache Misses
**Symptom:** Builds slower than usual
**Solution:** Check if dependencies changed, cache keys are correct

#### 2. Test Flakiness
**Symptom:** Intermittent test failures
**Solution:** Increase timeouts, add retries, fix race conditions

#### 3. Docker Build Failures
**Symptom:** Image build fails
**Solution:** Check Dockerfile syntax, verify base images

#### 4. Timeout Issues
**Symptom:** Jobs timeout
**Solution:** Increase timeout, optimize slow tests

### Getting Help

1. Check GitHub Actions logs
2. Review failed test output
3. Check Docker build logs
4. Consult documentation
5. Open an issue

## Future Enhancements

### Planned Improvements

- [ ] Automated performance testing
- [ ] Visual regression testing
- [ ] Automated database migrations
- [ ] Blue-green deployments
- [ ] Canary releases
- [ ] A/B testing infrastructure
- [ ] Automated rollback
- [ ] Chaos engineering tests

### Integration Opportunities

- [ ] Slack/Discord notifications
- [ ] Jira integration
- [ ] Datadog monitoring
- [ ] PagerDuty alerts
- [ ] SonarQube code quality
- [ ] Snyk security scanning

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Build Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Semantic Versioning](https://semver.org/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Test Coverage Best Practices](https://testing.googleblog.com/)

## Support

For questions or issues with the CI/CD pipeline:
1. Check this documentation
2. Review workflow files
3. Check GitHub Actions logs
4. Open an issue with `ci` label

