# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Terraform-based Infrastructure as Code (IaC)** project that deploys enterprise-grade **Coder development environments** on **Scaleway's managed Kubernetes** (Kapsule). The system provides 21+ workspace templates, multi-environment deployment, comprehensive cost management, and AI-enhanced development capabilities.

**Core Technology Stack:**

- **Infrastructure**: Terraform (≥1.13.3) with Scaleway provider
- **Container Platform**: Kubernetes on Scaleway Kapsule with Cilium CNI
- **Application**: Coder development platform with workspace templates
- **Database**: Managed PostgreSQL with environment-specific configurations
- **Orchestration**: Helm for application deployment
- **State Storage**: Remote state using Scaleway Object Storage (S3-compatible)

## Two-Phase Deployment Architecture

The system uses a **two-phase deployment architecture** that separates infrastructure provisioning from application deployment for enhanced reliability and troubleshooting capabilities:

**Phase 1: Infrastructure** (`environments/{env}/infra/`)

- Kubernetes cluster provisioning and configuration
- Database setup with environment-specific sizing
- Networking, load balancers, and security policies
- **Immediate kubeconfig availability** for troubleshooting

**Phase 2: Coder Application** (`environments/{env}/coder/`)

- Coder platform deployment using infrastructure outputs
- Persistent volume claims with validated storage classes
- OAuth integration and ingress configuration
- Workspace template deployment

**Key Benefits:**

- Infrastructure failures don't block cluster access for troubleshooting
- Coder deployment can be retried independently without rebuilding infrastructure
- Clear separation of concerns with dedicated state files
- Better error isolation and recovery capabilities

### Environment Structure

```text
environments/{env}/
├── infra/                    # Phase 1: Infrastructure
│   ├── main.tf              # Cluster, database, networking
│   ├── providers.tf          # Remote state: infra/terraform.tfstate
│   └── outputs.tf            # Kubeconfig, IPs, database info
└── coder/                    # Phase 2: Coder Application
    ├── main.tf               # Coder deployment module
    ├── providers.tf          # Remote state: coder/terraform.tfstate
    └── outputs.tf            # Coder URLs, admin credentials
```

### Multi-Environment Strategy

- **`environments/dev/`**: Cost-optimized (€155.09/month) - 2x GP1-XS nodes, DB-DEV-S
- **`environments/staging/`**: Production-like testing (€694.35/month) - 3x GP1-S nodes, DB-GP-S
- **`environments/prod/`**: High-availability enterprise (€1,992.34/month) - 5x GP1-M nodes, DB-GP-M HA

## Essential Commands

### Two-Phase Environment Management

```bash
# Complete environment deployment (infrastructure + Coder application)
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# Infrastructure only (Phase 1 - for troubleshooting)
./scripts/lifecycle/setup.sh --env=staging --no-coder

# Deploy with monitoring and HA
./scripts/lifecycle/setup.sh --env=prod --enable-monitoring --enable-ha

# Dry run to preview changes
./scripts/lifecycle/setup.sh --env=staging --dry-run

# Complete environment teardown with backup
./scripts/lifecycle/teardown.sh --env=dev --confirm
```

### GitHub Actions Workflows

```bash
# Complete Environment (Two-Phase)
gh workflow run deploy-environment.yml -f environment=dev -f template=python-django-crewai

# Infrastructure Only
gh workflow run deploy-infrastructure.yml -f environment=dev

# Coder Application Only (requires existing infrastructure)
gh workflow run deploy-coder.yml -f environment=dev -f template=java-spring
```

### Remote State Management

```bash
# Setup remote state backend (auto-provisioned in CI/CD)
./scripts/utils/setup-backend.sh --env=dev

# Migrate existing local state to remote backend
./scripts/utils/migrate-state.sh --env=dev --dry-run

# State management operations
./scripts/utils/state-manager.sh show --env=dev
./scripts/utils/state-manager.sh backup --env=staging
./scripts/utils/state-manager.sh drift --env=prod
```

### Cost Management

```bash
# Real-time cost analysis for all environments
./scripts/utils/cost-calculator.sh --env=all

# Set budget alerts with thresholds
./scripts/utils/cost-calculator.sh --env=prod --set-budget=400 --alert-threshold=80

# Generate detailed cost report
./scripts/utils/cost-calculator.sh --env=staging --format=json --detailed
```

### Testing and Validation

```bash
# Run comprehensive validation suite
./scripts/test-runner.sh --suite=all

# Quick health check for specific environment
./scripts/validate.sh --env=prod --quick

# Check prerequisites
./scripts/test-runner.sh --suite=prerequisites
```

### Terraform Operations

```bash
# Two-Phase Structure Operations

# Phase 1: Infrastructure
cd environments/dev/infra
terraform plan && terraform apply
terraform output  # Get kubeconfig, IPs, database info

# Phase 2: Coder Application
cd environments/dev/coder
terraform plan && terraform apply
terraform output  # Get Coder URLs, admin credentials
```

## Prerequisites and Environment Variables

> **Detailed setup instructions:** See [docs/PREREQUISITES.md](docs/PREREQUISITES.md)

**Required Tools**: Terraform ≥1.13.3, kubectl ≥1.32.0, Helm ≥3.12.0, jq

**Environment Variables:**

```bash
# Scaleway credentials (required)
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"

# For Terraform S3 backend
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"
```

## Key Development Patterns

### Infrastructure Changes

1. Always run `terraform plan` before applying changes
2. Use environment-specific configurations in `environments/{env}/`
3. Test changes in development environment first
4. Validate cost impact using `cost-calculator.sh` before deployment
5. Use remote state for all environments to enable team collaboration
6. Create state backups before major infrastructure changes

### Two-Phase Troubleshooting

1. **Phase 1 failure**: No cluster access available - check Scaleway console and retry complete deployment
2. **Phase 2 failure**: Infrastructure accessible via kubeconfig - troubleshoot Coder deployment independently:

   ```bash
   export KUBECONFIG=~/.kube/config-coder-{env}
   kubectl get storageclass  # Verify scw-bssd storage class exists
   kubectl get pvc -n coder  # Check persistent volume claims
   ```

### Template Development

1. Follow existing template patterns in `templates/` directories
2. Test templates using `test-runner.sh --suite=templates`
3. Ensure container images are properly tagged and available

### Security Practices

1. Never commit secrets or credentials to the repository
2. Use Kubernetes secrets for sensitive data
3. Apply appropriate Pod Security Standards based on environment

## Template System

The project includes 21+ workspace templates across six categories:

- **Backend** (7): Java Spring, Python Django+CrewAI, Go Fiber, Ruby Rails, PHP Symfony, Rust Actix, .NET Core
- **Frontend** (4): React+TypeScript, Angular, Vue+Nuxt, Svelte Kit
- **AI-Enhanced** (2): Claude Code Flow Base/Enterprise with 87 MCP tools
- **DevOps** (3): Docker Compose, Kubernetes+Helm, Terraform+Ansible
- **Data/ML** (2): Jupyter+Python, R Studio
- **Mobile** (3): Flutter, React Native, Ionic

> **Complete template guide:** See [docs/TEMPLATES.md](docs/TEMPLATES.md)

## Quick Troubleshooting

### Common Issues

```bash
# Two-Phase deployment failures
# Phase 1: Check infrastructure logs and retry complete deployment
# Phase 2: Use kubeconfig to troubleshoot Coder independently

# Template deployment failures
./scripts/test-runner.sh --suite=templates --template=<name>

# Cost overruns
./scripts/utils/cost-calculator.sh --env=all --detailed
./scripts/scale.sh --env=<env> --nodes=<count> --analyze-cost

# State management issues
./scripts/utils/state-manager.sh show --env=<env>
./scripts/utils/migrate-state.sh --env=<env> --dry-run
```

### Log Locations

- **Setup logs**: `/logs/setup/<timestamp>-<env>-setup.log`
- **Infrastructure state**: Remote in Scaleway Object Storage (`<env>/infra/terraform.tfstate`)
- **Coder application state**: Remote in Scaleway Object Storage (`<env>/coder/terraform.tfstate`)
- **Kubeconfig**: `~/.kube/config-coder-<env>`
- **Application logs**: `kubectl logs -f deployment/coder -n coder`

> **Complete troubleshooting guide:** See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## Comprehensive Documentation

For detailed information, see the complete documentation in the `docs/` directory:

- **[Quick Start Guide](docs/QUICK-START.md)** - Two-phase deployment walkthrough
- **[Usage Guide](docs/USAGE.md)** - Comprehensive examples and workflows
- **[Architecture Guide](docs/ARCHITECTURE.md)** - System design and components
- **[Feature Comparison](docs/FEATURES.md)** - Deployment methods comparison
- **[Management Scripts](docs/MANAGEMENT-SCRIPTS.md)** - Complete script reference
- **[Workflows Guide](docs/WORKFLOWS.md)** - GitHub Actions automation
- **[Hooks Framework](docs/HOOKS-FRAMEWORK.md)** - Custom automation and integrations

This project combines enterprise-grade infrastructure automation with modern development practices, providing a complete solution for scalable development environments on Scaleway's cloud platform.
