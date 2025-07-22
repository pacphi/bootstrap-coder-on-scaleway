# Bootstrap Coder on Scaleway

Production-ready automation for deploying enterprise-grade Coder development environments on Scaleway Kubernetes, featuring 20+ workspace templates, comprehensive CI/CD workflows, and AI-enhanced development with Claude Code Flow integration.

## ⚡ Quick Start

### Manual Deployment
```bash
# Clone and deploy in 3 commands
git clone https://github.com/your-org/bootstrap-coder-on-scaleway.git
cd bootstrap-coder-on-scaleway
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# 🎉 Access your Coder instance at the provided URL
```

### GitHub Actions Deployment
```bash
# Fork the repository and configure secrets
gh repo fork your-org/bootstrap-coder-on-scaleway
gh secret set SCW_ACCESS_KEY --body "your-access-key"
gh secret set SCW_SECRET_KEY --body "your-secret-key"
gh secret set SCW_DEFAULT_PROJECT_ID --body "your-project-id"

# Deploy via GitHub Actions
gh workflow run deploy-environment.yml \
  -f environment=dev \
  -f template=python-django-crewai \
  -f enable_monitoring=true
```

**Prerequisites**: Terraform ≥1.6.0, kubectl ≥1.28.0, Helm ≥3.12.0, [Scaleway credentials](https://www.scaleway.com/en/docs/identity-and-access-management/iam/how-to/create-api-keys/)

## 🏗️ Multi-Environment Architecture

| Environment | Monthly Cost | Use Case | Resources |
|-------------|--------------|----------|-----------|
| **Development** | €53.70 | Personal dev, learning | 2×GP1-XS nodes, DB-DEV-S |
| **Staging** | €97.85 | Team testing, CI/CD | 3×GP1-S nodes, DB-GP-S |
| **Production** | €374.50 | Enterprise, high availability | 5×GP1-M nodes, DB-GP-M HA |

## 🎯 Available Templates

### **Backend** (7 templates)
Java Spring, Python Django+CrewAI, Go Fiber, Ruby Rails, PHP Symfony, Rust Actix Web, .NET Core

### **Frontend** (4 templates)
React+TypeScript, Angular, Vue+Nuxt, Svelte Kit

### **AI-Enhanced** (2 templates)
Claude Code Flow Base/Enterprise with 87 MCP tools, swarm/hive-mind modes

### **DevOps** (3 templates)
Docker Compose, Kubernetes+Helm, Terraform+Ansible

### **Data/ML** (2 templates)
Jupyter+Python, R Studio

### **Mobile** (3 templates)
Flutter, React Native, Ionic

## 📖 Documentation

- **[📋 Usage Guide](docs/USAGE.md)** - Complete usage examples, GitHub Actions workflows, and troubleshooting
- **[🏗️ Architecture Guide](docs/ARCHITECTURE.md)** - System design, components, CI/CD flows, and Mermaid diagrams
- **[🤖 AI Assistant Context](CLAUDE.md)** - Technical context for Claude Code integration and new capabilities
- **[🔧 Hooks Framework](scripts/hooks/README.md)** - Extensible automation and integration examples
- **[🧪 Testing Guide](scripts/test-runner.sh)** - Comprehensive validation and testing procedures
- **[📊 Cost Management](scripts/utils/cost-calculator.sh)** - Real-time cost tracking and optimization

## 🤖 GitHub Actions CI/CD

### Deploy Environment
```bash
# Trigger deployment workflow
gh workflow run deploy-environment.yml \
  -f environment=staging \
  -f template=react-typescript \
  -f enable_monitoring=true \
  -f enable_cost_alerts=true
```

### Teardown Environment
```bash
# Secure teardown with confirmation
gh workflow run teardown-environment.yml \
  -f environment=dev \
  -f confirmation="I understand this will destroy the environment" \
  -f create_backup=true
```

### Template Validation
```bash
# Validate all templates and infrastructure
gh workflow run validate-templates.yml \
  -f validation_scope=comprehensive \
  -f test_deployments=true
```

## 🛠️ Management Scripts

### Comprehensive Testing
```bash
# Run all validation tests
./scripts/test-runner.sh --suite=all --verbose

# Run specific test suites
./scripts/test-runner.sh --suite=smoke,templates --format=json
```

### Environment Validation
```bash
# Quick health check
./scripts/validate.sh --env=prod --quick

# Comprehensive validation with detailed report
./scripts/validate.sh --env=staging --comprehensive --format=json
```

### Dynamic Scaling
```bash
# Scale cluster with cost analysis
./scripts/scale.sh --env=prod --nodes=8 --analyze-cost

# Auto-scale based on workload
./scripts/scale.sh --env=staging --auto --target-cpu=70
```

### Automated Backups
```bash
# Complete environment backup
./scripts/lifecycle/backup.sh --env=prod --include-all

# Pre-destroy backup with retention
./scripts/lifecycle/backup.sh --env=staging --pre-destroy --retention=90d
```

## 🔧 Hooks Framework

### Custom Automation
```bash
# Customize deployment lifecycle
./scripts/hooks/pre-setup.sh    # Before deployment starts
./scripts/hooks/post-setup.sh   # After deployment completes
./scripts/hooks/pre-teardown.sh # Before teardown starts
./scripts/hooks/post-teardown.sh # After teardown completes
```

### Integration Examples
- **Slack notifications** for deployment events
- **JIRA ticket creation** for environment changes
- **External monitoring** system registration
- **Compliance checks** and audit logging
- **User notifications** and workspace management

## 🚀 Key Features

### 🏗️ Infrastructure & Deployment
- **Multi-environment deployment** with cost optimization (dev/staging/prod)
- **GitHub Actions CI/CD** with automated workflows and notifications
- **Terraform automation** with state management and drift detection
- **Kubernetes management** on Scaleway Kapsule with auto-scaling
- **Extensible hooks framework** for custom deployment logic

### 🎯 Templates & Development
- **21+ production-ready templates** across all major frameworks
- **AI-enhanced development** with Claude Code Flow integration (87 MCP tools)
- **Dynamic template discovery** with automatic validation
- **Multi-language support** (Java, Python, Go, Rust, JS/TS, C#, PHP, Ruby)
- **Specialized templates** for data science, DevOps, and mobile development

### 🔒 Security & Compliance
- **Enterprise security** with Pod Security Standards and RBAC
- **Network policies** and traffic isolation
- **Encrypted secrets** management with Kubernetes
- **Audit logging** and compliance tracking
- **Environment-specific security policies** (dev/staging/prod)

### 📊 Monitoring & Operations
- **Cost management** with real-time tracking and budget alerts
- **Comprehensive monitoring** with Prometheus/Grafana stacks
- **Health checks** and automated validation
- **Performance metrics** and resource optimization
- **External system integration** (Slack, monitoring, etc.)

### 💾 Backup & Recovery
- **Automated backups** with configurable retention policies
- **Disaster recovery** procedures with point-in-time restoration
- **Pre-destroy backups** to prevent data loss
- **Multi-format exports** (infrastructure, configs, data)
- **Backup verification** and integrity checks

### ⚡ Performance & Scaling
- **Dynamic cluster scaling** with cost analysis
- **Auto-scaling policies** based on CPU/memory metrics
- **Resource quotas** and limit enforcement
- **Load balancing** with SSL termination
- **Performance optimization** recommendations

## 🛡️ Enterprise Ready

✅ **Security**: Pod Security Standards, Network Policies, RBAC, encrypted secrets
✅ **Monitoring**: Prometheus metrics, Grafana dashboards, alerting
✅ **Compliance**: Audit logging, cost tracking, resource quotas
✅ **Scalability**: Auto-scaling nodes (3-15), high availability database
✅ **Reliability**: Automated backups, disaster recovery, health checks

## 🚀 Advanced Usage Examples

### Complete Development Workflow
```bash
# 1. Deploy development environment with AI template
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

### Production Deployment with Monitoring
```bash
# Deploy production with all enterprise features
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

### CI/CD Pipeline Integration
```yaml
# GitHub Actions example
name: Deploy Staging on PR
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy staging environment
        uses: ./.github/workflows/deploy-environment.yml
        with:
          environment: staging
          template: react-typescript
          pr_number: ${{ github.event.number }}
```

## 🔍 Troubleshooting

### Common Issues

**Prerequisites Missing**
```bash
# Check system requirements
./scripts/test-runner.sh --suite=prerequisites --fix
```

**Template Deployment Fails**
```bash
# Validate templates
./scripts/test-runner.sh --suite=templates --verbose

# Check template syntax
gh workflow run validate-templates.yml -f validation_scope=syntax
```

**Cost Overruns**
```bash
# Analyze current costs
./scripts/utils/cost-calculator.sh --env=all --detailed

# Set budget alerts
./scripts/utils/cost-calculator.sh --env=prod --set-budget=300 --alert-threshold=80
```

**Scaling Issues**
```bash
# Check cluster capacity
./scripts/validate.sh --env=prod --focus=resources

# Analyze scaling recommendations
./scripts/scale.sh --env=prod --analyze-only
```

### Support Channels
- **[Usage Guide](docs/USAGE.md)** - Comprehensive documentation
- **[GitHub Issues](../../issues)** - Bug reports and feature requests
- **[Architecture Guide](docs/ARCHITECTURE.md)** - System design and troubleshooting
- **[Hooks Examples](scripts/hooks/README.md)** - Custom integration patterns

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](.github/CONTRIBUTING.md) and check out [open issues](../../issues).

### Development Setup
```bash
# Fork and clone the repository
gh repo fork your-org/bootstrap-coder-on-scaleway
cd bootstrap-coder-on-scaleway

# Run comprehensive tests
./scripts/test-runner.sh --suite=all

# Deploy test environment
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai
```

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

**🚀 Ready to get started?** Choose your deployment method:
- **Quick Start**: `./scripts/lifecycle/setup.sh --env=dev --template=react-typescript`
- **GitHub Actions**: `gh workflow run deploy-environment.yml`
- **Comprehensive Setup**: Check the [Usage Guide](docs/USAGE.md)

**Need help?** Check the [documentation](docs/) or [create an issue](../../issues) 📞