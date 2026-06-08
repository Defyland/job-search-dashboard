# CI/CD

This project uses two GitHub Actions workflows:

- `CI`: runs on pull requests and pushes to `main`.
- `Deploy Railway`: runs after `CI` succeeds on `main`.

Deploys are intentionally gated by CI. A commit only reaches Railway when tests,
lint, and security checks pass.

## CI

The CI workflow runs:

- Brakeman
- bundler-audit
- importmap audit
- RuboCop
- Rails tests
- Rails system tests

System test failure screenshots are uploaded as artifacts.

## Railway deploy

The deploy workflow publishes both Railway services in order:

1. `web`
2. `worker`

The order avoids concurrent deploys running the same Rails predeploy command at
the same time.

After deploying, the workflow polls `/up` on the production web service.

## GitHub repository variables

These repository variables are required:

- `RAILWAY_PROJECT_ID`
- `RAILWAY_ENVIRONMENT`
- `RAILWAY_WEB_SERVICE`
- `RAILWAY_WORKER_SERVICE`
- `RAILWAY_HEALTHCHECK_URL`

Current production values:

- `RAILWAY_ENVIRONMENT=production`
- `RAILWAY_WEB_SERVICE=web`
- `RAILWAY_WORKER_SERVICE=worker`
- `RAILWAY_HEALTHCHECK_URL=https://web-production-b2243.up.railway.app/up`

## GitHub repository secret

This repository secret is required:

- `RAILWAY_API_TOKEN`

Use an account/workspace-scoped Railway API token because the workflow links the
project, environment, and service before deploying:

```bash
gh secret set RAILWAY_API_TOKEN --repo Defyland/job-search-dashboard
```

The application runtime secrets stay in Railway. Do not copy app variables such
as database credentials, admin password, Rails master key, or provider API keys
into GitHub Actions unless a workflow explicitly needs them.
