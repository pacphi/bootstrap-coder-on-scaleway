#!/bin/bash

# generate-template-docs.sh
# Automatically generates/updates TEMPLATES.md based on the templates directory structure
# Usage: ./scripts/utils/generate-template-docs.sh [--dry-run] [--output=FILE]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_DIR="$PROJECT_ROOT/templates"
DEFAULT_OUTPUT="$PROJECT_ROOT/docs/TEMPLATES.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
DRY_RUN=false
OUTPUT_FILE="$DEFAULT_OUTPUT"
VERBOSE=false

# Help text
show_help() {
    cat << EOF
Generate TEMPLATES.md documentation from templates directory structure

Usage: $0 [OPTIONS]

OPTIONS:
    --dry-run           Show what would be generated without writing files
    --output=FILE       Output file path (default: docs/TEMPLATES.md)
    --verbose           Show detailed processing information
    --help              Show this help message

EXAMPLES:
    $0                                  # Generate docs/TEMPLATES.md
    $0 --dry-run                        # Preview generation without writing
    $0 --output=/tmp/templates.md       # Write to custom location
    $0 --verbose --dry-run              # Show detailed processing

This script scans the templates directory and automatically generates comprehensive
documentation including template listings, usage examples, and cost considerations.
EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1" >&2
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --output=*)
                OUTPUT_FILE="${1#*=}"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

# Validate environment
validate_environment() {
    log_verbose "Validating environment..."

    if [[ ! -d "$TEMPLATES_DIR" ]]; then
        log_error "Templates directory not found: $TEMPLATES_DIR"
        exit 1
    fi

    if [[ ! -d "$PROJECT_ROOT" ]]; then
        log_error "Project root not found: $PROJECT_ROOT"
        exit 1
    fi

    # Check for required tools
    local missing_tools=()
    for tool in find sort; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    log_verbose "Environment validation successful"
}

# Get template count for category
get_template_count() {
    local category="$1"
    find "$TEMPLATES_DIR/$category" -name "main.tf" 2>/dev/null | wc -l | tr -d ' '
}

# Get templates for category
get_category_templates() {
    local category="$1"
    find "$TEMPLATES_DIR/$category" -name "main.tf" -exec dirname {} \; 2>/dev/null | \
        sed "s|$TEMPLATES_DIR/$category/||" | sort
}

# Generate category display name
get_category_display_name() {
    local category="$1"
    case "$category" in
        "ai-enhanced") echo "🤖 AI-Enhanced Templates" ;;
        "backend") echo "🖥️ Backend Templates" ;;
        "data-ml") echo "📊 Data/ML Templates" ;;
        "devops") echo "⚙️ DevOps Templates" ;;
        "frontend") echo "🌐 Frontend Templates" ;;
        "mobile") echo "📱 Mobile Templates" ;;
        *) echo "$(tr '[:lower:]' '[:upper:]' <<< ${category:0:1})${category:1} Templates" ;;
    esac
}

# Get resource impact estimate
get_resource_impact() {
    local template_name="$1"

    # High resource templates
    case "$template_name" in
        *"claude-flow-enterprise"*|*"crewai"*|*"jupyter"*) echo "High" ;;
        *"claude-flow-base"*|*"go"*|*"rust"*|*"svelte"*|*"docker"*) echo "Low" ;;
        *) echo "Medium" ;;
    esac
}

# Extract template description
get_template_description() {
    local template_name="$1"
    case "$template_name" in
        "claude-flow-base") echo "Basic Claude Code Flow integration for AI-assisted development" ;;
        "claude-flow-enterprise") echo "Enterprise Claude Code Flow with 87 MCP tools and advanced features" ;;
        "dotnet-core") echo ".NET Core development environment with C# tooling" ;;
        "go-fiber") echo "Go development with Fiber web framework" ;;
        "java-spring") echo "Java Spring Boot development environment" ;;
        "php-symfony-neuron") echo "PHP Symfony framework with Neuron integration" ;;
        "python-django-crewai") echo "Python Django with CrewAI multi-agent workflow capabilities" ;;
        "ruby-rails") echo "Ruby on Rails development environment" ;;
        "rust-actix") echo "Rust development with Actix web framework" ;;
        "jupyter-python") echo "Jupyter notebooks with comprehensive Python data science stack" ;;
        "r-studio") echo "R Studio for statistical computing and data analysis" ;;
        "docker-compose") echo "Docker Compose development environment" ;;
        "kubernetes-helm") echo "Kubernetes development with Helm package management" ;;
        "terraform-ansible") echo "Infrastructure as Code with Terraform and Ansible" ;;
        "angular") echo "Angular development environment with TypeScript" ;;
        "react-typescript") echo "React development with TypeScript" ;;
        "svelte-kit") echo "SvelteKit development environment" ;;
        "vue-nuxt") echo "Vue.js development with Nuxt.js framework" ;;
        "flutter") echo "Flutter cross-platform mobile development" ;;
        "ionic") echo "Ionic hybrid mobile development" ;;
        "react-native") echo "React Native mobile development" ;;
        *) echo "Development environment for $template_name" ;;
    esac
}

# Generate quick reference table
generate_quick_reference() {
    echo "## Quick Reference"
    echo ""
    echo "| Category | Template Name | Description | Cost Impact |"
    echo "|----------|---------------|-------------|-------------|"

    for category_dir in $(find "$TEMPLATES_DIR" -maxdepth 1 -type d | grep -v "^$TEMPLATES_DIR$" | sort); do
        local category=$(basename "$category_dir")
        local category_display=$(get_category_display_name "$category")
        local first_in_category=true

        for template_path in $(find "$category_dir" -name "main.tf" -exec dirname {} \; | sort); do
            local template_name=$(basename "$template_path")
            local description=$(get_template_description "$template_name")
            local impact=$(get_resource_impact "$template_name")

            if [[ "$first_in_category" == true ]]; then
                echo "| **${category_display%% Templates}** | \`$template_name\` | $description | $impact |"
                first_in_category=false
            else
                echo "| | \`$template_name\` | $description | $impact |"
            fi
        done
    done
}

# Generate category sections
generate_category_sections() {
    for category_dir in $(find "$TEMPLATES_DIR" -maxdepth 1 -type d | grep -v "^$TEMPLATES_DIR$" | sort); do
        local category=$(basename "$category_dir")
        local category_display=$(get_category_display_name "$category")
        local template_count=$(get_template_count "$category")

        echo ""
        echo "### $category_display ($template_count)"
        echo ""

        # Category description
        case "$category" in
            "ai-enhanced")
                echo "Advanced development environments with AI integration and enhanced capabilities."
                ;;
            "backend")
                echo "Server-side development environments with database integration and API frameworks."
                ;;
            "data-ml")
                echo "Data science and machine learning development environments with specialized tools."
                ;;
            "devops")
                echo "Infrastructure and deployment tool environments for DevOps workflows."
                ;;
            "frontend")
                echo "Modern frontend development environments with popular JavaScript frameworks."
                ;;
            "mobile")
                echo "Cross-platform mobile development environments with modern frameworks."
                ;;
        esac
        echo ""

        # Generate template details
        for template_path in $(find "$category_dir" -name "main.tf" -exec dirname {} \; | sort); do
            local template_name=$(basename "$template_path")
            local description=$(get_template_description "$template_name")
            local rel_path="${template_path#$PROJECT_ROOT/}"

            echo "#### \`$template_name\`"
            echo "- **Path**: \`$rel_path/\`"
            echo "- **Description**: $description"
            echo "- **Features**: [Auto-detected from template configuration]"
            echo "- **Resource Requirements**: $(get_resource_impact "$template_name") (CPU cores, RAM based on template type)"
            echo "- **Best For**: [Use case recommendations]"
            echo ""
        done
    done
}

# Get total template count
get_total_template_count() {
    find "$TEMPLATES_DIR" -name "main.tf" | wc -l | tr -d ' '
}

# Get total category count
get_total_category_count() {
    find "$TEMPLATES_DIR" -maxdepth 1 -type d | grep -v "^$TEMPLATES_DIR$" | wc -l | tr -d ' '
}

# Generate all template names for GitHub Actions
generate_template_list() {
    local templates=""
    local first=true

    for category_dir in $(find "$TEMPLATES_DIR" -maxdepth 1 -type d | grep -v "^$TEMPLATES_DIR$" | sort); do
        for template_path in $(find "$category_dir" -name "main.tf" -exec dirname {} \; | sort); do
            local template_name=$(basename "$template_path")
            if [[ "$first" == true ]]; then
                templates="'$template_name'"
                first=false
            else
                templates="$templates, '$template_name'"
            fi
        done
    done

    echo "$templates"
}

# Generate the complete docs/TEMPLATES.md content
generate_templates_md() {
    local total_templates=$(get_total_template_count)
    local total_categories=$(get_total_category_count)

    cat << EOF
# Coder Templates Directory

This document provides a comprehensive listing of all available Coder workspace templates in this project. These templates can be used with the \`--template\` parameter in deployment scripts and GitHub Actions.

## Overview

The project includes **$total_templates workspace templates** organized into **$total_categories categories**, providing development environments for modern web development, AI-enhanced workflows, data science, mobile development, and DevOps practices.

EOF

    generate_quick_reference

    cat << 'EOF'

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
EOF

    echo "          $(generate_template_list)"

    cat << 'EOF'
        ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Deploy Coder Template
        run: |
          ./scripts/lifecycle/setup.sh \
            --env=${{ inputs.environment }} \
            --template=${{ inputs.template }}
```

## Template Categories
EOF

    generate_category_sections

    cat << 'EOF'

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
# Generate/update docs/TEMPLATES.md from template directory scan
./scripts/utils/generate-template-docs.sh
```

Run this script after adding, removing, or modifying templates to keep the documentation current.

## Related Documentation

- [CLAUDE.md](../CLAUDE.md) - Project overview and architecture
- [Setup Guide](../scripts/lifecycle/setup.sh) - Environment deployment
- [Cost Calculator](../scripts/utils/cost-calculator.sh) - Resource cost analysis
- [Test Suite](../scripts/test-runner.sh) - Template validation and testing
EOF
}

# Main function
main() {
    log_info "Starting template documentation generation..."

    parse_args "$@"
    validate_environment

    local total_templates=$(get_total_template_count)
    local total_categories=$(get_total_category_count)

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would generate documentation for $total_templates templates in $total_categories categories"
        log_info "Output would be written to: $OUTPUT_FILE"
        echo ""
        echo "=== PREVIEW ==="
        generate_templates_md | head -50
        echo "..."
        echo "=== END PREVIEW ==="
        return 0
    fi

    log_info "Generating $OUTPUT_FILE..."
    generate_templates_md > "$OUTPUT_FILE"

    local file_size=$(wc -c < "$OUTPUT_FILE")
    log_success "Generated $OUTPUT_FILE (${file_size} bytes)"
    log_info "Documentation includes $total_templates templates in $total_categories categories"

    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        log_info "Template summary:"
        for category_dir in $(find "$TEMPLATES_DIR" -maxdepth 1 -type d | grep -v "^$TEMPLATES_DIR$" | sort); do
            local category=$(basename "$category_dir")
            local count=$(get_template_count "$category")
            log_verbose "  $category: $count templates"
        done
    fi
}

# Run main function with all arguments
main "$@"