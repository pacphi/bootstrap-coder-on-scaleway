# Coder Templates Directory

This document provides a comprehensive listing of all available Coder workspace templates in this project. These templates can be used with the `--template` parameter in deployment scripts and GitHub Actions.

## Overview

The project includes **21 workspace templates** organized into **6 categories**, providing development environments for modern web development, AI-enhanced workflows, data science, mobile development, and DevOps practices.

## Quick Reference

| Category | Template Name | Description | Cost Impact |
|----------|---------------|-------------|-------------|
| **🤖 AI-Enhanced** | `claude-flow-base` | Basic Claude Code Flow integration for AI-assisted development | Low |
| | `claude-flow-enterprise` | Enterprise Claude Code Flow with 87 MCP tools and advanced features | High |
| **🖥️ Backend** | `dotnet-core` | .NET Core development environment with C# tooling | Medium |
| | `go-fiber` | Go development with Fiber web framework | Low |
| | `java-spring` | Java Spring Boot development environment | Medium |
| | `php-symfony-neuron` | PHP Symfony framework with Neuron integration | Medium |
| | `python-django-crewai` | Python Django with CrewAI multi-agent workflow capabilities | High |
| | `ruby-rails` | Ruby on Rails development environment | Medium |
| | `rust-actix` | Rust development with Actix web framework | Low |
| **📊 Data/ML** | `jupyter-python` | Jupyter notebooks with comprehensive Python data science stack | High |
| | `r-studio` | R Studio for statistical computing and data analysis | Medium |
| **⚙️ DevOps** | `docker-compose` | Docker Compose development environment | Low |
| | `kubernetes-helm` | Kubernetes development with Helm package management | Medium |
| | `terraform-ansible` | Infrastructure as Code with Terraform and Ansible | Medium |
| **🌐 Frontend** | `angular` | Angular development environment with TypeScript | Medium |
| | `react-typescript` | React development with TypeScript | Medium |
| | `svelte-kit` | SvelteKit development environment | Low |
| | `vue-nuxt` | Vue.js development with Nuxt.js framework | Medium |
| **📱 Mobile** | `flutter` | Flutter cross-platform mobile development | Medium |
| | `ionic` | Ionic hybrid mobile development | Medium |
| | `react-native` | React Native mobile development | Medium |

## Usage Examples

### Using Templates with Lifecycle Scripts

```bash
# Deploy development environment with Python Django + CrewAI template
./scripts/lifecycle/setup.sh --env=dev --template=python-django-crewai

# Deploy staging with enterprise AI capabilities
./scripts/lifecycle/setup.sh --env=staging --template=claude-flow-enterprise

# Deploy production with React TypeScript frontend
./scripts/lifecycle/setup.sh --env=prod --template=react-typescript
```

### Using Templates with GitHub Actions

```yaml
name: Deploy Coder Environment
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [dev, staging, prod]
      template:
        description: 'Template to deploy'
        required: true
        type: choice
        options: [
          'claude-flow-base', 'claude-flow-enterprise', 'dotnet-core', 'go-fiber', 'java-spring', 'php-symfony-neuron', 'python-django-crewai', 'ruby-rails', 'rust-actix', 'jupyter-python', 'r-studio', 'docker-compose', 'kubernetes-helm', 'terraform-ansible', 'angular', 'react-typescript', 'svelte-kit', 'vue-nuxt', 'flutter', 'ionic', 'react-native'
        ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy Coder Template
        run: |
          ./scripts/lifecycle/setup.sh \
            --env=${{ inputs.environment }} \
            --template=${{ inputs.template }}
```

## Template Categories

### 🤖 AI-Enhanced Templates (2)

Advanced development environments with AI integration and enhanced capabilities.

#### `claude-flow-base`
- **Path**: `templates/ai-enhanced/claude-flow-base/`
- **Description**: Basic Claude Code Flow integration for AI-assisted development
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Low (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `claude-flow-enterprise`
- **Path**: `templates/ai-enhanced/claude-flow-enterprise/`
- **Description**: Enterprise Claude Code Flow with 87 MCP tools and advanced features
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: High (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]


### 🖥️ Backend Templates (7)

Server-side development environments with database integration and API frameworks.

#### `dotnet-core`
- **Path**: `templates/backend/dotnet-core/`
- **Description**: .NET Core development environment with C# tooling
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `go-fiber`
- **Path**: `templates/backend/go-fiber/`
- **Description**: Go development with Fiber web framework
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Low (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `java-spring`
- **Path**: `templates/backend/java-spring/`
- **Description**: Java Spring Boot development environment
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `php-symfony-neuron`
- **Path**: `templates/backend/php-symfony-neuron/`
- **Description**: PHP Symfony framework with Neuron integration
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `python-django-crewai`
- **Path**: `templates/backend/python-django-crewai/`
- **Description**: Python Django with CrewAI multi-agent workflow capabilities
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: High (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `ruby-rails`
- **Path**: `templates/backend/ruby-rails/`
- **Description**: Ruby on Rails development environment
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `rust-actix`
- **Path**: `templates/backend/rust-actix/`
- **Description**: Rust development with Actix web framework
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Low (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]


### 📊 Data/ML Templates (2)

Data science and machine learning development environments with specialized tools.

#### `jupyter-python`
- **Path**: `templates/data-ml/jupyter-python/`
- **Description**: Jupyter notebooks with comprehensive Python data science stack
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: High (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `r-studio`
- **Path**: `templates/data-ml/r-studio/`
- **Description**: R Studio for statistical computing and data analysis
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]


### ⚙️ DevOps Templates (3)

Infrastructure and deployment tool environments for DevOps workflows.

#### `docker-compose`
- **Path**: `templates/devops/docker-compose/`
- **Description**: Docker Compose development environment
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Low (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `kubernetes-helm`
- **Path**: `templates/devops/kubernetes-helm/`
- **Description**: Kubernetes development with Helm package management
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `terraform-ansible`
- **Path**: `templates/devops/terraform-ansible/`
- **Description**: Infrastructure as Code with Terraform and Ansible
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]


### 🌐 Frontend Templates (4)

Modern frontend development environments with popular JavaScript frameworks.

#### `angular`
- **Path**: `templates/frontend/angular/`
- **Description**: Angular development environment with TypeScript
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `react-typescript`
- **Path**: `templates/frontend/react-typescript/`
- **Description**: React development with TypeScript
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `svelte-kit`
- **Path**: `templates/frontend/svelte-kit/`
- **Description**: SvelteKit development environment
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Low (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `vue-nuxt`
- **Path**: `templates/frontend/vue-nuxt/`
- **Description**: Vue.js development with Nuxt.js framework
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]


### 📱 Mobile Templates (3)

Cross-platform mobile development environments with modern frameworks.

#### `flutter`
- **Path**: `templates/mobile/flutter/`
- **Description**: Flutter cross-platform mobile development
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `ionic`
- **Path**: `templates/mobile/ionic/`
- **Description**: Ionic hybrid mobile development
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]

#### `react-native`
- **Path**: `templates/mobile/react-native/`
- **Description**: React Native mobile development
- **Features**: [Auto-detected from template configuration]
- **Resource Requirements**: Medium (CPU cores, RAM based on template type)
- **Best For**: [Use case recommendations]


## Cost Considerations

### Resource Impact by Template Type

- **Low Impact** (€15-30/month per workspace): Templates with minimal resource requirements
- **Medium Impact** (€30-60/month per workspace): Most backend, frontend, and mobile templates
- **High Impact** (€60-120/month per workspace): AI-enhanced templates, data science environments

### Environment Scaling

Templates automatically scale resources based on the target environment:
- **Development**: Minimal resources, cost-optimized
- **Staging**: Production-like resources for testing
- **Production**: Full resources with high availability

## Template Selection Guide

### For Individual Developers
- **AI-Enhanced Development**: `claude-flow-base`
- **Web Development**: `react-typescript`, `vue-nuxt`, `go-fiber`
- **Data Science**: `jupyter-python`, `r-studio`
- **Mobile Development**: `flutter`, `react-native`

### For Teams
- **Enterprise AI**: `claude-flow-enterprise`
- **Backend Services**: `java-spring`, `python-django-crewai`, `dotnet-core`
- **DevOps Workflows**: `kubernetes-helm`, `terraform-ansible`
- **Full-Stack Development**: `react-typescript` + `go-fiber`

### For Specific Use Cases
- **High Performance**: `rust-actix`, `go-fiber`
- **Rapid Prototyping**: `svelte-kit`, `ruby-rails`
- **Enterprise Applications**: `java-spring`, `dotnet-core`, `angular`
- **AI/ML Projects**: `python-django-crewai`, `jupyter-python`

## Template Development

### Adding New Templates

1. Create template directory: `templates/{category}/{framework}/`
2. Implement `main.tf` with Coder workspace definition
3. Test template deployment with `./scripts/test-runner.sh --suite=templates`
4. Update this documentation using `./scripts/utils/generate-template-docs.sh`

### Template Structure Requirements

Each template must include:
- `main.tf`: Coder template definition (Terraform configuration)
- Configurable parameters for CPU, memory, disk size
- Startup scripts for environment setup
- Resource management and security contexts

## Maintenance

This documentation is automatically maintained using:
```bash
# Generate/update TEMPLATES.md from template directory scan
./scripts/utils/generate-template-docs.sh
```

Run this script after adding, removing, or modifying templates to keep the documentation current.

## Related Documentation

- [CLAUDE.md](./CLAUDE.md) - Project overview and architecture
- [Setup Guide](./scripts/lifecycle/setup.sh) - Environment deployment
- [Cost Calculator](./scripts/utils/cost-calculator.sh) - Resource cost analysis
- [Test Suite](./scripts/test-runner.sh) - Template validation and testing
