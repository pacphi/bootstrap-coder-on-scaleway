#!/bin/bash

# Coder on Scaleway - Setup Script
# Complete environment provisioning with safety checks and validation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENVIRONMENT=""
TEMPLATE=""
DOMAIN_NAME=""
SUBDOMAIN=""
DRY_RUN=false
AUTO_APPROVE=false
BACKUP_EXISTING=true
ENABLE_MONITORING=false
ENABLE_CODER=true
CONFIG_FILE=""
LOG_FILE=""
START_TIME=$(date +%s)

# Default configuration
DEFAULT_SCALEWAY_REGION="fr-par"
DEFAULT_SCALEWAY_ZONE="fr-par-1"

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║        Production Setup Script        ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --env=ENV               Environment (dev|staging|prod) [required]
    --template=TEMPLATE     Workspace template to deploy [optional]
    --domain=DOMAIN         Custom domain name for SSL certificates [optional]
    --subdomain=SUBDOMAIN   Subdomain prefix (default: environment-specific)
    --dry-run              Preview changes without executing
    --auto-approve         Skip confirmation prompts
    --no-backup            Skip backup of existing resources
    --enable-monitoring    Enable monitoring stack
    --no-coder             Skip Coder deployment (infrastructure only)
    --config=FILE          Use custom configuration file
    --help                 Show this help message

Examples:
    $0 --env=dev --template=java-spring
    $0 --env=prod --domain=company.com --subdomain=coder
    $0 --env=staging --auto-approve --enable-monitoring --domain=example.com
    $0 --env=dev --dry-run

Environment Variables:
    SCW_ACCESS_KEY         Scaleway access key
    SCW_SECRET_KEY         Scaleway secret key
    SCW_DEFAULT_PROJECT_ID Scaleway project ID
    SCW_DEFAULT_ZONE       Scaleway zone (default: fr-par-1)
    SCW_DEFAULT_REGION     Scaleway region (default: fr-par)

Domain Configuration:
    Without --domain: Uses load balancer IP with self-signed certificates
    With --domain:    Generates Let's Encrypt SSL certificates automatically

    DNS Requirements (when using --domain):
    1. Create A record: [subdomain.]domain → load-balancer-ip
    2. Create CNAME record: *.[subdomain.]domain → [subdomain.]domain

    Default subdomains by environment:
    - dev: coder-dev
    - staging: coder-staging
    - prod: coder

EOF
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) echo -e "${PURPLE}[DEBUG]${NC} $message" ;;
        STEP)  echo -e "${CYAN}[STEP]${NC}  $message" ;;
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_logging() {
    local log_dir="${PROJECT_ROOT}/logs/setup"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-setup.log"
    log INFO "Logging to: $LOG_FILE"
}

check_prerequisites() {
    log STEP "Checking prerequisites..."

    local required_tools=("terraform" "kubectl" "helm" "jq" "curl")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log ERROR "Missing required tools: ${missing_tools[*]}"
        log ERROR "Please install missing tools and try again"
        exit 1
    fi

    # Check Scaleway credentials
    if [[ -z "${SCW_ACCESS_KEY:-}" || -z "${SCW_SECRET_KEY:-}" || -z "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
        log ERROR "Missing Scaleway credentials. Please set:"
        log ERROR "  - SCW_ACCESS_KEY"
        log ERROR "  - SCW_SECRET_KEY"
        log ERROR "  - SCW_DEFAULT_PROJECT_ID"
        exit 1
    fi

    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    local min_version="1.12.0"
    if ! printf '%s\n%s\n' "$min_version" "$tf_version" | sort -V -C; then
        log ERROR "Terraform version $tf_version is too old. Minimum required: $min_version"
        exit 1
    fi

    log INFO "✅ All prerequisites met"
}

validate_environment() {
    log STEP "Validating environment configuration..."

    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Environment: $ENVIRONMENT"
            ;;
        *)
            log ERROR "Invalid environment: $ENVIRONMENT"
            log ERROR "Must be one of: dev, staging, prod"
            exit 1
            ;;
    esac

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    if [[ ! -d "$env_dir" ]]; then
        log ERROR "Environment directory not found: $env_dir"
        exit 1
    fi

    # Check for new two-phase structure
    local infra_dir="${env_dir}/infra"
    local coder_dir="${env_dir}/coder"

    if [[ -d "$infra_dir" && -d "$coder_dir" ]]; then
        log INFO "Two-phase environment structure detected"

        if [[ ! -f "${infra_dir}/main.tf" ]]; then
            log ERROR "Infrastructure configuration not found: ${infra_dir}/main.tf"
            exit 1
        fi

        if [[ ! -f "${coder_dir}/main.tf" ]]; then
            log ERROR "Coder configuration not found: ${coder_dir}/main.tf"
            exit 1
        fi

        log INFO "✅ Two-phase environment configuration validated"
        log INFO "   Infrastructure: ${infra_dir}/main.tf"
        log INFO "   Coder: ${coder_dir}/main.tf"
    elif [[ -f "${env_dir}/main.tf" ]]; then
        log WARN "Legacy single-file environment structure detected"
        log WARN "Consider migrating to two-phase structure (infra/ and coder/ subdirectories)"
        log INFO "✅ Legacy environment configuration validated"
    else
        log ERROR "No valid environment configuration found"
        log ERROR "Expected either:"
        log ERROR "  - ${infra_dir}/main.tf and ${coder_dir}/main.tf (two-phase)"
        log ERROR "  - ${env_dir}/main.tf (legacy)"
        exit 1
    fi
}

validate_domain() {
    if [[ -n "$DOMAIN_NAME" ]]; then
        log STEP "Validating domain configuration..."

        # Basic domain validation
        if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$ ]]; then
            log ERROR "Invalid domain format: $DOMAIN_NAME"
            log ERROR "Domain must be a valid DNS name (e.g., example.com, my-site.co.uk)"
            exit 1
        fi

        # Set default subdomain if not provided
        if [[ -z "$SUBDOMAIN" ]]; then
            case "$ENVIRONMENT" in
                dev) SUBDOMAIN="coder-dev" ;;
                staging) SUBDOMAIN="coder-staging" ;;
                prod) SUBDOMAIN="coder" ;;
            esac
            log INFO "Using default subdomain for $ENVIRONMENT: $SUBDOMAIN"
        fi

        # Validate subdomain format
        if [[ ! "$SUBDOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$ ]]; then
            log ERROR "Invalid subdomain format: $SUBDOMAIN"
            log ERROR "Subdomain must contain only letters, numbers, and hyphens"
            exit 1
        fi

        local full_domain="${SUBDOMAIN}.${DOMAIN_NAME}"
        log INFO "✅ Domain configuration validated"
        log INFO "   Full domain: $full_domain"
        log INFO "   SSL certificates will be generated automatically"

        # DNS setup reminder
        log WARN "⚠️  DNS Configuration Required:"
        log WARN "   After deployment completes, configure DNS:"
        log WARN "   1. A record: $full_domain → <load-balancer-ip>"
        log WARN "   2. CNAME: *.$full_domain → $full_domain"

    else
        log INFO "No domain specified - using IP-based access"
        log INFO "SSL certificates will not be generated"
        log INFO "Users will see browser warnings for self-signed certificates"
    fi
}

discover_available_templates() {
    log STEP "Discovering available templates..."

    # Discover all templates dynamically
    local template_paths=()
    while IFS= read -r -d '' template_file; do
        # Extract template name from path: templates/category/name/main.tf -> name
        local template_name=$(dirname "$template_file" | sed 's|.*/templates/.*/||')
        if [[ -n "$template_name" ]]; then
            template_paths+=("$template_name:$template_file")
        fi
    done < <(find "${PROJECT_ROOT}/templates" -name "main.tf" -type f -print0)

    if [[ ${#template_paths[@]} -eq 0 ]]; then
        log ERROR "No templates found in ${PROJECT_ROOT}/templates"
        exit 1
    fi

    log INFO "✅ Discovered ${#template_paths[@]} available templates"
    printf '%s\n' "${template_paths[@]}" | sort
}

validate_template() {
    if [[ -n "$TEMPLATE" ]]; then
        log STEP "Validating workspace template: $TEMPLATE"

        # Find template path dynamically
        local template_path=""
        local found=false

        while IFS= read -r -d '' template_file; do
            local template_name=$(dirname "$template_file" | sed 's|.*/templates/.*/||')
            if [[ "$template_name" == "$TEMPLATE" ]]; then
                template_path=$(dirname "$template_file" | sed "s|${PROJECT_ROOT}/||")
                found=true
                break
            fi
        done < <(find "${PROJECT_ROOT}/templates" -name "main.tf" -type f -print0)

        if [[ "$found" != "true" ]]; then
            log ERROR "Unknown template: $TEMPLATE"
            log ERROR "Available templates:"
            discover_available_templates | sed 's|:.*||' | sort | sed 's/^/  - /'
            exit 1
        fi

        if [[ ! -f "${PROJECT_ROOT}/${template_path}/main.tf" ]]; then
            log ERROR "Template not found: ${PROJECT_ROOT}/${template_path}/main.tf"
            exit 1
        fi

        # Validate template Terraform syntax
        local template_dir="${PROJECT_ROOT}/${template_path}"
        if command -v terraform &> /dev/null; then
            cd "$template_dir"
            if ! terraform validate &> /dev/null; then
                log ERROR "Template Terraform validation failed for: $TEMPLATE"
                terraform validate
                exit 1
            fi
            cd - &> /dev/null
        fi

        log INFO "✅ Template validated: $TEMPLATE"
        log INFO "   Path: $template_path"
    else
        log INFO "No template specified. Available templates:"
        discover_available_templates | sed 's|:.*||' | sort | sed 's/^/  - /'
    fi
}

estimate_costs() {
    log STEP "Estimating infrastructure costs..."

    local costs_script="${PROJECT_ROOT}/scripts/utils/cost-calculator.sh"
    if [[ -f "$costs_script" ]]; then
        bash "$costs_script" --env="$ENVIRONMENT" --estimate-only
    else
        # Fallback cost estimation
        case "$ENVIRONMENT" in
            dev)
                log INFO "💰 Estimated monthly cost: €53.70"
                log INFO "   - Cluster: €30.40 (2x GP1-XS)"
                log INFO "   - Database: €12.30 (DB-DEV-S)"
                log INFO "   - Load Balancer: €8.90"
                log INFO "   - Networking: €2.10"
                ;;
            staging)
                log INFO "💰 Estimated monthly cost: €97.85"
                log INFO "   - Cluster: €68.40 (3x GP1-S)"
                log INFO "   - Database: €18.45 (DB-GP-S)"
                log INFO "   - Load Balancer: €8.90"
                log INFO "   - Networking: €2.10"
                ;;
            prod)
                log INFO "💰 Estimated monthly cost: €374.50"
                log INFO "   - Cluster: €228.00 (5x GP1-M)"
                log INFO "   - Database: €73.80 (DB-GP-M HA)"
                log INFO "   - Load Balancer: €45.60 (LB-GP-M)"
                log INFO "   - Networking: €2.10"
                log INFO "   - Storage: €25.00"
                ;;
        esac
    fi
}

backup_existing() {
    if [[ "$BACKUP_EXISTING" == "true" ]]; then
        log STEP "Backing up existing resources..."

        local backup_script="${PROJECT_ROOT}/scripts/lifecycle/backup.sh"
        if [[ -f "$backup_script" ]]; then
            bash "$backup_script" --env="$ENVIRONMENT" --auto
        else
            log WARN "Backup script not found, skipping backup"
        fi
    fi
}

run_pre_setup_hooks() {
    local hooks_dir="${PROJECT_ROOT}/scripts/hooks"
    local pre_setup_hook="${hooks_dir}/pre-setup.sh"

    if [[ -f "$pre_setup_hook" ]]; then
        log STEP "Running pre-setup hooks..."
        bash "$pre_setup_hook" --env="$ENVIRONMENT"
    fi
}

detect_environment_structure() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local infra_dir="${env_dir}/infra"
    local coder_dir="${env_dir}/coder"

    if [[ -d "$infra_dir" && -d "$coder_dir" ]]; then
        echo "two-phase"
    elif [[ -f "${env_dir}/main.tf" ]]; then
        echo "legacy"
    else
        echo "unknown"
    fi
}

terraform_init_infrastructure() {
    log STEP "Initializing Terraform for infrastructure (Phase 1)..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "two-phase" ]]; then
        local infra_dir="${env_dir}/infra"
        cd "$infra_dir"
        terraform init -upgrade
        log INFO "✅ Infrastructure Terraform initialized"
    else
        cd "$env_dir"
        terraform init -upgrade
        log INFO "✅ Legacy Terraform initialized"
    fi
}

terraform_plan_infrastructure() {
    log STEP "Creating infrastructure execution plan (Phase 1)..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local structure=$(detect_environment_structure)

    # Build terraform variables
    local tf_vars=()
    tf_vars+=("-var=scaleway_organization_id=${SCW_DEFAULT_ORGANIZATION_ID:-}")
    tf_vars+=("-var=scaleway_project_id=${SCW_DEFAULT_PROJECT_ID}")
    tf_vars+=("-var=scaleway_region=${SCW_DEFAULT_REGION:-${DEFAULT_SCALEWAY_REGION}}")
    tf_vars+=("-var=scaleway_zone=${SCW_DEFAULT_ZONE:-${DEFAULT_SCALEWAY_ZONE}}")

    # Add domain configuration if provided
    if [[ -n "$DOMAIN_NAME" ]]; then
        tf_vars+=("-var=domain_name=${DOMAIN_NAME}")
        if [[ -n "$SUBDOMAIN" ]]; then
            tf_vars+=("-var=subdomain=${SUBDOMAIN}")
        fi
        log INFO "Configuring domain: ${SUBDOMAIN}.${DOMAIN_NAME}"
    else
        tf_vars+=("-var=domain_name=")
        log INFO "Using IP-based access (no domain configured)"
    fi

    local plan_file=""
    if [[ "$structure" == "two-phase" ]]; then
        local infra_dir="${env_dir}/infra"
        cd "$infra_dir"
        plan_file="${infra_dir}/infra-tfplan"
        log INFO "Creating infrastructure plan (two-phase structure)"
    else
        cd "$env_dir"
        plan_file="${env_dir}/tfplan"
        log INFO "Creating infrastructure plan (legacy structure)"
    fi

    terraform plan -out="$plan_file" "${tf_vars[@]}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🔍 Infrastructure dry run complete. Plan saved to: $plan_file"
        return 0
    fi

    log INFO "✅ Infrastructure plan created successfully"
}

terraform_apply_infrastructure() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log STEP "Applying infrastructure configuration (Phase 1)..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local structure=$(detect_environment_structure)

    if [[ "$AUTO_APPROVE" == "false" ]]; then
        echo
        log WARN "⚠️  About to create/modify infrastructure in environment: $ENVIRONMENT"
        log WARN "⚠️  This will incur costs on your Scaleway account"
        echo
        read -p "Continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Setup cancelled by user"
            exit 0
        fi
    fi

    local plan_file=""
    if [[ "$structure" == "two-phase" ]]; then
        local infra_dir="${env_dir}/infra"
        cd "$infra_dir"
        plan_file="${infra_dir}/infra-tfplan"
    else
        cd "$env_dir"
        plan_file="${env_dir}/tfplan"
    fi

    terraform apply "$plan_file"
    log INFO "✅ Infrastructure deployed successfully (Phase 1)"
}

terraform_init_coder() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" != "two-phase" ]]; then
        log INFO "Skipping Coder initialization (legacy structure - already initialized)"
        return 0
    fi

    log STEP "Initializing Terraform for Coder application (Phase 2)..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local coder_dir="${env_dir}/coder"
    cd "$coder_dir"

    terraform init -upgrade
    log INFO "✅ Coder Terraform initialized"
}

terraform_plan_coder() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" != "two-phase" ]]; then
        log INFO "Skipping Coder planning (legacy structure - included in main plan)"
        return 0
    fi

    log STEP "Creating Coder application execution plan (Phase 2)..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local coder_dir="${env_dir}/coder"
    cd "$coder_dir"

    local plan_file="${coder_dir}/coder-tfplan"
    terraform plan -out="$plan_file"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🔍 Coder dry run complete. Plan saved to: $plan_file"
        return 0
    fi

    log INFO "✅ Coder plan created successfully"
}

terraform_apply_coder() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    local structure=$(detect_environment_structure)

    if [[ "$structure" != "two-phase" ]]; then
        log INFO "Skipping Coder application deployment (legacy structure - already deployed)"
        return 0
    fi

    if [[ "$ENABLE_CODER" == "false" ]]; then
        log INFO "Skipping Coder application deployment (--no-coder flag)"
        return 0
    fi

    log STEP "Applying Coder application configuration (Phase 2)..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local coder_dir="${env_dir}/coder"
    cd "$coder_dir"

    local plan_file="${coder_dir}/coder-tfplan"
    terraform apply "$plan_file"
    log INFO "✅ Coder application deployed successfully (Phase 2)"
}

get_cluster_info() {
    log STEP "Retrieving cluster information..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local structure=$(detect_environment_structure)

    # For two-phase structure, get kubeconfig from infrastructure directory
    if [[ "$structure" == "two-phase" ]]; then
        local infra_dir="${env_dir}/infra"
        cd "$infra_dir"
    else
        cd "$env_dir"
    fi

    # Extract kubeconfig
    terraform output -raw kubeconfig > "${HOME}/.kube/config-coder-${ENVIRONMENT}"
    chmod 600 "${HOME}/.kube/config-coder-${ENVIRONMENT}"

    # Set kubectl context
    export KUBECONFIG="${HOME}/.kube/config-coder-${ENVIRONMENT}"

    # Verify cluster access
    if kubectl cluster-info >/dev/null 2>&1; then
        log INFO "✅ Cluster access configured and verified"
        log INFO "Kubeconfig saved to: ${HOME}/.kube/config-coder-${ENVIRONMENT}"
    else
        log ERROR "Failed to connect to cluster"
        log ERROR "Check kubeconfig and cluster status"
        return 1
    fi
}

deploy_coder() {
    local structure=$(detect_environment_structure)

    if [[ "$ENABLE_CODER" == "false" ]]; then
        log INFO "Skipping Coder deployment (--no-coder flag)"
        return 0
    fi

    if [[ "$structure" == "two-phase" ]]; then
        log STEP "Validating Coder deployment..."

        local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
        local coder_dir="${env_dir}/coder"
        cd "$coder_dir"

        # Get access URLs from Terraform outputs
        local access_url=$(terraform output -raw coder_url 2>/dev/null || terraform output -raw access_url 2>/dev/null || echo "")
        local wildcard_url=$(terraform output -raw wildcard_access_url 2>/dev/null || echo "")

        if [[ -n "$access_url" ]]; then
            log INFO "✅ Coder deployed successfully"
            log INFO "Access URL: $access_url"
            if [[ -n "$wildcard_url" ]]; then
                log INFO "Wildcard URL: $wildcard_url"
            fi
        else
            log WARN "Coder deployment completed but access URL not available"
            log WARN "Check Terraform outputs in: $coder_dir"
        fi
    else
        log STEP "Validating legacy Coder deployment..."

        local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
        cd "$env_dir"

        # Get database connection string and access URL from Terraform outputs
        local db_connection=$(terraform output -raw database_connection_string 2>/dev/null || echo "")
        local access_url=$(terraform output -raw coder_url 2>/dev/null || echo "")
        local wildcard_url=$(terraform output -raw wildcard_access_url 2>/dev/null || echo "")

        if [[ -n "$access_url" ]]; then
            log INFO "✅ Legacy Coder deployment validated"
            log INFO "Access URL: $access_url"
            if [[ -n "$wildcard_url" ]]; then
                log INFO "Wildcard URL: $wildcard_url"
            fi
        else
            log WARN "Legacy Coder deployment issue - access URL not available"
            log WARN "Check Terraform outputs in: $env_dir"
        fi
    fi
}

deploy_template() {
    if [[ -z "$TEMPLATE" ]]; then
        log INFO "No workspace template specified, skipping template deployment"
        return 0
    fi

    log STEP "Deploying workspace template: $TEMPLATE"

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    # Get Coder access URL and admin credentials
    local coder_url=$(terraform output -raw access_url 2>/dev/null || terraform output -raw coder_url 2>/dev/null || echo "")
    local admin_username=$(terraform output -raw admin_username 2>/dev/null || echo "admin")
    local admin_password=$(terraform output -raw admin_password 2>/dev/null || echo "")

    if [[ -z "$coder_url" ]]; then
        log ERROR "Could not retrieve Coder URL from Terraform outputs"
        return 1
    fi

    # Find template path
    local template_path=""
    while IFS= read -r -d '' template_file; do
        local template_name=$(dirname "$template_file" | sed 's|.*/templates/.*/||')
        if [[ "$template_name" == "$TEMPLATE" ]]; then
            template_path=$(dirname "$template_file")
            break
        fi
    done < <(find "${PROJECT_ROOT}/templates" -name "main.tf" -type f -print0)

    if [[ -z "$template_path" ]]; then
        log ERROR "Could not find template path for: $TEMPLATE"
        return 1
    fi

    # Install Coder CLI if not present
    if ! command -v coder &> /dev/null; then
        log INFO "Installing Coder CLI..."
        curl -fsSL https://coder.com/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi

    # Configure Coder CLI
    export CODER_URL="$coder_url"
    export CODER_SESSION_TOKEN=""

    # Login to Coder
    log INFO "Logging in to Coder at: $coder_url"
    if [[ -n "$admin_password" ]]; then
        echo "$admin_password" | coder login "$coder_url" --username "$admin_username" --password-stdin
    else
        log WARN "No admin password available, manual login may be required"
        coder login "$coder_url"
    fi

    # Check if template already exists
    local template_exists=false
    if coder templates list | grep -q "^$TEMPLATE "; then
        template_exists=true
        log INFO "Template '$TEMPLATE' already exists, updating..."
    else
        log INFO "Creating new template: $TEMPLATE"
    fi

    # Deploy/update template
    cd "$template_path"
    if [[ "$template_exists" == "true" ]]; then
        coder templates update "$TEMPLATE" --directory="$template_path" --yes
    else
        coder templates create "$TEMPLATE" --directory="$template_path" --yes
    fi

    if [[ $? -eq 0 ]]; then
        log INFO "✅ Template '$TEMPLATE' deployed successfully"
        log INFO "   Template can be used to create workspaces at: $coder_url"

        # Show template info
        coder templates show "$TEMPLATE"
    else
        log ERROR "Failed to deploy template: $TEMPLATE"
        return 1
    fi

    cd - &> /dev/null
}

setup_monitoring() {
    if [[ "$ENABLE_MONITORING" == "false" ]]; then
        return 0
    fi

    log STEP "Setting up monitoring stack..."

    # Ensure kubectl is configured
    if [[ ! -f "${HOME}/.kube/config-coder-${ENVIRONMENT}" ]]; then
        log ERROR "Kubeconfig not found. Ensure cluster is deployed first."
        return 1
    fi

    export KUBECONFIG="${HOME}/.kube/config-coder-${ENVIRONMENT}"

    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

    # Add Prometheus Helm repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update

    # Deploy Prometheus
    log INFO "Deploying Prometheus..."
    cat > /tmp/prometheus-values.yaml <<EOF
server:
  persistentVolume:
    size: 20Gi
  retention: "30d"
  service:
    type: ClusterIP
  ingress:
    enabled: true
    hosts:
      - prometheus-${ENVIRONMENT}.${SCW_DEFAULT_REGION}.scw.cloud
alertmanager:
  enabled: true
  persistentVolume:
    size: 5Gi
nodeExporter:
  enabled: true
pushgateway:
  enabled: false
EOF

    helm upgrade --install prometheus prometheus-community/prometheus \
        --namespace monitoring \
        --values /tmp/prometheus-values.yaml \
        --wait --timeout=10m

    # Deploy Grafana
    log INFO "Deploying Grafana..."
    cat > /tmp/grafana-values.yaml <<EOF
persistence:
  enabled: true
  size: 10Gi
adminPassword: $(openssl rand -base64 32)
service:
  type: ClusterIP
ingress:
  enabled: true
  hosts:
    - grafana-${ENVIRONMENT}.${SCW_DEFAULT_REGION}.scw.cloud
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server.monitoring.svc.cluster.local
      access: proxy
      isDefault: true
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      orgId: 1
      folder: ''
      type: file
      disableDeletion: false
      editable: true
      options:
        path: /var/lib/grafana/dashboards/default
dashboards:
  default:
    kubernetes-cluster-monitoring:
      gnetId: 315
      revision: 3
      datasource: Prometheus
    coder-monitoring:
      gnetId: 1860
      revision: 27
      datasource: Prometheus
EOF

    helm upgrade --install grafana grafana/grafana \
        --namespace monitoring \
        --values /tmp/grafana-values.yaml \
        --wait --timeout=10m

    # Get Grafana admin password
    local grafana_password=$(kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

    # Configure ServiceMonitors for Coder
    cat > /tmp/coder-servicemonitor.yaml <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: coder-metrics
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: coder
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
EOF

    if kubectl get crd servicemonitors.monitoring.coreos.com &> /dev/null; then
        kubectl apply -f /tmp/coder-servicemonitor.yaml
    else
        log WARN "ServiceMonitor CRD not available, skipping Coder metrics scraping"
    fi

    # Clean up temp files
    rm -f /tmp/prometheus-values.yaml /tmp/grafana-values.yaml /tmp/coder-servicemonitor.yaml

    log INFO "✅ Monitoring stack deployed successfully"
    log INFO "   Prometheus: http://prometheus-${ENVIRONMENT}.${SCW_DEFAULT_REGION}.scw.cloud"
    log INFO "   Grafana: http://grafana-${ENVIRONMENT}.${SCW_DEFAULT_REGION}.scw.cloud"
    log INFO "   Grafana admin password: $grafana_password"
}

run_post_setup_hooks() {
    local hooks_dir="${PROJECT_ROOT}/scripts/hooks"
    local post_setup_hook="${hooks_dir}/post-setup.sh"

    if [[ -f "$post_setup_hook" ]]; then
        log STEP "Running post-setup hooks..."
        bash "$post_setup_hook" --env="$ENVIRONMENT"
    fi
}

validate_deployment() {
    log STEP "Validating deployment..."

    # Check cluster health
    if command -v kubectl &> /dev/null && [[ -n "${KUBECONFIG:-}" ]]; then
        local nodes_ready=$(kubectl get nodes --no-headers | grep -c " Ready ")
        log INFO "Cluster nodes ready: $nodes_ready"

        if kubectl get namespace coder &> /dev/null; then
            local pods_running=$(kubectl get pods -n coder --no-headers | grep -c " Running ")
            log INFO "Coder pods running: $pods_running"
        fi
    fi

    # Test access URLs
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    local access_url=$(terraform output -raw access_url 2>/dev/null || echo "")
    if [[ -n "$access_url" ]]; then
        log INFO "Coder will be available at: $access_url"
    fi

    log INFO "✅ Deployment validation completed"
}

print_summary() {
    log STEP "Setup Summary"

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local structure=$(detect_environment_structure)

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    if [[ "$structure" == "two-phase" ]]; then
        echo -e "${GREEN}🎉 Two-Phase Setup completed successfully! 🎉${NC}"
        echo
        echo -e "${WHITE}Environment:${NC} $ENVIRONMENT (Two-Phase Structure)"
        echo -e "${WHITE}Infrastructure:${NC} Phase 1 ✅"
        if [[ "$ENABLE_CODER" == "true" ]]; then
            echo -e "${WHITE}Coder Application:${NC} Phase 2 ✅"
        else
            echo -e "${WHITE}Coder Application:${NC} Skipped (--no-coder)"
        fi
    else
        echo -e "${GREEN}🎉 Legacy Setup completed successfully! 🎉${NC}"
        echo
        echo -e "${WHITE}Environment:${NC} $ENVIRONMENT (Legacy Structure)"
    fi

    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"

    if [[ -n "$TEMPLATE" ]]; then
        echo -e "${WHITE}Template:${NC} $TEMPLATE"
    fi

    # Extract and display connection info based on structure
    local access_url=""
    local admin_username=""
    local admin_password=""
    local load_balancer_ip=""

    if [[ "$structure" == "two-phase" ]]; then
        # Get infrastructure outputs from infra directory
        local infra_dir="${env_dir}/infra"
        cd "$infra_dir"
        load_balancer_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")

        # Get Coder outputs from coder directory (if enabled)
        if [[ "$ENABLE_CODER" == "true" ]]; then
            local coder_dir="${env_dir}/coder"
            cd "$coder_dir"
            access_url=$(terraform output -raw access_url 2>/dev/null || terraform output -raw coder_url 2>/dev/null || echo "")
            admin_username=$(terraform output -raw admin_username 2>/dev/null || echo "admin")
            admin_password=$(terraform output -raw admin_password 2>/dev/null || echo "")
        fi
    else
        # Legacy structure - get all outputs from main directory
        cd "$env_dir"
        access_url=$(terraform output -raw access_url 2>/dev/null || echo "")
        admin_username=$(terraform output -raw admin_username 2>/dev/null || echo "admin")
        admin_password=$(terraform output -raw admin_password 2>/dev/null || echo "")
        load_balancer_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")
    fi

    if [[ -n "$access_url" ]]; then
        echo
        echo -e "${YELLOW}📋 Access Information:${NC}"
        echo -e "   URL: ${CYAN}$access_url${NC}"
        echo -e "   Username: ${CYAN}$admin_username${NC}"
        if [[ -n "$admin_password" ]]; then
            echo -e "   Password: ${CYAN}[Retrieved from Terraform output]${NC}"
        fi
        if [[ -n "$load_balancer_ip" ]]; then
            echo -e "   Load Balancer IP: ${CYAN}$load_balancer_ip${NC}"
        fi
    fi

    # Show DNS configuration if domain was provided
    if [[ -n "$DOMAIN_NAME" && -n "$load_balancer_ip" ]]; then
        local full_domain="${SUBDOMAIN}.${DOMAIN_NAME}"
        echo
        echo -e "${YELLOW}🌐 DNS Configuration Required:${NC}"
        echo -e "${WHITE}   Configure these DNS records at your domain registrar:${NC}"
        echo
        echo -e "   ${CYAN}A Record:${NC}"
        echo -e "     Name: ${WHITE}$full_domain${NC}"
        echo -e "     Value: ${WHITE}$load_balancer_ip${NC}"
        echo -e "     TTL: ${WHITE}300${NC}"
        echo
        echo -e "   ${CYAN}CNAME Record (Wildcard):${NC}"
        echo -e "     Name: ${WHITE}*.$full_domain${NC}"
        echo -e "     Value: ${WHITE}$full_domain${NC}"
        echo -e "     TTL: ${WHITE}300${NC}"
        echo
        echo -e "${WHITE}   After DNS propagation (5-15 minutes):${NC}"
        echo -e "   • SSL certificates will be issued automatically"
        echo -e "   • Access Coder at: ${CYAN}https://$full_domain${NC}"
        echo -e "   • Workspaces will use: ${CYAN}https://*.${full_domain}${NC}"
    elif [[ -n "$DOMAIN_NAME" ]]; then
        echo
        echo -e "${YELLOW}⚠️  DNS Configuration Needed:${NC}"
        echo -e "   Domain configured but load balancer IP not available"
        echo -e "   Run: ${CYAN}terraform output load_balancer_ip${NC} to get the IP"
    fi

    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo "   1. Access Coder at the URL above"
    echo "   2. Create your first workspace using available templates"
    echo "   3. Start coding with Claude Code Flow integration!"

    if [[ -n "$TEMPLATE" ]]; then
        echo "   4. Your $TEMPLATE template is ready to use"
    fi

    echo
    echo -e "${YELLOW}📖 Useful Commands:${NC}"
    echo "   Check status: ./scripts/validate.sh --env=$ENVIRONMENT"
    echo "   View logs: tail -f $LOG_FILE"
    echo "   Scale cluster: ./scripts/scale.sh --env=$ENVIRONMENT --nodes=N"
    echo "   Teardown: ./scripts/teardown.sh --env=$ENVIRONMENT"
    echo
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Setup failed with exit code: $exit_code"
        log ERROR "Check the logs for details: $LOG_FILE"
    fi
}

main() {
    trap cleanup_on_exit EXIT

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --template=*)
                TEMPLATE="${1#*=}"
                shift
                ;;
            --domain=*)
                DOMAIN_NAME="${1#*=}"
                shift
                ;;
            --subdomain=*)
                SUBDOMAIN="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --no-backup)
                BACKUP_EXISTING=false
                shift
                ;;
            --enable-monitoring)
                ENABLE_MONITORING=true
                shift
                ;;
            --no-coder)
                ENABLE_CODER=false
                shift
                ;;
            --config=*)
                CONFIG_FILE="${1#*=}"
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$ENVIRONMENT" ]]; then
        log ERROR "Environment is required. Use --env=ENV"
        print_usage
        exit 1
    fi

    print_banner
    setup_logging

    log INFO "Starting setup for environment: $ENVIRONMENT"
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🔍 Running in dry-run mode"
    fi

    # Execute setup phases
    check_prerequisites
    validate_environment
    validate_domain
    validate_template
    estimate_costs

    if [[ "$DRY_RUN" == "false" ]]; then
        backup_existing
        run_pre_setup_hooks
    fi

    # Phase 1: Infrastructure deployment
    terraform_init_infrastructure
    terraform_plan_infrastructure
    terraform_apply_infrastructure

    if [[ "$DRY_RUN" == "false" ]]; then
        get_cluster_info
    fi

    # Phase 2: Coder application deployment (only for two-phase structure)
    local structure=$(detect_environment_structure)
    if [[ "$structure" == "two-phase" ]]; then
        terraform_init_coder
        terraform_plan_coder
        terraform_apply_coder
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        deploy_coder
        deploy_template
        setup_monitoring
        run_post_setup_hooks
        validate_deployment
        print_summary
    fi
}

# Run main function with all arguments
main "$@"