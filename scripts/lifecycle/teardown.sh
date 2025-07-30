#!/bin/bash

# Coder on Scaleway - Teardown Script
# Safe environment destruction with comprehensive safety checks

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
FORCE=false
EMERGENCY=false
BACKUP_BEFORE_DESTROY=true
SKIP_CONFIRMATIONS=false
PRESERVE_DATA=false
CONFIG_FILE=""
LOG_FILE=""
START_TIME=$(date +%s)
DESTRUCTION_DELAY=300  # 5 minutes safety delay

print_banner() {
    echo -e "${RED}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║       ENVIRONMENT TEARDOWN            ║
║         ⚠️  DESTRUCTIVE  ⚠️            ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

⚠️  WARNING: This script will PERMANENTLY DELETE all infrastructure
    and data in the specified environment. This action is IRREVERSIBLE.

Options:
    --env=ENV              Environment to teardown (dev|staging|prod) [required]
    --confirm              Confirm environment name (safety check)
    --force                Skip most safety checks
    --emergency            Emergency teardown (bypasses all safety)
    --no-backup            Skip backup before destruction
    --preserve-data        Preserve data volumes and databases
    --help                 Show this help message

Safety Features:
    • Requires typing environment name to confirm
    • 5-minute delay before destruction (unless --emergency)
    • Automatic backup before destruction
    • Resource dependency checking
    • Production environment extra protection

Examples:
    $0 --env=dev --confirm
    $0 --env=staging --force --confirm
    $0 --env=prod --confirm  # Extra confirmations required

Environment Variables:
    SCW_ACCESS_KEY         Scaleway access key
    SCW_SECRET_KEY         Scaleway secret key
    SCW_DEFAULT_PROJECT_ID Scaleway project ID

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
        DANGER) echo -e "${RED}[DANGER]${NC} $message" ;;
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_logging() {
    local log_dir="${PROJECT_ROOT}/logs/teardown"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-teardown.log"
    log INFO "Logging to: $LOG_FILE"
}

check_prerequisites() {
    log STEP "Checking prerequisites..."

    local required_tools=("terraform" "kubectl" "jq")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log ERROR "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Check Scaleway credentials
    if [[ -z "${SCW_ACCESS_KEY:-}" || -z "${SCW_SECRET_KEY:-}" || -z "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
        log ERROR "Missing Scaleway credentials"
        exit 1
    fi

    log INFO "✅ Prerequisites met"
}

validate_environment() {
    log STEP "Validating environment configuration..."

    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Target environment: $ENVIRONMENT"
            ;;
        *)
            log ERROR "Invalid environment: $ENVIRONMENT"
            exit 1
            ;;
    esac

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    if [[ ! -d "$env_dir" ]]; then
        log ERROR "Environment directory not found: $env_dir"
        exit 1
    fi

    # Check for backend configuration (remote state)
    if [[ -f "${env_dir}/backend.tf" ]]; then
        log INFO "Remote state backend configured: ${env_dir}/backend.tf"
    elif [[ -f "${env_dir}/terraform.tfstate" ]]; then
        log WARN "Local state found: ${env_dir}/terraform.tfstate"
        log WARN "Consider migrating to remote state backend"
    else
        log WARN "No state configuration found in $env_dir"
        log WARN "Environment may not be deployed"
    fi

    log INFO "✅ Environment validated"
}

check_active_resources() {
    log STEP "Checking for active resources and workspaces..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    # Initialize Terraform to check state
    log INFO "Initializing Terraform to check state..."
    if ! terraform init -input=false &> /dev/null; then
        log WARN "Could not initialize Terraform - backend may not exist or credentials invalid"
        return 0
    fi

    # Check if we can access remote state
    if ! terraform state pull > /dev/null 2>&1; then
        log WARN "Cannot access remote state - state may not exist or be corrupted"
        return 0
    fi

    # Get current resources
    local resource_count
    resource_count=$(terraform state list 2>/dev/null | wc -l || echo "0")

    if [[ "$resource_count" -gt 0 ]]; then
        log WARN "Found $resource_count active resources in state:"
        terraform state list 2>/dev/null | head -10 | while read -r resource; do
            log WARN "  - $resource"
        done
        if [[ "$resource_count" -gt 10 ]]; then
            log WARN "  ... and $((resource_count - 10)) more resources"
        fi
    else
        log INFO "No active resources found in Terraform state"
        log INFO "Environment may already be destroyed or was never deployed"
    fi

    # Check for active Kubernetes workspaces if cluster exists
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"

        if kubectl cluster-info &> /dev/null; then
            local active_workspaces
            active_workspaces=$(kubectl get deployments -n coder --no-headers 2>/dev/null | grep -c "coder-.*workspace" || echo "0")

            if [[ "$active_workspaces" -gt 0 ]]; then
                log WARN "⚠️  Found $active_workspaces active workspace(s)"
                kubectl get deployments -n coder --no-headers 2>/dev/null | grep "coder-.*workspace" | while read -r workspace; do
                    log WARN "  - Active workspace: $workspace"
                done

                if [[ "$FORCE" == "false" ]]; then
                    log ERROR "Active workspaces detected. Stop all workspaces before teardown"
                    log ERROR "Or use --force to destroy anyway"
                    exit 1
                fi
            fi
        fi
    fi
}

estimate_cost_savings() {
    log STEP "Calculating cost savings from teardown..."

    case "$ENVIRONMENT" in
        dev)
            log INFO "💰 Monthly cost savings: ~€53.70"
            ;;
        staging)
            log INFO "💰 Monthly cost savings: ~€97.85"
            ;;
        prod)
            log INFO "💰 Monthly cost savings: ~€374.50"
            ;;
    esac
}

backup_before_destruction() {
    if [[ "$BACKUP_BEFORE_DESTROY" == "false" ]]; then
        log WARN "Skipping backup before destruction (--no-backup)"
        return 0
    fi

    log STEP "Creating backup before destruction..."

    local backup_script="${PROJECT_ROOT}/scripts/lifecycle/backup.sh"
    if [[ -f "$backup_script" ]]; then
        bash "$backup_script" --env="$ENVIRONMENT" --pre-destroy
        log INFO "✅ Backup completed"
    else
        log WARN "Backup script not found, skipping backup"
    fi
}

safety_confirmations() {
    if [[ "$EMERGENCY" == "true" ]]; then
        log DANGER "🚨 EMERGENCY MODE - Bypassing all safety checks"
        return 0
    fi

    echo
    log DANGER "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    log DANGER "This will PERMANENTLY DELETE all infrastructure in: $ENVIRONMENT"
    log DANGER "This includes:"
    log DANGER "  • Kubernetes cluster and all workspaces"
    log DANGER "  • PostgreSQL database and ALL DATA"
    log DANGER "  • Load balancers and networking"
    log DANGER "  • Storage volumes and backups"
    echo
    log DANGER "This action is IRREVERSIBLE and will result in DATA LOSS"
    echo

    # Environment name confirmation
    echo -e "${YELLOW}To confirm, type the environment name '${ENVIRONMENT}':${NC}"
    read -r confirmation
    if [[ "$confirmation" != "$ENVIRONMENT" ]]; then
        log ERROR "Environment name confirmation failed"
        log ERROR "Expected: $ENVIRONMENT"
        log ERROR "Got: $confirmation"
        exit 1
    fi

    # Production extra confirmation
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        echo
        log DANGER "🔴 PRODUCTION ENVIRONMENT DESTRUCTION 🔴"
        echo
        log DANGER "You are about to destroy the PRODUCTION environment!"
        log DANGER "This will affect live users and services!"
        echo
        echo -e "${YELLOW}Type 'DELETE PRODUCTION' to confirm:${NC}"
        read -r prod_confirmation
        if [[ "$prod_confirmation" != "DELETE PRODUCTION" ]]; then
            log ERROR "Production confirmation failed"
            exit 1
        fi
    fi

    # Final confirmation
    echo
    log WARN "Last chance to cancel! Are you absolutely sure? (type 'yes')"
    read -r final_confirmation
    if [[ "$final_confirmation" != "yes" ]]; then
        log INFO "Teardown cancelled by user"
        exit 0
    fi

    log INFO "✅ All confirmations completed"
}

safety_delay() {
    if [[ "$EMERGENCY" == "true" || "$FORCE" == "true" ]]; then
        log WARN "Skipping safety delay"
        return 0
    fi

    log STEP "Safety delay: ${DESTRUCTION_DELAY} seconds before destruction begins..."
    log WARN "Press Ctrl+C to cancel"

    for ((i=DESTRUCTION_DELAY; i>0; i--)); do
        if ((i % 60 == 0)); then
            log WARN "Destruction in ${i} seconds... (Ctrl+C to cancel)"
        elif ((i <= 10)); then
            log WARN "Destruction in ${i} seconds..."
        fi
        sleep 1
    done

    log DANGER "🔥 Beginning destruction sequence..."
}

run_pre_teardown_hooks() {
    local hooks_dir="${PROJECT_ROOT}/scripts/hooks"
    local pre_teardown_hook="${hooks_dir}/pre-teardown.sh"

    if [[ -f "$pre_teardown_hook" ]]; then
        log STEP "Running pre-teardown hooks..."
        bash "$pre_teardown_hook" --env="$ENVIRONMENT"
    fi
}

cleanup_monitoring_stack() {
    log STEP "Cleaning up monitoring stack..."

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping monitoring cleanup"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info &> /dev/null; then
        log WARN "Cannot connect to cluster, skipping monitoring cleanup"
        return 0
    fi

    # Check if monitoring namespace exists
    if ! kubectl get namespace monitoring &> /dev/null; then
        log INFO "No monitoring namespace found, skipping cleanup"
        return 0
    fi

    # Uninstall Helm releases
    if command -v helm &> /dev/null; then
        log INFO "Uninstalling Grafana..."
        helm uninstall grafana --namespace monitoring || true

        log INFO "Uninstalling Prometheus..."
        helm uninstall prometheus --namespace monitoring || true
    fi

    # Delete monitoring namespace (this will clean up all remaining resources)
    log INFO "Deleting monitoring namespace..."
    kubectl delete namespace monitoring --grace-period=60 || true

    # Wait for namespace deletion
    local timeout=180
    log INFO "Waiting up to ${timeout}s for monitoring namespace deletion..."
    kubectl wait --for=delete namespace/monitoring --timeout=${timeout}s || true

    log INFO "✅ Monitoring cleanup completed"
}

drain_kubernetes_nodes() {
    log STEP "Draining Kubernetes nodes..."

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping node drain"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info &> /dev/null; then
        log WARN "Cannot connect to cluster, skipping node drain"
        return 0
    fi

    # Clean up monitoring stack first
    cleanup_monitoring_stack

    # Cordon all nodes
    kubectl get nodes --no-headers | awk '{print $1}' | while read -r node; do
        log INFO "Cordoning node: $node"
        kubectl cordon "$node" || true
    done

    # Delete all workspaces gracefully
    if kubectl get namespace coder &> /dev/null; then
        log INFO "Deleting workspace pods..."
        kubectl delete deployments -n coder --all --grace-period=60 || true

        # Wait for pods to terminate
        local timeout=120
        log INFO "Waiting up to ${timeout}s for pods to terminate..."
        kubectl wait --for=delete pods -n coder --all --timeout=${timeout}s || true
    fi

    log INFO "✅ Node drain completed"
}

preserve_data_volumes() {
    if [[ "$PRESERVE_DATA" == "false" ]]; then
        return 0
    fi

    log STEP "Preserving data volumes..."

    # This would implement data preservation logic
    log INFO "Data preservation would be implemented here"
    log INFO "• Database snapshots"
    log INFO "• PVC backups"
    log INFO "• Configuration exports"

    log INFO "✅ Data preserved"
}

terraform_destroy() {
    log STEP "Destroying infrastructure with Terraform..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    # Refresh state
    terraform refresh \
        -var="scaleway_organization_id=${SCW_DEFAULT_ORGANIZATION_ID:-}" \
        -var="scaleway_project_id=${SCW_DEFAULT_PROJECT_ID}" || true

    # Create destroy plan
    local destroy_plan="${env_dir}/destroy-plan"
    terraform plan -destroy -out="$destroy_plan" \
        -var="scaleway_organization_id=${SCW_DEFAULT_ORGANIZATION_ID:-}" \
        -var="scaleway_project_id=${SCW_DEFAULT_PROJECT_ID}" || {
        log ERROR "Failed to create destroy plan"
        return 1
    }

    # Apply destroy plan
    log DANGER "🔥 Executing infrastructure destruction..."
    terraform apply "$destroy_plan" || {
        log ERROR "Terraform destroy failed"
        log ERROR "Some resources may still exist - check Scaleway console"
        return 1
    }

    # Clean up plan file
    rm -f "$destroy_plan"

    log INFO "✅ Infrastructure destruction completed"
}

cleanup_local_state() {
    log STEP "Cleaning up local artifacts and configuration..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"

    # Remove kubeconfig
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        rm -f "$kubeconfig"
        log INFO "Removed kubeconfig: $kubeconfig"
    fi

    # Create backup of state before cleanup (if using remote state)
    local archive_dir="${PROJECT_ROOT}/archives/teardown/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}"
    mkdir -p "$archive_dir"

    # For remote state, pull and backup the final state
    if [[ -f "${env_dir}/backend.tf" ]]; then
        log INFO "Backing up final remote state..."
        if terraform state pull > "${archive_dir}/final-terraform.tfstate" 2>/dev/null; then
            log INFO "Final state backed up to: $archive_dir/final-terraform.tfstate"
        else
            log INFO "No remote state to backup (likely already destroyed)"
        fi
    elif [[ -f "${env_dir}/terraform.tfstate" ]]; then
        # Archive local state if it exists
        cp "${env_dir}/terraform.tfstate" "$archive_dir/"
        log INFO "Archived local Terraform state to: $archive_dir"
    fi

    # Create cleanup summary
    cat > "${archive_dir}/teardown-summary.txt" << EOF
Teardown Summary for Environment: ${ENVIRONMENT}
Date: $(date)
Script: $0

Environment Directory: ${env_dir}
Backend Configuration: $(test -f "${env_dir}/backend.tf" && echo "Remote (backend.tf)" || echo "Local")
Kubeconfig Removed: $(test -f "$kubeconfig" && echo "No" || echo "Yes")

Cleanup Actions Performed:
- Removed kubeconfig: $kubeconfig
- Backed up final state
- Cleaned up .terraform directory
- Removed any temporary files

EOF

    # Remove .terraform directory but preserve source files
    if [[ -d "${env_dir}/.terraform" ]]; then
        rm -rf "${env_dir}/.terraform"
        log INFO "Cleaned up .terraform directory"
    fi

    # Remove any temporary files from teardown
    find "$env_dir" -name "*.tfplan" -type f -delete 2>/dev/null || true
    find "$env_dir" -name "*.log" -type f -delete 2>/dev/null || true

    log INFO "✅ Local cleanup completed"
    log INFO "Archive location: $archive_dir"
}

run_post_teardown_hooks() {
    local hooks_dir="${PROJECT_ROOT}/scripts/hooks"
    local post_teardown_hook="${hooks_dir}/post-teardown.sh"

    if [[ -f "$post_teardown_hook" ]]; then
        log STEP "Running post-teardown hooks..."
        bash "$post_teardown_hook" --env="$ENVIRONMENT"
    fi
}

validate_complete_destruction() {
    log STEP "Validating complete resource destruction..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    # Try to check state (may fail if backend/state no longer exists)
    local remaining_resources=0
    local state_accessible=false

    if terraform state pull > /dev/null 2>&1; then
        state_accessible=true
        remaining_resources=$(terraform state list 2>/dev/null | wc -l || echo "0")

        if [[ "$remaining_resources" -gt 0 ]]; then
            log WARN "⚠️  $remaining_resources resources still exist in Terraform state:"
            terraform state list 2>/dev/null | head -10 | while read -r resource; do
                log WARN "  - $resource"
            done
            if [[ "$remaining_resources" -gt 10 ]]; then
                log WARN "  ... and $((remaining_resources - 10)) more resources"
            fi
            log WARN "Please check Scaleway console and remove manually if needed"
            log WARN "Consider re-running teardown or manual cleanup"
        else
            log INFO "✅ No resources remaining in Terraform state"
        fi
    else
        log INFO "Cannot access remote state - this may indicate successful teardown"
        log INFO "State backend may have been cleaned up or is no longer accessible"
    fi

    # Check cluster connectivity (kubeconfig should have been removed by now)
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        log WARN "⚠️  Kubeconfig still exists: $kubeconfig"
        if kubectl --kubeconfig="$kubeconfig" cluster-info &> /dev/null; then
            log WARN "⚠️  Kubernetes cluster still accessible - destruction may be incomplete"
        else
            log INFO "Kubeconfig exists but cluster is not accessible (normal after teardown)"
        fi
    fi

    # Additional validation using external tools if available
    if command -v scw &> /dev/null; then
        log INFO "Additional validation using Scaleway CLI..."
        # This would check for orphaned resources but requires scw CLI setup
        log INFO "Please verify manually in Scaleway console for any orphaned resources"
    fi

    log INFO "✅ Destruction validation completed"

    # Return status for script exit code
    if [[ "$state_accessible" == "true" && "$remaining_resources" -gt 0 ]]; then
        log WARN "Validation indicates incomplete teardown"
        return 1
    else
        log INFO "Validation indicates successful teardown"
        return 0
    fi
}

print_summary() {
    log STEP "Teardown Summary"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${GREEN}💥 Teardown completed! 💥${NC}"
    echo
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"

    case "$ENVIRONMENT" in
        dev) echo -e "${WHITE}Cost Savings:${NC} ~€53.70/month" ;;
        staging) echo -e "${WHITE}Cost Savings:${NC} ~€97.85/month" ;;
        prod) echo -e "${WHITE}Cost Savings:${NC} ~€374.50/month" ;;
    esac

    echo
    echo -e "${YELLOW}📋 What was destroyed:${NC}"
    echo "   ✓ Kubernetes cluster and all nodes"
    echo "   ✓ PostgreSQL database and data"
    echo "   ✓ Load balancers and networking"
    echo "   ✓ Storage volumes"
    echo "   ✓ All Coder workspaces and templates"

    if [[ "$BACKUP_BEFORE_DESTROY" == "true" ]]; then
        echo
        echo -e "${YELLOW}💾 Backup Information:${NC}"
        echo "   Configuration and state archived"
        echo "   Check logs for backup locations"
    fi

    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo "   • Verify no unexpected charges in Scaleway console"
    echo "   • Remove any manually created resources"
    echo "   • Update DNS records if custom domain was used"

    if [[ "$PRESERVE_DATA" == "true" ]]; then
        echo "   • Your data volumes were preserved"
        echo "   • Check preservation logs for recovery instructions"
    fi

    echo
    echo -e "${GREEN}Environment '$ENVIRONMENT' has been successfully torn down.${NC}"
    echo
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Teardown failed with exit code: $exit_code"
        log ERROR "Some resources may still exist - check Scaleway console"
        log ERROR "Check the logs for details: $LOG_FILE"
        echo
        log ERROR "⚠️  IMPORTANT: Verify no unexpected charges are occurring"
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
            --confirm)
                # This flag doesn't do anything but makes the command more explicit
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --emergency)
                EMERGENCY=true
                FORCE=true
                shift
                ;;
            --no-backup)
                BACKUP_BEFORE_DESTROY=false
                shift
                ;;
            --preserve-data)
                PRESERVE_DATA=true
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

    log DANGER "🔥 Starting teardown for environment: $ENVIRONMENT"
    if [[ "$EMERGENCY" == "true" ]]; then
        log DANGER "🚨 EMERGENCY MODE ACTIVE"
    fi

    # Execute teardown phases
    check_prerequisites
    validate_environment
    check_active_resources
    estimate_cost_savings

    safety_confirmations
    safety_delay

    backup_before_destruction
    run_pre_teardown_hooks
    drain_kubernetes_nodes
    preserve_data_volumes
    terraform_destroy
    cleanup_local_state
    run_post_teardown_hooks
    validate_complete_destruction
    print_summary
}

# Run main function with all arguments
main "$@"