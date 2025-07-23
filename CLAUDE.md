# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Terraform-based Infrastructure as Code (IaC)** project that deploys enterprise-grade **Coder development environments** on **Scaleway's managed Kubernetes** (Kapsule). The system provides 21+ workspace templates, multi-environment deployment, comprehensive cost management, and AI-enhanced development capabilities.

## Core Technology Stack

- **Infrastructure**: Terraform (≥1.6.0) with Scaleway provider
- **Container Platform**: Kubernetes on Scaleway Kapsule with Cilium CNI
- **Application**: Coder development platform with workspace templates
- **Database**: Managed PostgreSQL with environment-specific configurations
- **Orchestration**: Helm for application deployment
- **Automation**: Bash scripts for lifecycle management and operations

## Architecture Overview

### Multi-Environment Strategy
- **`environments/dev/`**: Cost-optimized (€53.70/month) - 2x GP1-XS nodes, DB-DEV-S
- **`environments/staging/`**: Production-like testing (€97.85/month) - 3x GP1-S nodes, DB-GP-S
- **`environments/prod/`**: High-availability enterprise (€374.50/month) - 5x GP1-M nodes, DB-GP-M HA

### Modular Infrastructure
- **`modules/scaleway-cluster/`**: Kubernetes cluster management with auto-scaling
- **`modules/networking/`**: VPC, security groups, load balancers
- **`modules/postgresql/`**: Database provisioning with HA and backup configuration
- **`modules/coder-deployment/`**: Coder platform deployment with OAuth and ingress
- **`modules/security/`**: RBAC, Pod Security Standards, network policies

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
# Deploy development environment with specific template
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# Deploy production with monitoring and HA
./scripts/lifecycle/setup.sh --env=prod --enable-monitoring --enable-ha

# Dry run to preview changes
./scripts/lifecycle/setup.sh --env=staging --dry-run

# Complete environment teardown with backup
./scripts/lifecycle/teardown.sh --env=dev --create-backup
```

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
# Navigate to environment directory first
cd environments/dev

# Plan infrastructure changes
terraform plan

# Apply changes with auto-approval
terraform apply -auto-approve

# Check current state
terraform show

# Import existing resources
terraform import <resource_type>.<name> <resource_id>
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

### Terraform Configuration
- **`shared/variables.tf`**: Common variables across environments
- **`shared/locals.tf`**: Environment-specific computed values
- **`shared/providers.tf`**: Terraform provider configurations
- **`shared/versions.tf`**: Version constraints and requirements

### Environment-Specific Files
Each `environments/{env}/` directory contains:
- **`main.tf`**: Environment-specific resource definitions
- **`providers.tf`**: Provider configurations with backend state
- **`outputs.tf`**: Environment outputs (URLs, connection strings)

## Prerequisites and Setup

### Required Tools and Versions
- **Terraform** ≥1.6.0
- **kubectl** ≥1.28.0
- **Helm** ≥3.12.0
- **Git** for version control
- **jq** for JSON processing in scripts

### Environment Variables
```bash
# Scaleway credentials (required)
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"

# Optional: Default region and zone
export SCW_DEFAULT_REGION="fr-par"
export SCW_DEFAULT_ZONE="fr-par-1"
```

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
# Check database status and connection
kubectl get secrets -n coder
kubectl exec -it deployment/coder -n coder -- env | grep DB_
```

### Log Locations
- **Setup logs**: `/logs/setup/<timestamp>-<env>-setup.log`
- **Terraform state**: `environments/<env>/terraform.tfstate`
- **Kubeconfig**: `~/.kube/config-coder-<env>`
- **Application logs**: `kubectl logs -f deployment/coder -n coder`

## Key Patterns for Development

### Infrastructure Changes
1. Always run `terraform plan` before applying changes
2. Use environment-specific configurations in `environments/{env}/`
3. Test changes in development environment before promoting to staging/production
4. Validate cost impact using `cost-calculator.sh` before deployment

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

### Cost Optimization
1. Use cost calculator before scaling or deploying
2. Implement resource quotas and limits
3. Monitor usage patterns and optimize node sizing
4. Set up budget alerts for cost overrun prevention

This project combines enterprise-grade infrastructure automation with modern development practices, providing a complete solution for scalable development environments on Scaleway's cloud platform.