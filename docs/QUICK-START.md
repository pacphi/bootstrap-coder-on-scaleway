# Quick Start

Two-phase deployment architecture, manual deployment, GitHub Actions setup, and deployment phases explained.

> **Important**: Ensure you've completed all [Prerequisites](PREREQUISITES.md) before proceeding.

## Two-Phase Deployment Architecture

This project uses a **two-phase deployment strategy** for better reliability and troubleshooting:

- **Phase 1 (Infrastructure)**: Deploy Kubernetes cluster, database, networking, and security
- **Phase 2 (Coder Application)**: Deploy the Coder platform with workspace templates

**Benefits**: Infrastructure failures don't block cluster access, better separation of concerns, independent retry capability, and immediate kubeconfig access for troubleshooting.

## Manual Deployment

Deploy your first Coder environment in minutes:

```bash
# 1. Verify prerequisites are met
./scripts/test-runner.sh --suite=prerequisites

# 2. Deploy complete environment (both phases automatically)
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# 🎉 Your Coder instance will be available at the provided URL
# 💡 First deployment takes ~10-15 minutes
```

## GitHub Actions Deployment

Deploy using GitHub Actions with automated two-phase workflow:

```bash
# Prerequisites: GitHub CLI (gh) must be installed
# Fork the repository and configure secrets
gh repo fork pacphi/bootstrap-coder-on-scaleway
gh secret set SCW_ACCESS_KEY --body "your-access-key"
gh secret set SCW_SECRET_KEY --body "your-secret-key"
gh secret set SCW_DEFAULT_PROJECT_ID --body "your-project-id"
gh secret set SCW_DEFAULT_ORGANIZATION_ID --body "your-organziation-id"

# Deploy complete environment (both phases)
gh workflow run deploy-environment.yml \
  -f environment=dev \
  -f template=python-django-crewai \
  -f enable_monitoring=true

# Or deploy infrastructure only for troubleshooting
gh workflow run deploy-infrastructure.yml \
  -f environment=dev

# Monitor deployment progress
gh run watch
```

## What Happens Next?

**Phase 1 - Infrastructure Deployment (~10 min)**:

- ✅ Kubernetes cluster creation with auto-scaling
- ✅ Managed PostgreSQL database provisioning
- ✅ VPC networking and security groups
- ✅ Load balancer and SSL configuration
- ✅ **Kubeconfig uploaded for immediate cluster access**

**Phase 2 - Coder Application Deployment (~5 min)**:

- ✅ Coder platform installation and configuration
- ✅ OAuth integration and user management
- ✅ Workspace template deployment (if specified)
- ✅ Final health checks and validation

> **Key Advantage**: If Phase 2 fails, you still have full cluster access via kubeconfig to troubleshoot and retry Coder deployment independently.
