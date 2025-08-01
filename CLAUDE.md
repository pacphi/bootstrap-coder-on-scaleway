# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Terraform-based Infrastructure as Code (IaC)** project that deploys enterprise-grade **Coder development environments** on **Scaleway's managed Kubernetes** (Kapsule). The system provides 21+ workspace templates, multi-environment deployment, comprehensive cost management, and AI-enhanced development capabilities.

## Core Technology Stack

- **Infrastructure**: Terraform (≥1.12.0) with Scaleway provider
- **State Storage**: Remote state using Scaleway Object Storage (S3-compatible)
- **Container Platform**: Kubernetes on Scaleway Kapsule with Cilium CNI
- **Application**: Coder development platform with workspace templates
- **Database**: Managed PostgreSQL with environment-specific configurations
- **Orchestration**: Helm for application deployment
- **Automation**: Bash scripts for lifecycle management and operations

## Architecture Overview

### Two-Phase Deployment Strategy
The system uses a **two-phase deployment architecture** that separates infrastructure provisioning from application deployment:

**Phase 1: Infrastructure** (`environments/{env}/infra/`)
- Kubernetes cluster provisioning and configuration
- Database setup with environment-specific sizing
- Networking, load balancers, and security policies
- Immediate kubeconfig availability for troubleshooting

**Phase 2: Coder Application** (`environments/{env}/coder/`)
- Coder platform deployment using infrastructure outputs
- Persistent volume claims with validated storage classes
- OAuth integration and ingress configuration
- Workspace template deployment

### Multi-Environment Strategy
- **`environments/dev/`**: Cost-optimized (€53.70/month) - 2x GP1-XS nodes, DB-DEV-S
- **`environments/staging/`**: Production-like testing (€97.85/month) - 3x GP1-S nodes, DB-GP-S
- **`environments/prod/`**: High-availability enterprise (€374.50/month) - 5x GP1-M nodes, DB-GP-M HA

### Environment Structure
```
environments/{env}/
├── infra/                    # Phase 1: Infrastructure
│   ├── main.tf              # Cluster, database, networking
│   ├── variables.tf          # Infrastructure variables
│   ├── outputs.tf            # Kubeconfig, IPs, database info
│   └── providers.tf          # Remote state: infra/terraform.tfstate
└── coder/                    # Phase 2: Coder Application
    ├── main.tf               # Coder deployment module
    ├── variables.tf          # Application variables
    ├── outputs.tf            # Coder URLs, admin credentials
    └── providers.tf          # Remote state: coder/terraform.tfstate
```

### Modular Infrastructure
- **`modules/scaleway-cluster/`**: Kubernetes cluster management with auto-scaling
- **`modules/networking/`**: VPC, security groups, load balancers
- **`modules/postgresql/`**: Database provisioning with HA and backup configuration
- **`modules/coder-deployment/`**: Coder platform deployment with OAuth and ingress
- **`modules/security/`**: RBAC, Pod Security Standards, network policies
- **`modules/terraform-backend/`**: Remote state storage using Scaleway Object Storage

### Benefits of Two-Phase Architecture
- **Faster Troubleshooting**: Kubeconfig available immediately after Phase 1
- **Independent Retries**: Coder deployment can be retried without rebuilding infrastructure
- **Better Separation**: Clear distinction between infrastructure and application concerns
- **Reduced Blast Radius**: Phase 2 failures don't affect infrastructure accessibility

### Template System (21+ Templates)
- **Backend** (7): Java Spring, Python Django+CrewAI, Go Fiber, Ruby Rails, PHP Symfony, Rust Actix, .NET Core
- **Frontend** (4): React+TypeScript, Angular, Vue+Nuxt, Svelte Kit
- **AI-Enhanced** (2): Claude Code Flow Base/Enterprise with 87 MCP tools
- **DevOps** (3): Docker Compose, Kubernetes+Helm, Terraform+Ansible
- **Data/ML** (2): Jupyter+Python, R Studio
- **Mobile** (3): Flutter, React Native, Ionic

## Essential Commands

### Environment Management

```bash
# Two-Phase Deployment (Recommended)
# Deploy complete environment (infrastructure + Coder application)
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# Deploy infrastructure only (Phase 1 - for troubleshooting)
./scripts/lifecycle/setup.sh --env=staging --no-coder

# Deploy production with monitoring and HA
./scripts/lifecycle/setup.sh --env=prod --enable-monitoring

# Dry run to preview changes
./scripts/lifecycle/setup.sh --env=staging --dry-run

# Complete environment teardown with backup
./scripts/lifecycle/teardown.sh --env=dev --confirm
```

### GitHub Actions Workflows

```bash
# Method 1: Complete Environment (Two-Phase)
# Uses: deploy-environment.yml
# Deploys: Infrastructure (Phase 1) → Coder Application (Phase 2)

# Method 2: Infrastructure Only
# Uses: deploy-infrastructure.yml
# Deploys: Only infrastructure, provides kubeconfig for manual Coder deployment

# Method 3: Coder Application Only
# Uses: deploy-coder.yml
# Deploys: Only Coder application (requires existing infrastructure)
```

### Remote State Management

```bash
# Manual setup of remote state backend infrastructure (optional - auto-provisioned in CI/CD)
./scripts/utils/setup-backend.sh --env=dev
./scripts/utils/setup-backend.sh --env=all  # Setup all environments

# Migrate existing local state to remote backend (if migrating from local state)
./scripts/utils/migrate-state.sh --env=dev
./scripts/utils/migrate-state.sh --env=prod --verbose

# State management operations
./scripts/utils/state-manager.sh show --env=dev
./scripts/utils/state-manager.sh list --env=prod --format=json
./scripts/utils/state-manager.sh backup --env=staging
./scripts/utils/state-manager.sh drift --env=prod
```

**Note**: Remote state backend infrastructure is now **automatically provisioned** during GitHub Actions workflows. Manual setup is only needed for local development or troubleshooting.

### Cost Management and Analysis

```bash
# Real-time cost analysis for all environments
./scripts/utils/cost-calculator.sh --env=all

# Set budget alerts with thresholds
./scripts/utils/cost-calculator.sh --env=prod --set-budget=400 --alert-threshold=80

# Generate detailed cost report in JSON format
./scripts/utils/cost-calculator.sh --env=staging --format=json --detailed
```

### Testing and Validation

```bash
# Run comprehensive validation suite
./scripts/test-runner.sh --suite=all

# Quick health check for specific environment
./scripts/validate.sh --env=prod --quick

# Validate specific test suites
./scripts/test-runner.sh --suite=smoke,templates --format=json

# Check prerequisites
./scripts/test-runner.sh --suite=prerequisites
```

### Scaling and Resource Management

```bash
# Scale cluster with cost analysis
./scripts/scale.sh --env=prod --nodes=8 --analyze-cost

# Auto-scale based on workload metrics
./scripts/scale.sh --env=staging --auto --target-cpu=70

# Analyze scaling recommendations only
./scripts/scale.sh --env=prod --analyze-only
```

### Backup and Recovery

```bash
# Complete environment backup with data
./scripts/lifecycle/backup.sh --env=prod --include-all

# Pre-destroy backup with retention policy
./scripts/lifecycle/backup.sh --env=staging --pre-destroy --retention-days=90
```

### Terraform Operations

```bash
# Two-Phase Structure Operations

# Phase 1: Infrastructure Operations
cd environments/dev/infra
terraform plan    # Plan infrastructure changes
terraform apply   # Apply infrastructure changes
terraform output  # Get kubeconfig, IPs, database info

# Phase 2: Coder Application Operations
cd environments/dev/coder
terraform plan    # Plan Coder application changes
terraform apply   # Apply Coder application changes
terraform output  # Get Coder URLs, admin credentials

# Legacy Structure Operations (backward compatibility)
cd environments/dev
terraform plan    # Plan all changes (infrastructure + Coder)
terraform apply   # Apply all changes
terraform show    # Check current state
```

### Kubernetes Management

```bash
# Set kubeconfig for specific environment
export KUBECONFIG=~/.kube/config-coder-dev

# Check cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Monitor Coder deployment
kubectl get pods -n coder
kubectl logs -f deployment/coder -n coder

# Check resource usage
kubectl top nodes
kubectl top pods -A
```

## Configuration Files Structure

### Two-Phase Environment Structure (Current)
Each `environments/{env}/` directory contains:

**Infrastructure Phase** (`infra/`):
- **`main.tf`**: Cluster, database, networking, security modules
- **`variables.tf`**: Infrastructure-specific variables
- **`providers.tf`**: Remote state backend (`infra/terraform.tfstate`)
- **`outputs.tf`**: Kubeconfig, load balancer IPs, database connection

**Coder Application Phase** (`coder/`):
- **`main.tf`**: Coder deployment module with infrastructure remote state
- **`variables.tf`**: Application-specific variables
- **`providers.tf`**: Remote state backend (`coder/terraform.tfstate`)
- **`outputs.tf`**: Coder URLs, admin credentials, namespace info

### Legacy Environment Structure (Backward Compatible)
Each `environments/{env}/` directory contains:
- **`main.tf`**: All resource definitions (infrastructure + Coder)
- **`providers.tf`**: Provider configurations with backend state
- **`outputs.tf`**: All environment outputs (URLs, connection strings)

### Shared Configuration
- **`shared/variables.tf`**: Common variables across environments
- **`shared/locals.tf`**: Environment-specific computed values
- **`shared/providers.tf`**: Terraform provider configurations
- **`shared/versions.tf`**: Version constraints and requirements

## Prerequisites and Setup

### Required Tools and Versions
- **Terraform** ≥1.12.0
- **kubectl** ≥1.32.0
- **Helm** ≥3.12.0
- **Git** for version control
- **jq** for JSON processing in scripts

### Environment Variables
```bash
# Scaleway credentials (required)
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"

# Required for Terraform S3 backend (uses Scaleway credentials)
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"

# Optional: Default region and zone
export SCW_DEFAULT_REGION="fr-par"
export SCW_DEFAULT_ZONE="fr-par-1"
```

### GitHub Actions Secrets

When using GitHub Actions workflows:

**Required Secrets**:
- `SCW_ACCESS_KEY`: Scaleway API access key
- `SCW_SECRET_KEY`: Scaleway API secret key
- `SCW_DEFAULT_PROJECT_ID`: Scaleway project ID
- `SCW_DEFAULT_ORGANIZATION_ID`: Scaleway organization ID

**Optional Feature Flags**:
- `ENABLE_AUTO_STAGING_DEPLOY`: Set to "true" to enable automatic staging deployments on push/PR events. When not set or set to any other value, automatic deployments are disabled while manual deployments continue to work.

## Template Development

### Template Structure
Templates are located in `templates/{category}/{framework}/` and contain:
- **`main.tf`**: Coder template definition with workspace resources
- **`README.md`**: Template documentation and usage instructions
- **Docker configuration**: Container images and build specifications
- **IDE configurations**: VS Code settings, extensions, development tools

### Available Template Categories
- **Backend**: Server-side frameworks with database integration
- **Frontend**: Client-side frameworks with modern tooling
- **AI-Enhanced**: Templates with Claude Code Flow integration (87 MCP tools)
- **DevOps**: Infrastructure and deployment tool templates
- **Data/ML**: Data science and machine learning environments
- **Mobile**: Cross-platform mobile development frameworks

## Hooks Framework

### Custom Automation Points
```bash
# Customize deployment lifecycle
./scripts/hooks/pre-setup.sh    # Before deployment starts
./scripts/hooks/post-setup.sh   # After deployment completes
./scripts/hooks/pre-teardown.sh # Before teardown starts
./scripts/hooks/post-teardown.sh # After teardown completes
```

### Hook Capabilities
- **Slack/Teams notifications** for deployment events
- **External monitoring** system registration
- **Compliance checks** and audit logging
- **User provisioning** and workspace management
- **Custom integrations** with organization-specific tools

## Security and Compliance

### Environment-Specific Security
- **Development**: Basic Pod Security Standards (baseline)
- **Staging**: Enhanced security policies and network policies
- **Production**: Full security enforcement (restricted Pod Security Standards, comprehensive RBAC)

### Security Tools
```bash
# Run security audit on environment
./scripts/utils/security-audit.sh --env=prod --comprehensive

# Apply security remediation
./scripts/utils/security-remediation.sh --env=staging --apply

# Generate security report
./scripts/utils/security-audit.sh --env=all --format=json --output=security-report.json
```

### Secret Management
- **Kubernetes secrets** for database connections and credentials
- **Terraform state encryption** with backend configuration
- **OAuth integration** with GitHub, Google for user authentication

## Monitoring and Observability

### Health Checks
- **Infrastructure**: Terraform state validation and drift detection
- **Application**: Coder deployment health and workspace availability
- **Database**: PostgreSQL connectivity and performance metrics
- **Network**: Load balancer and ingress connectivity

### Cost Monitoring
- **Real-time tracking** with Scaleway pricing API integration
- **Budget alerts** with configurable thresholds
- **Resource optimization** recommendations based on usage patterns
- **Multi-format reporting** (table, JSON, CSV)

## Troubleshooting Guide

### Common Issues

**Two-Phase Deployment Issues**
```bash
# Phase 1 failure: Infrastructure deployment failed
# Check infrastructure logs and retry Phase 1 only
cd environments/<env>/infra
terraform plan
terraform apply

# Phase 2 failure: Coder application deployment failed
# Infrastructure is accessible via kubeconfig, retry Phase 2 only
cd environments/<env>/coder
terraform plan
terraform apply

# Check storage classes are ready for PVC creation
kubectl get storageclass
kubectl get pvc -n coder
```

**Template Deployment Failures**
```bash
# Validate template syntax and dependencies
./scripts/test-runner.sh --suite=templates --template=<template-name>
```

**Cost Overruns**
```bash
# Analyze resource usage and costs
./scripts/utils/cost-calculator.sh --env=all --detailed
./scripts/utils/resource-tracker.sh --env=<env> --optimize
```

**Scaling Issues**
```bash
# Check cluster capacity and scaling constraints
./scripts/validate.sh --env=<env> --focus=resources
kubectl describe nodes
```

**Database Connectivity**
```bash
# Two-phase: Check from infrastructure outputs
cd environments/<env>/infra
terraform output database_host

# Check database status and connection
kubectl get secrets -n coder
kubectl exec -it deployment/coder -n coder -- env | grep DB_
```

**Remote State Issues**
```bash
# Backend auto-provisioning issues (check GitHub Actions logs for backend setup job)
# Manual backend creation if auto-provisioning fails
./scripts/utils/setup-backend.sh --env=<env> --verbose

# Ensure AWS environment variables are set for S3 backend
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"

# Check state backend connectivity
./scripts/utils/state-manager.sh show --env=<env>

# Verify backend configuration
cd environments/<env> && terraform init

# Check for state drift
./scripts/utils/state-manager.sh drift --env=<env>

# Create state backup before troubleshooting
./scripts/utils/state-manager.sh backup --env=<env>
```

**State Migration Problems**
```bash
# Dry run migration to preview changes
./scripts/utils/migrate-state.sh --env=<env> --dry-run

# Check migration prerequisites
cd environments/<env> && terraform init -backend=false

# Rollback to local state if needed (see migration backup directory)
ls backups/state-migration/<env>/
```

### Log Locations
- **Setup logs**: `/logs/setup/<timestamp>-<env>-setup.log`
- **Terraform state**: Remote in Scaleway Object Storage (`terraform-state-coder-<env>` bucket)
  - **Infrastructure state**: `infra/terraform.tfstate`
  - **Coder application state**: `coder/terraform.tfstate`
- **Local state backup**: `environments/<env>/infra/` and `environments/<env>/coder/` (after migration)
- **State migration logs**: `backups/state-migration/migration-<timestamp>-<env>-*.log`
- **State backups**: `backups/state-backups/<env>-<timestamp>/`
- **Kubeconfig**: `~/.kube/config-coder-<env>`
- **Application logs**: `kubectl logs -f deployment/coder -n coder`

## Key Patterns for Development

### Infrastructure Changes
1. Always run `terraform plan` before applying changes
2. Use environment-specific configurations in `environments/{env}/`
3. Test changes in development environment before promoting to staging/production
4. Validate cost impact using `cost-calculator.sh` before deployment
5. Use remote state for all environments to enable team collaboration
6. Create state backups before major infrastructure changes

### Template Development
1. Follow existing template patterns in `templates/` directories
2. Test templates using `test-runner.sh --suite=templates`
3. Document template requirements and usage in README.md
4. Ensure container images are properly tagged and available

### Security Practices
1. Never commit secrets or credentials to the repository
2. Use Kubernetes secrets for sensitive data
3. Apply appropriate Pod Security Standards based on environment
4. Implement network policies for production environments

### Integration Development
1. All integrations are optional and activated via environment variables
2. Use the comprehensive documentation in `docs/INTEGRATIONS.md`
3. Test integrations using `test-runner.sh --suite=integrations`
4. Follow the patterns in the hooks framework for consistent integration behavior
5. Always implement graceful degradation when integrations are not configured

### State Management Best Practices
1. **Setup Remote Backend First**: Use `setup-backend.sh` before deploying infrastructure
2. **Migrate Safely**: Use `migrate-state.sh` with dry-run option to preview migration
3. **Regular Backups**: Create state backups before major changes using `state-manager.sh backup`
4. **Monitor Drift**: Regularly check for configuration drift using `state-manager.sh drift`
5. **Team Coordination**: Use GitHub Actions for centralized deployments to avoid conflicts
6. **State Inspection**: Use `state-manager.sh show/list/inspect` for troubleshooting
7. **Version Management**: Object Storage versioning is enabled for state history
8. **Access Control**: Use environment-specific buckets and IAM policies

### Cost Optimization
1. Use cost calculator before scaling or deploying
2. Implement resource quotas and limits
3. Monitor usage patterns and optimize node sizing
4. Set up budget alerts for cost overrun prevention

This project combines enterprise-grade infrastructure automation with modern development practices, providing a complete solution for scalable development environments on Scaleway's cloud platform.