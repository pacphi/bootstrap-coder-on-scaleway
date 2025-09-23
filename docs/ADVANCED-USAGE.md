# Advanced Usage Examples

Complete development workflow, production deployment with monitoring, troubleshooting with two-phase architecture, and CI/CD pipeline integration.

## Environment Structure

The two-phase architecture organizes environments with separate configurations:

```text
environments/
├── dev/
│   ├── infra/          # Phase 1: Infrastructure (cluster, database, networking)
│   │   ├── main.tf
│   │   ├── providers.tf
│   │   └── outputs.tf
│   └── coder/          # Phase 2: Coder application deployment
│       ├── main.tf
│       ├── providers.tf
│       └── outputs.tf
├── staging/
│   ├── infra/
│   └── coder/
└── prod/
    ├── infra/
    └── coder/
```

## Complete Development Workflow

```bash
# 1. Deploy development environment with AI template (two-phase automatic)
./scripts/lifecycle/setup.sh --env=dev --template=claude-flow-base

# 2. Validate deployment
./scripts/validate.sh --env=dev --quick

# 3. Scale for team development
./scripts/scale.sh --env=dev --nodes=4

# 4. Create backup before major changes
./scripts/lifecycle/backup.sh --env=dev --include-workspaces

# 5. Run comprehensive tests
./scripts/test-runner.sh --suite=integration --env=dev
```

## Production Deployment with Monitoring

```bash
# Deploy production with all enterprise features (two-phase automatic)
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=java-spring \
  --enable-monitoring \
  --enable-ha \
  --cost-budget=400

# Validate production readiness
./scripts/validate.sh --env=prod --comprehensive

# Set up automated scaling
./scripts/scale.sh --env=prod --auto --min-nodes=5 --max-nodes=15
```

## Troubleshooting with Two-Phase Architecture

```bash
# If Coder deployment fails, infrastructure is still accessible:

# 1. Use kubeconfig from Phase 1 to investigate
export KUBECONFIG=~/.kube/config-coder-dev
kubectl get pods -n coder
kubectl describe deployment coder -n coder

# 2. Retry only Coder deployment (Phase 2)
gh workflow run deploy-coder.yml -f environment=dev

# 3. Or use manual deployment for Phase 2
cd environments/dev/coder
terraform init && terraform apply
```

## CI/CD Pipeline Integration

```yaml
# GitHub Actions example - Two-Phase Deployment
name: Deploy Staging on PR
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Deploy complete environment (two-phase)
        uses: ./.github/workflows/deploy-environment.yml
        with:
          environment: staging
          template: react-typescript
          enable_monitoring: true
          auto_approve: true
```
