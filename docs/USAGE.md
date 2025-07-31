# Usage Guide

This comprehensive guide provides step-by-step instructions for using the Bootstrap Coder on Scaleway system, from initial setup to advanced operations.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Environment Management](#environment-management)
3. [Template Selection Guide](#template-selection-guide)
4. [Script Usage Examples](#script-usage-examples)
5. [User Persona Workflows](#user-persona-workflows)
6. [Advanced Use Cases](#advanced-use-cases)
7. [Troubleshooting Guide](#troubleshooting-guide)

## Getting Started

### Prerequisites

Before deploying your first Coder environment, ensure you have the following tools installed:

```bash
# Check required versions
terraform version    # >= 1.12.0
kubectl version      # >= 1.32.0
helm version         # >= 3.12.0
```

### Scaleway Account Setup

1. **Create Scaleway Account**: Sign up at [scaleway.com](https://scaleway.com)
2. **Generate API Keys**: Go to Credentials > API Keys
3. **Set Environment Variables**:

```bash
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"
export SCW_DEFAULT_REGION="fr-par"
export SCW_DEFAULT_ZONE="fr-par-1"
```

### Repository Setup

```bash
# Clone the repository
git clone https://github.com/your-org/bootstrap-coder-on-scaleway.git
cd bootstrap-coder-on-scaleway

# Make scripts executable
chmod +x scripts/**/*.sh

# Verify prerequisites
./scripts/lifecycle/setup.sh --check-prereqs
```

### First Deployment

Deploy your first development environment:

```bash
# Deploy development environment with Python template
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# Expected output:
# ✅ Prerequisites verified
# 💰 Estimated monthly cost: €53.70
# 🚀 Starting deployment...
# 🎉 Environment ready at: https://coder-dev.your-domain.com
```

### Understanding the Deployment Process

The deployment system automatically handles both infrastructure and application deployment:

#### **What Gets Deployed Automatically**
- ✅ **Kubernetes Cluster** - Fully configured with auto-scaling
- ✅ **PostgreSQL Database** - Managed database with backups
- ✅ **Coder Application** - Ready-to-use development platform
- ✅ **Networking & Security** - Load balancer, ingress, SSL certificates
- ✅ **Admin User** - Automatically created with secure credentials

#### **Template Deployment Behavior**

**With Template Specified** (`--template=template-name`):
```bash
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai
# Result: Coder + Python Django CrewAI template ready for workspace creation
```

**Without Template** (template left blank or omitted):
```bash
./scripts/lifecycle/setup.sh --env=dev
# Result: Coder deployed and ready, templates can be added later
```

#### **Adding Templates Later**
If you deployed without a template, you can add them anytime:

```bash
# Add a specific template after deployment
./scripts/lifecycle/setup.sh --env=dev --template=react-typescript --auto-approve

# Or manually via Coder CLI
export KUBECONFIG=<(terraform output -raw kubeconfig)
coder templates create my-template --directory=./templates/frontend/react-typescript
```

> **Key Point**: Your Coder environment is fully functional immediately after deployment, regardless of whether you specify a template. Templates are workspace blueprints that can be managed independently.

## Environment Management

### Development Environment

**Use Case**: Quick testing, personal development, learning

**Configuration**:
- **Cost**: €53.70/month
- **Resources**: 2×GP1-XS nodes (1 vCPU, 2GB RAM each)
- **Database**: DB-DEV-S (1 vCPU, 2GB RAM)
- **Storage**: 20GB block storage
- **Features**: Basic security, no monitoring

**Deployment**:

```bash
# Quick development setup
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=python-django-crewai \
  --auto-approve

# With custom configuration
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=react-typescript \
  --nodes=2 \
  --node-type=GP1-XS \
  --disk-size=30
```

### Staging Environment

**Use Case**: Pre-production testing, team collaboration, CI/CD validation

**Configuration**:
- **Cost**: €97.85/month
- **Resources**: 3×GP1-S nodes (2 vCPU, 4GB RAM each)
- **Database**: DB-GP-S with backups (2 vCPU, 4GB RAM)
- **Storage**: 50GB block storage with snapshots
- **Features**: Enhanced security, basic monitoring

**Deployment**:

```bash
# Staging environment with monitoring
./scripts/lifecycle/setup.sh \
  --env=staging \
  --template=java-spring \
  --enable-monitoring \
  --backup-retention=7

# Expected deployment time: 12-15 minutes
```

### Production Environment

**Use Case**: Live development environments, enterprise teams, high availability

**Configuration**:
- **Cost**: €374.50/month
- **Resources**: 5×GP1-M nodes (4 vCPU, 8GB RAM each)
- **Database**: DB-GP-M with HA clustering (4 vCPU, 16GB RAM)
- **Storage**: 200GB block storage with daily backups
- **Features**: Full security enforcement, comprehensive monitoring

**Deployment**:

```bash
# Production environment with full features
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=claude-flow-enterprise \
  --enable-monitoring \
  --enable-ha \
  --backup-retention=30 \
  --auto-scaling-min=3 \
  --auto-scaling-max=15

# Deployment includes:
# - Pod Security Standards (restricted)
# - Network Policies with default deny-all
# - Resource quotas and limits
# - Monitoring stack (Prometheus + Grafana)
# - Automated backups
# - Cost tracking and alerts
```

## Template Selection Guide

### Backend Framework Templates

#### Java Spring Boot (`java-spring`)

**Best for**: Enterprise microservices, REST APIs, complex business logic

**Features**:
- Spring Boot 3.2 with Spring AI integration
- Maven and Gradle support
- PostgreSQL and Redis connectivity
- Docker containerization
- Comprehensive testing setup

**Use Case Example**:

```bash
# Deploy Java environment for microservices development
./scripts/lifecycle/setup.sh \
  --env=staging \
  --template=java-spring \
  --cpu=4 \
  --memory=8

# Workspace includes:
# - OpenJDK 21 + Spring Boot 3.2
# - Maven 3.9 + Gradle 8.5
# - IntelliJ IDEA Community Edition
# - PostgreSQL client tools
# - Docker + Docker Compose
# - JUnit 5 + Testcontainers
```

#### Python Django + CrewAI (`python-django-crewai`)

**Best for**: AI-powered web applications, multi-agent systems, data processing

**Features**:
- Django 4.2 with Django REST Framework
- CrewAI framework for multi-agent orchestration
- Poetry for dependency management
- Jupyter notebook integration
- GPU support for AI workloads

**Use Case Example**:

```bash
# Deploy AI-enhanced Python environment
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=python-django-crewai \
  --enable-gpu \
  --memory=16

# Includes sample CrewAI setup:
# - Content generation agents
# - Data analysis workflows
# - API endpoints for agent orchestration
# - Jupyter notebooks for experimentation
```

#### Go Fiber (`go-fiber`)

**Best for**: High-performance APIs, microservices, cloud-native applications

**Features**:
- Go 1.21 with Fiber v3 framework
- GORM for database operations
- Air for live reloading
- Docker multi-stage builds
- Comprehensive benchmarking tools

**Deployment Example**:

```bash
./scripts/lifecycle/setup.sh \
  --env=staging \
  --template=go-fiber \
  --cpu=2 \
  --memory=4

# Development environment includes:
# - Go 1.21 + Fiber v3
# - PostgreSQL with GORM
# - Redis for caching
# - Prometheus metrics integration
# - Load testing tools (k6)
```

### Frontend Framework Templates

#### React + TypeScript (`react-typescript`)

**Best for**: Modern SPAs, PWAs, component libraries

**Features**:
- React 18 with TypeScript 5
- Vite build system
- Tailwind CSS + Headless UI
- Storybook for component development
- Comprehensive testing (Jest + Testing Library + Playwright)

**Deployment**:

```bash
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=react-typescript \
  --enable-pwa

# Workspace configuration:
# - Node.js 20 LTS
# - pnpm package manager
# - VS Code with React extensions
# - Storybook dev server
# - Tailwind CSS IntelliSense
```

#### Angular (`angular`)

**Best for**: Enterprise applications, complex forms, large teams

**Features**:
- Angular 17 with standalone components
- Angular CLI and DevKit
- NgRx for state management
- Angular Material + CDK
- Karma + Jasmine testing

**Deployment Example**:

```bash
./scripts/lifecycle/setup.sh \
  --env=staging \
  --template=angular \
  --state-management=ngrx

# Includes:
# - Angular 17 + Angular CLI 17
# - TypeScript 5.2
# - NgRx store and effects
# - Angular Material components
# - Cypress E2E testing
```

### AI-Enhanced Templates

#### Claude Code Flow Base (`claude-flow-base`)

**Best for**: AI-assisted development, rapid prototyping, learning

**Features**:
- 87 advanced MCP tools
- Swarm mode for quick tasks
- Multiple development stacks
- Intelligent code generation
- Automated testing and documentation

**Deployment**:

```bash
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=claude-flow-base \
  --ai-mode=swarm \
  --dev-stack=full-stack

# AI capabilities include:
# - Automated code generation
# - Intelligent refactoring
# - Test case creation
# - Documentation generation
# - Performance optimization
```

#### Claude Code Flow Enterprise (`claude-flow-enterprise`)

**Best for**: Large teams, complex projects, enterprise AI workflows

**Features**:
- All base features plus:
- Hive-mind mode for complex projects
- Advanced memory system
- Team collaboration features
- Enterprise security integration

**Deployment**:

```bash
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=claude-flow-enterprise \
  --ai-mode=hive-mind \
  --team-size=20 \
  --memory=32

# Enterprise features:
# - Multi-agent project orchestration
# - Persistent project memory
# - Team knowledge sharing
# - Advanced security policies
# - Enterprise audit logging
```

### Mobile Development Templates

#### Flutter (`flutter`)

**Best for**: Cross-platform mobile apps, rapid prototyping

**Deployment**:

```bash
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=flutter \
  --target-platforms=all

# Includes:
# - Flutter 3.22 + Dart 3.4
# - Android SDK + emulator
# - Chrome for web development
# - VS Code with Flutter extensions
# - Firebase integration tools
```

#### React Native (`react-native`)

**Best for**: JavaScript-based mobile development, code sharing with web

**Deployment**:

```bash
./scripts/lifecycle/setup.sh \
  --env=staging \
  --template=react-native \
  --target-platforms=android,ios

# Development environment:
# - Node.js 20 + React Native 0.74
# - Android SDK and Virtual Device
# - Expo CLI for rapid development
# - Metro bundler with hot reloading
# - Detox for E2E testing
```

## Script Usage Examples

### Setup Script (`./scripts/lifecycle/setup.sh`)

**Complete option reference**:

```bash
./scripts/lifecycle/setup.sh [OPTIONS]

OPTIONS:
  --env=<environment>          Environment (dev|staging|prod)
  --template=<template>        Workspace template name
  --dry-run                   Show plan without applying
  --auto-approve              Skip confirmation prompts
  --enable-monitoring         Enable Prometheus/Grafana stack
  --enable-ha                 Enable high availability (prod only)
  --backup-retention=<days>   Backup retention period (default: 7)
  --nodes=<count>            Number of nodes (overrides env default)
  --node-type=<type>         Node instance type
  --cpu=<cores>              CPU cores for templates
  --memory=<gb>              Memory in GB for templates
  --disk-size=<gb>           Disk size in GB
  --domain=<domain>          Custom domain name
  --oauth-provider=<provider> OAuth provider (github|google|oidc)
  --budget=<amount>          Monthly budget limit in EUR
  --alert-threshold=<percent> Budget alert threshold (default: 80)
  --config-file=<path>       Custom configuration file
  --log-file=<path>          Custom log file location
  --help                     Show detailed help
```

**Example Workflows**:

```bash
# Quick development setup
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# Production deployment with full options
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=claude-flow-enterprise \
  --enable-monitoring \
  --enable-ha \
  --backup-retention=30 \
  --domain=coder.mycompany.com \
  --oauth-provider=oidc \
  --budget=500 \
  --alert-threshold=85

# Dry run to preview changes
./scripts/lifecycle/setup.sh \
  --env=staging \
  --template=java-spring \
  --dry-run

# Custom node configuration
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=go-fiber \
  --nodes=3 \
  --node-type=GP1-S \
  --auto-approve
```

### Cost Calculator (`./scripts/utils/cost-calculator.sh`)

**Calculate and manage costs**:

```bash
# Show costs for all environments
./scripts/utils/cost-calculator.sh --env=all

# Output:
# Environment  Monthly Cost  Annual Cost   Budget    Usage
# dev          €53.70       €644.40       €100      53.7%
# staging      €97.85       €1,174.20     €200      48.9%
# prod         €374.50      €4,494.00     €500      74.9%
# TOTAL        €526.05      €6,312.60     €800      65.8%

# Set budget and alerts for production
./scripts/utils/cost-calculator.sh \
  --env=prod \
  --set-budget=500 \
  --alert-threshold=80 \
  --alert-email=admin@company.com

# Generate detailed cost report
./scripts/utils/cost-calculator.sh \
  --env=prod \
  --format=json \
  --period=yearly \
  --output-file=costs-2024.json

# Check specific resource costs
./scripts/utils/cost-calculator.sh \
  --env=staging \
  --breakdown=detailed \
  --include-projections
```

### Resource Tracker (`./scripts/utils/resource-tracker.sh`)

**Monitor and optimize resource usage**:

```bash
# Show resource utilization for all environments
./scripts/utils/resource-tracker.sh --env=all

# Detailed resource analysis for production
./scripts/utils/resource-tracker.sh \
  --env=prod \
  --detailed \
  --recommendations

# Track specific resource types
./scripts/utils/resource-tracker.sh \
  --env=staging \
  --resource-types=cpu,memory,storage \
  --time-range=7d

# Generate optimization report
./scripts/utils/resource-tracker.sh \
  --env=prod \
  --optimize \
  --savings-threshold=10 \
  --output=optimization-report.json
```

### Validation Script (`./scripts/validate.sh`)

**Validate environment health**:

```bash
# Complete health check
./scripts/validate.sh --env=prod

# Quick connectivity check
./scripts/validate.sh --env=dev --quick

# Validate specific components
./scripts/validate.sh \
  --env=staging \
  --components=coder,database,monitoring

# Generate health report
./scripts/validate.sh \
  --env=prod \
  --detailed \
  --output=health-report-$(date +%Y%m%d).json
```

## User Persona Workflows

### DevOps Engineer Workflows

#### Initial Platform Setup

**Scenario**: Setting up Coder platform for a 50-person engineering team

```bash
# 1. Deploy production environment with high availability
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=claude-flow-enterprise \
  --enable-monitoring \
  --enable-ha \
  --nodes=5 \
  --auto-scaling-min=3 \
  --auto-scaling-max=15 \
  --backup-retention=30 \
  --domain=coder.company.com \
  --oauth-provider=oidc \
  --budget=1000 \
  --alert-threshold=80

# 2. Set up staging environment for testing
./scripts/lifecycle/setup.sh \
  --env=staging \
  --template=java-spring \
  --enable-monitoring \
  --backup-retention=7 \
  --domain=coder-staging.company.com \
  --budget=200

# 3. Configure cost monitoring and alerts
./scripts/utils/cost-calculator.sh \
  --env=all \
  --set-budget=1200 \
  --alert-threshold=75 \
  --daily-reports \
  --alert-email=devops@company.com

# 4. Set up automated health checks
crontab -e
# Add: 0 */4 * * * /path/to/scripts/validate.sh --env=prod --quick
# Add: 0 8 * * * /path/to/scripts/utils/cost-calculator.sh --env=all --daily-report
```

#### Infrastructure Scaling

**Scenario**: Scaling infrastructure during team growth

```bash
# Monitor current resource utilization
./scripts/utils/resource-tracker.sh --env=prod --detailed

# Scale cluster nodes based on usage
./scripts/scale.sh \
  --env=prod \
  --nodes=8 \
  --node-type=GP1-M \
  --auto-approve

# Update resource quotas for increased usage
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: coder-workspace-quota
  namespace: coder
spec:
  hard:
    requests.cpu: "100"
    requests.memory: 200Gi
    persistentvolumeclaims: "100"
EOF

# Verify scaling completion
./scripts/validate.sh --env=prod --components=cluster,monitoring
```

#### Disaster Recovery Testing

**Scenario**: Testing backup and recovery procedures

```bash
# 1. Create full environment backup
./scripts/backup.sh \
  --env=prod \
  --include-data \
  --include-config \
  --backup-name="disaster-recovery-test-$(date +%Y%m%d)"

# 2. Test database recovery
./scripts/restore.sh \
  --env=staging \
  --backup-name="disaster-recovery-test-20241121" \
  --component=database \
  --dry-run

# 3. Validate recovery process
./scripts/validate.sh \
  --env=staging \
  --post-restore-checks \
  --detailed

# 4. Document recovery time objectives
./scripts/utils/resource-tracker.sh \
  --env=staging \
  --recovery-metrics \
  --output=recovery-test-results.json
```

### Developer Workflows

#### Getting Started with AI-Enhanced Development

**Scenario**: Developer joining team, needs AI-powered Python environment

1. **Access Coder Instance**:

```bash
# Developer receives invitation email with:
# URL: https://coder.company.com
# OAuth: Use company Google/GitHub account
```

2. **Create Workspace**:

- Navigate to Coder web interface
- Select "Python Django + CrewAI" template
- Configure resources: 4 CPU, 8GB RAM, 50GB storage
- Click "Create Workspace"

3. **Start Development**:

```bash
# Connect via VS Code
code --remote ssh-remote+coder-workspace /home/coder

# Or use web IDE
# Click "VS Code" in Coder dashboard

# Initialize new project with AI assistance
claude-flow init --project="Customer Analytics API" --stack=python-ai

# AI will generate:
# - Django project structure
# - CrewAI agent configurations
# - API endpoints for analytics
# - Database models and migrations
# - Comprehensive tests
# - Documentation
```

#### Frontend Development Workflow

**Scenario**: Frontend developer building React application

```bash
# 1. Create React TypeScript workspace
# Via Coder UI: Select "React + TypeScript" template

# 2. Connect to workspace
code --remote ssh-remote+coder-workspace /home/coder

# 3. Initialize project with AI assistance
claude-flow create-app \
  --name="customer-dashboard" \
  --framework=react \
  --features="authentication,routing,state-management,testing"

# 4. AI generates complete application structure:
# customer-dashboard/
# ├── src/
# │   ├── components/        # Reusable UI components
# │   ├── pages/            # Page components
# │   ├── hooks/            # Custom React hooks
# │   ├── services/         # API service layer
# │   ├── store/            # State management (Zustand)
# │   └── types/            # TypeScript definitions
# ├── tests/                # Comprehensive test suite
# └── docs/                 # Generated documentation

# 5. Start development server
npm run dev
# Access at: https://workspace-name-8080.coder.company.com

# 6. AI-assisted development
claude-flow assist --context="building user authentication flow"
# AI provides component suggestions, best practices, security considerations
```

#### Mobile Development with React Native

**Scenario**: Mobile developer building cross-platform app

```bash
# 1. Create React Native workspace
# Via Coder UI: Select "React Native" template, target: iOS + Android

# 2. Access workspace
ssh coder-workspace

# 3. AI-assisted project setup
claude-flow mobile-init \
  --name="TaskManager" \
  --platforms="ios,android" \
  --features="authentication,offline-sync,push-notifications"

# 4. Start Android emulator
emulator -avd Pixel_4_API_30

# 5. Run development build
npx react-native run-android

# 6. Access Metro bundler
# Web interface: https://workspace-name-8081.coder.company.com

# 7. AI-powered development assistance
claude-flow code-review --files="src/components/TaskList.tsx"
# AI provides optimization suggestions, accessibility improvements
```

### Platform Administrator Workflows

#### Cost Optimization

**Scenario**: Monthly cost review and optimization

```bash
# 1. Generate comprehensive cost report
./scripts/utils/cost-calculator.sh \
  --env=all \
  --period=monthly \
  --breakdown=detailed \
  --include-projections \
  --format=json \
  --output="cost-report-$(date +%Y-%m).json"

# 2. Analyze resource utilization
./scripts/utils/resource-tracker.sh \
  --env=all \
  --detailed \
  --recommendations \
  --underutilized-threshold=50 \
  --output="resource-analysis-$(date +%Y-%m).json"

# 3. Identify optimization opportunities
# Example output:
# Environment: prod
# Underutilized resources:
# - Node pool: 3/5 nodes at <40% CPU utilization
# - Database: 2 vCPU, 16GB RAM at 25% utilization
# - Storage: 200GB provisioned, 120GB used
#
# Recommendations:
# - Reduce node count to 3 (save €84.60/month)
# - Downgrade database to DB-GP-S (save €89.25/month)
# - Reduce storage to 150GB (save €2/month)
# Total potential savings: €175.85/month (46.9%)

# 4. Implement optimizations
./scripts/scale.sh --env=prod --nodes=3 --confirm
./scripts/database-resize.sh --env=prod --instance-type=DB-GP-S --confirm

# 5. Update budget alerts
./scripts/utils/cost-calculator.sh \
  --env=prod \
  --set-budget=300 \
  --alert-threshold=85
```

#### Security Compliance Audit

**Scenario**: Quarterly security review

```bash
# 1. Generate security compliance report
./scripts/security-audit.sh \
  --env=all \
  --standards="pod-security,network-policy,rbac" \
  --output="security-audit-$(date +%Y-Q%q).json"

# 2. Check Pod Security Standards compliance
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.securityContext.runAsNonRoot}{"\n"}{end}' | grep false

# 3. Validate Network Policies
kubectl get networkpolicies -A
kubectl describe networkpolicy default-deny-all -n coder

# 4. RBAC audit
kubectl auth can-i --list --as=system:serviceaccount:coder:coder-service-account

# 5. Certificate expiration check
kubectl get certificates -A -o custom-columns="NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,EXPIRES:.status.notAfter"

# 6. Generate remediation plan
./scripts/security-remediation.sh \
  --audit-file="security-audit-2024-Q4.json" \
  --priority=high \
  --output="remediation-plan.md"
```

#### User Access Management

**Scenario**: Managing team access and permissions

```bash
# 1. Create team-based RBAC
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: coder
  name: frontend-developer
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: frontend-team
  namespace: coder
subjects:
- kind: Group
  name: frontend-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: frontend-developer
  apiGroup: rbac.authorization.k8s.io
EOF

# 2. Configure resource quotas per team
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: frontend-team-quota
  namespace: coder
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    persistentvolumeclaims: "10"
    pods: "20"
EOF

# 3. Set up user provisioning automation
./scripts/user-provisioning.sh \
  --team=frontend \
  --template=react-typescript \
  --default-resources="cpu=2,memory=4Gi,storage=20Gi" \
  --oauth-group="frontend-team@company.com"

# 4. Monitor user activity
./scripts/user-activity-report.sh \
  --period=monthly \
  --teams=frontend,backend,devops \
  --metrics="login-frequency,resource-usage,cost-attribution" \
  --output="user-activity-$(date +%Y-%m).json"
```

## Advanced Use Cases

### Multi-Environment CI/CD Pipeline

**Scenario**: Automated testing and deployment across environments

```bash
# 1. Set up CI/CD pipeline configuration
cat > .github/workflows/coder-deployment.yml <<EOF
name: Coder Environment Deployment
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy Development
        run: |
          ./scripts/lifecycle/setup.sh \
            --env=dev \
            --template=python-django-crewai \
            --auto-approve
      - name: Run Integration Tests
        run: ./scripts/run-integration-tests.sh --env=dev

  deploy-staging:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy Staging
        run: |
          ./scripts/lifecycle/setup.sh \
            --env=staging \
            --template=java-spring \
            --auto-approve
      - name: Run E2E Tests
        run: ./scripts/run-e2e-tests.sh --env=staging

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4
      - name: Deploy Production
        run: |
          ./scripts/lifecycle/setup.sh \
            --env=prod \
            --template=claude-flow-enterprise \
            --enable-monitoring \
            --enable-ha \
            --auto-approve
      - name: Validate Production
        run: ./scripts/validate.sh --env=prod --comprehensive
EOF

# 2. Set up environment-specific secrets
gh secret set SCW_ACCESS_KEY_PROD --body "$SCW_ACCESS_KEY_PROD"
gh secret set SCW_SECRET_KEY_PROD --body "$SCW_SECRET_KEY_PROD"
gh secret set CODER_ADMIN_PASSWORD --body "$CODER_ADMIN_PASSWORD"
```

### Custom Template Creation

**Scenario**: Creating specialized template for Rust microservices

```bash
# 1. Create template directory
mkdir -p templates/backend/rust-microservices

# 2. Create template configuration
cat > templates/backend/rust-microservices/main.tf <<EOF
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# Template-specific parameters
data "coder_parameter" "rust_version" {
  name         = "rust_version"
  display_name = "Rust Version"
  description  = "Rust toolchain version"
  default      = "1.75"
  option {
    name  = "Rust 1.75 (Stable)"
    value = "1.75"
  }
  option {
    name  = "Rust 1.76 (Beta)"
    value = "1.76"
  }
}

data "coder_parameter" "microservice_stack" {
  name         = "microservice_stack"
  display_name = "Microservice Stack"
  description  = "Microservice framework and tools"
  default      = "tokio-axum"
  option {
    name  = "Tokio + Axum"
    value = "tokio-axum"
  }
  option {
    name  = "Tokio + Warp"
    value = "tokio-warp"
  }
  option {
    name = "Actix Web"
    value = "actix-web"
  }
}

# Workspace configuration
resource "kubernetes_deployment" "workspace" {
  metadata {
    name      = "coder-\${data.coder_workspace.me.name}"
    namespace = "coder"
  }
  spec {
    selector {
      match_labels = {
        app = "coder-workspace"
      }
    }
    template {
      metadata {
        labels = {
          app = "coder-workspace"
        }
      }
      spec {
        container {
          name  = "workspace"
          image = "rust:\${data.coder_parameter.rust_version.value}"
          command = ["/bin/bash", "-c"]
          args = [coder_agent.main.init_script]

          resources {
            requests = {
              cpu    = "2"
              memory = "4Gi"
            }
            limits = {
              cpu    = "4"
              memory = "8Gi"
            }
          }
        }
      }
    }
  }
}

# Custom startup script for Rust microservices
resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # Install system dependencies
    apt-get update && apt-get install -y \
      build-essential \
      pkg-config \
      libssl-dev \
      postgresql-client \
      redis-tools \
      docker.io \
      kubectl \
      helm

    # Install Rust toolchain
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source ~/.cargo/env
    rustup default \${data.coder_parameter.rust_version.value}

    # Install Rust development tools
    rustup component add clippy rustfmt rust-analyzer
    cargo install cargo-watch cargo-edit cargo-audit cargo-outdated

    # Install VS Code extensions
    code-server --install-extension rust-lang.rust-analyzer
    code-server --install-extension vadimcn.vscode-lldb
    code-server --install-extension serayuzgur.crates

    # Create sample microservice project
    case "\${data.coder_parameter.microservice_stack.value}" in
      "tokio-axum")
        cargo new --name sample-service /home/coder/sample-service
        cd /home/coder/sample-service
        cat >> Cargo.toml <<EOT
[dependencies]
tokio = { version = "1.0", features = ["full"] }
axum = "0.7"
tower = "0.4"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
sqlx = { version = "0.7", features = ["runtime-tokio-rustls", "postgres"] }
redis = "0.24"
tracing = "0.1"
tracing-subscriber = "0.3"
EOT
        ;;
      "actix-web")
        cargo new --name sample-service /home/coder/sample-service
        cd /home/coder/sample-service
        cat >> Cargo.toml <<EOT
[dependencies]
actix-web = "4.0"
actix-rt = "2.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
sqlx = { version = "0.7", features = ["runtime-actix-rustls", "postgres"] }
redis = "0.24"
env_logger = "0.10"
EOT
        ;;
    esac

    # Build initial project
    cargo build

    # Set up development environment
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    echo 'alias ll="ls -la"' >> ~/.bashrc
    echo 'alias cw="cargo watch -x run"' >> ~/.bashrc

    # Create docker-compose for local services
    cat > /home/coder/docker-compose.yml <<EOT
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: microservice_db
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: devpass
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
EOT
  EOF
}

# Applications
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code"
  icon         = "/icon/code.svg"
  url          = "http://localhost:8080"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "microservice" {
  agent_id     = coder_agent.main.id
  slug         = "microservice"
  display_name = "Microservice Dev Server"
  icon         = "/icon/rust.svg"
  url          = "http://localhost:3000"
  subdomain    = true
  share        = "owner"
}
EOF

# 3. Test the custom template
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=rust-microservices \
  --dry-run
```

### Integration with Existing Infrastructure

**Scenario**: Integrating with existing company infrastructure

```bash
# 1. Configure VPC peering with existing networks
cat > environments/prod/vpc-peering.tf <<EOF
# Existing company VPC
data "scaleway_vpc" "company_vpc" {
  vpc_id = var.company_vpc_id
}

# Peer Coder VPC with company VPC
resource "scaleway_vpc_route" "to_company" {
  vpc_id      = module.networking.vpc_id
  destination = "10.0.0.0/8"  # Company network range
  nexthop     = data.scaleway_vpc.company_vpc.gateway_ip
}

resource "scaleway_vpc_route" "from_company" {
  vpc_id      = data.scaleway_vpc.company_vpc.id
  destination = module.networking.cidr_block
  nexthop     = module.networking.gateway_ip
}
EOF

# 2. Integrate with existing monitoring
cat > modules/coder-deployment/monitoring-integration.tf <<EOF
# Forward metrics to existing Prometheus
resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "prometheus-remote-write"
    namespace = "monitoring"
  }

  data = {
    "remote_write.yml" = yamlencode({
      remote_write = [{
        url = var.company_prometheus_url
        bearer_token = var.prometheus_bearer_token
        write_relabel_configs = [{
          source_labels = ["__name__"]
          regex = "coder_.*"
          action = "keep"
        }]
      }]
    })
  }
}
EOF

# 3. Use existing DNS and certificates
cat > modules/networking/dns-integration.tf <<EOF
# Use existing DNS zone
data "scaleway_domain_zone" "company" {
  domain = var.company_domain
}

resource "scaleway_domain_record" "coder" {
  dns_zone = data.scaleway_domain_zone.company.id
  name     = "coder"
  type     = "A"
  data     = module.load_balancer.ip_address
  ttl      = 300
}

# Use existing certificate
data "scaleway_lb_certificate" "company_wildcard" {
  name = "wildcard.${var.company_domain}"
}
EOF

# 4. Deploy with existing infrastructure integration
./scripts/lifecycle/setup.sh \
  --env=prod \
  --template=claude-flow-enterprise \
  --config-file=configs/company-integration.tfvars \
  --enable-monitoring \
  --company-vpc-id=vpc-12345 \
  --company-domain=company.com \
  --prometheus-endpoint=https://prometheus.company.com
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Prerequisites and Dependencies

**Issue**: Setup fails with missing dependencies

```bash
# Symptom
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai
ERROR: Terraform not found or version < 1.12.0

# Solution
# 1. Check versions
terraform version    # Should be >= 1.12.0
kubectl version      # Should be >= 1.32.0
helm version         # Should be >= 3.12.0

# 2. Install missing tools
# Terraform
wget https://releases.hashicorp.com/terraform/1.12.2/terraform_1.12.2_linux_amd64.zip
unzip terraform_1.12.2_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 3. Verify prerequisites
./scripts/lifecycle/setup.sh --check-prereqs
```

#### Scaleway Authentication

**Issue**: Authentication failures

```bash
# Symptom
Error: failed to create client: scaleway-sdk-go: no credentials found

# Solution
# 1. Check environment variables
echo $SCW_ACCESS_KEY     # Should be set
echo $SCW_SECRET_KEY     # Should be set
echo $SCW_DEFAULT_PROJECT_ID  # Should be set

# 2. Re-configure credentials
scw init
# Or export manually:
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"

# 3. Test authentication
scw account project list
```

#### Resource Quota Exceeded

**Issue**: Deployment fails due to resource limits

```bash
# Symptom
Error: error waiting for cluster to be ready: timeout while waiting for state to become 'ready'

# Solution
# 1. Check current resource usage
scw k8s cluster list
scw k8s node list cluster-id=$CLUSTER_ID

# 2. Check account quotas
scw account quota list

# 3. Request quota increase or reduce resource requests
# Option A: Reduce resources
./scripts/lifecycle/setup.sh \
  --env=dev \
  --nodes=2 \
  --node-type=GP1-XS \
  --template=python-django-crewai

# Option B: Contact Scaleway support for quota increase
```

#### Network Connectivity Issues

**Issue**: Cannot access Coder instance

```bash
# Symptom
curl: (28) Failed to connect to coder-dev.domain.com port 443: Connection timed out

# Solution
# 1. Check load balancer status
kubectl get svc -n coder
kubectl describe svc coder-service -n coder

# 2. Check ingress configuration
kubectl get ingress -n coder
kubectl describe ingress coder-ingress -n coder

# 3. Verify DNS resolution
nslookup coder-dev.domain.com
dig coder-dev.domain.com

# 4. Check security groups
scw vpc security-group list
scw vpc security-group-rule list security-group-id=$SG_ID

# 5. Validate certificates
kubectl get certificates -n coder
kubectl describe certificate coder-cert -n coder
```

#### Database Connection Issues

**Issue**: Coder cannot connect to PostgreSQL

```bash
# Symptom
WARN: database connection failed: connection refused

# Solution
# 1. Check database status
scw rdb instance list
scw rdb instance get instance-id=$DB_ID

# 2. Verify database connection from cluster
kubectl exec -it deployment/coder -n coder -- psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# 3. Check network connectivity
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# 4. Verify security group rules
scw vpc security-group-rule list security-group-id=$DB_SG_ID

# 5. Check secrets
kubectl get secret coder-db-secret -n coder -o yaml
kubectl describe secret coder-db-secret -n coder
```

#### Template Deployment Issues

**Issue**: Workspace creation fails

```bash
# Symptom
Error: failed to create workspace: template validation failed

# Solution
# 1. Validate template syntax
cd templates/backend/python-django-crewai
terraform validate
terraform plan

# 2. Check resource limits
kubectl get resourcequota -n coder
kubectl describe resourcequota -n coder

# 3. Check node resources
kubectl top nodes
kubectl describe nodes

# 4. Review pod events
kubectl get events -n coder --sort-by='.lastTimestamp'

# 5. Check image availability
kubectl run test --image=python:3.11 --dry-run=client -o yaml
```

#### Performance Issues

**Issue**: Slow workspace startup or poor performance

```bash
# Symptom
Workspace takes 10+ minutes to start, or runs slowly

# Solution
# 1. Check node resources
kubectl top nodes
kubectl top pods -n coder

# 2. Analyze resource requests vs limits
kubectl get pods -n coder -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources}{"\n"}{end}'

# 3. Check storage performance
kubectl exec -it $WORKSPACE_POD -- dd if=/dev/zero of=/tmp/test bs=1M count=1000 conv=fdatasync

# 4. Review monitoring metrics
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090 and query: rate(cpu_usage_seconds_total[5m])

# 5. Scale resources if needed
./scripts/scale.sh \
  --env=dev \
  --nodes=3 \
  --node-type=GP1-S

# Or adjust workspace resources
kubectl patch deployment workspace-name -n coder -p '{"spec":{"template":{"spec":{"containers":[{"name":"workspace","resources":{"requests":{"cpu":"2","memory":"4Gi"}}}]}}}}'
```

#### GitHub Actions Failures

**Issue**: Deployment workflow fails

```bash
# Symptom
Error: The workflow run failed. View the workflow run for more details.

# Solution
# 1. Check workflow logs
gh run list --workflow=deploy-environment.yml
gh run view 1234567890 --log

# 2. Debug workflow locally
act -W .github/workflows/deploy-environment.yml \
  --secret-file .env.secrets \
  --var environment=dev

# 3. Validate workflow syntax
yaml-lint .github/workflows/deploy-environment.yml
actionlint .github/workflows/

# 4. Check secrets configuration
gh secret list
gh secret get SCW_ACCESS_KEY  # Should not show value

# 5. Run manual deployment for debugging
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=python-django-crewai
```

#### Template Validation Failures

**Issue**: Template validation fails in CI/CD

```bash
# Symptom
ERROR: Template 'custom-template' failed validation

# Solution
# 1. Test template locally
./scripts/test-runner.sh \
  --suite=templates

# 2. Check template syntax
cd templates/backend/custom-template
terraform validate
terraform fmt -check

# 3. Validate template metadata
yaml-lint metadata.yaml

# 4. Test template deployment
./scripts/lifecycle/setup.sh \
  --env=dev \
  --template=custom-template \
  --dry-run

# 5. Check template resource limits
kubectl apply --dry-run=client -f template-resources.yaml
```

#### Webhook and Notification Issues

**Issue**: Notifications not being sent

```bash
# Symptom
Deployment successful but no Slack notifications

# Solution
# 1. Test webhook URL
curl -X POST "$SLACK_WEBHOOK" \
  -H 'Content-type: application/json' \
  -d '{"text":"Test message"}'

# 2. Check secret configuration
gh secret get SLACK_WEBHOOK  # Verify secret exists

# 3. Validate workflow notification step
gh run view --log | grep -A 10 "Send notification"

# 4. Test notification script locally
./scripts/hooks/post-setup.sh --env=dev

# 5. Check notification service status
curl -I https://hooks.slack.com/services/health
```

#### Cost Overruns

**Issue**: Monthly costs exceed budget

```bash
# Symptom
Budget alert: Current month costs (€450) exceed 80% of budget (€400)

# Solution
# 1. Analyze current costs
./scripts/utils/cost-calculator.sh \
  --env=all \
  --breakdown=detailed \
  --include-projections

# 2. Identify high-cost resources
./scripts/utils/resource-tracker.sh \
  --env=all \
  --cost-analysis \
  --sort-by-cost

# 3. Optimize underutilized resources
./scripts/utils/resource-tracker.sh \
  --env=prod \
  --underutilized-threshold=50 \
  --recommendations

# 4. Implement cost optimization
# Example optimizations:
./scripts/scale.sh --env=prod --nodes=3  # Reduce from 5 nodes
./scripts/database-resize.sh --env=prod --instance-type=DB-GP-S  # Downgrade DB

# 5. Set stricter budget alerts
./scripts/utils/cost-calculator.sh \
  --env=all \
  --set-budget=400 \
  --alert-threshold=70 \
  --daily-alerts
```

### Getting Help

**Support Channels**:

1. **Internal Documentation**:
   - `docs/ARCHITECTURE.md` - System architecture
   - `CLAUDE.md` - AI assistant context
   - Script help: `./scripts/lifecycle/setup.sh --help`

2. **Monitoring and Logs**:
   - Setup logs: `tail -f logs/setup-$(date +%Y%m%d).log`
   - Kubernetes logs: `kubectl logs -n coder deployment/coder`
   - Monitoring: Access Grafana at monitoring endpoint

3. **Community Support**:
   - Create issues in project repository
   - Check existing documentation and FAQ
   - Contact DevOps team for infrastructure issues

4. **GitHub Actions Debugging**:
   - Workflow logs: `gh run view <run-id> --log`
   - Local testing: Use `act` tool for workflow debugging
   - Syntax validation: `actionlint` and `yaml-lint`
   - Secret management: `gh secret list` and verification

5. **Emergency Contacts**:
   - Production issues: DevOps on-call rotation
   - Security incidents: Security team escalation
   - Cost concerns: Platform administrators
   - CI/CD failures: Platform automation team

This comprehensive usage guide provides detailed examples for all aspects of the Bootstrap Coder on Scaleway system, including advanced GitHub Actions CI/CD integration, automated testing, cost management, and extensible hooks framework. Use it as your primary reference for:

- **Daily Operations**: Environment deployment, scaling, and monitoring
- **CI/CD Integration**: Automated workflows, testing, and deployment pipelines
- **Cost Management**: Budget tracking, optimization, and automated alerts
- **Template Development**: Creating custom templates and validation workflows
- **Troubleshooting**: Common issues, debugging procedures, and emergency contacts
- **Team Workflows**: Multi-persona operations from developers to platform administrators

For the most up-to-date information and additional examples, refer to the project's GitHub repository and documentation.