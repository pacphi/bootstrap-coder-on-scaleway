#!/bin/bash

# Coder on Scaleway - Scaling Script
# Dynamic cluster scaling and resource management

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
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT=""
NODE_COUNT=""
NODE_TYPE=""
MIN_NODES=""
MAX_NODES=""
AUTO_APPROVE=false
DRY_RUN=false
SCALE_DOWN=false
VALIDATE_AFTER=true
TIMEOUT=600
LOG_FILE=""
START_TIME=$(date +%s)

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║          Cluster Scaling              ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Scale Kubernetes cluster nodes and manage auto-scaling configuration
for Coder environments on Scaleway.

Options:
    --env=ENV               Environment to scale (dev|staging|prod) [required]
    --nodes=COUNT           Target number of nodes
    --node-type=TYPE        Node instance type (GP1-XS|GP1-S|GP1-M)
    --min-nodes=COUNT       Minimum nodes for auto-scaling
    --max-nodes=COUNT       Maximum nodes for auto-scaling
    --auto-approve          Skip confirmation prompts
    --dry-run               Show scaling plan without applying changes
    --no-validate           Skip post-scaling validation
    --scale-down            Allow scaling down (with safety checks)
    --timeout=SECONDS       Timeout for scaling operations (default: 600)
    --help                  Show this help message

Examples:
    $0 --env=dev --nodes=3
    $0 --env=prod --nodes=7 --node-type=GP1-M --auto-approve
    $0 --env=staging --min-nodes=2 --max-nodes=10
    $0 --env=dev --nodes=1 --scale-down --confirm

Node Types and Costs (Paris region):
    GP1-XS:  4 vCPU, 16GB RAM  -  €66.43/month
    GP1-S:   8 vCPU, 32GB RAM  - €136.51/month
    GP1-M:  16 vCPU, 64GB RAM  - €274.48/month

Scaling Safety Features:
    • Workload impact analysis before scaling down
    • Resource utilization checks
    • Automatic pod rescheduling
    • Cost impact calculation
    • Rollback capability

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
    local log_dir="${PROJECT_ROOT}/logs/scaling"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-scaling.log"
    log INFO "Logging to: $LOG_FILE"
}

validate_environment() {
    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Target environment: $ENVIRONMENT"
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

    if [[ ! -f "${env_dir}/terraform.tfstate" ]]; then
        log ERROR "No Terraform state found. Environment may not be deployed."
        exit 1
    fi
}

get_current_state() {
    log STEP "Analyzing current cluster state..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    # Get current node information from Terraform
    local current_nodes=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type=="scaleway_k8s_pool") | .values.size' 2>/dev/null || echo "0")
    local current_node_type=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type=="scaleway_k8s_pool") | .values.node_type' 2>/dev/null || echo "unknown")
    local current_min_size=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type=="scaleway_k8s_pool") | .values.min_size' 2>/dev/null || echo "0")
    local current_max_size=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type=="scaleway_k8s_pool") | .values.max_size' 2>/dev/null || echo "0")

    # Get live cluster information if kubeconfig exists
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    local live_nodes="N/A"
    local ready_nodes="N/A"

    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"
        if kubectl cluster-info &>/dev/null; then
            live_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "N/A")
            ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready " | wc -l || echo "N/A")
        fi
    fi

    cd - &>/dev/null

    echo "CURRENT_NODES=$current_nodes"
    echo "CURRENT_NODE_TYPE=$current_node_type"
    echo "CURRENT_MIN_SIZE=$current_min_size"
    echo "CURRENT_MAX_SIZE=$current_max_size"
    echo "LIVE_NODES=$live_nodes"
    echo "READY_NODES=$ready_nodes"

    log INFO "✅ Current state analysis completed"
    log INFO "   Terraform nodes: $current_nodes (type: $current_node_type)"
    log INFO "   Auto-scaling: $current_min_size - $current_max_size nodes"
    log INFO "   Live cluster: $ready_nodes/$live_nodes nodes ready"
}

calculate_cost_impact() {
    local current_nodes="$1"
    local current_type="$2"
    local new_nodes="$3"
    local new_type="$4"

    log STEP "Calculating cost impact..."

    # Node type costs per month (Paris region)
    declare -A node_costs
    node_costs["GP1-XS"]=66.43
    node_costs["GP1-S"]=136.51
    node_costs["GP1-M"]=274.48

    local current_cost=$(echo "scale=2; $current_nodes * ${node_costs[$current_type]:-0}" | bc 2>/dev/null || echo "0")
    local new_cost=$(echo "scale=2; $new_nodes * ${node_costs[$new_type]:-0}" | bc 2>/dev/null || echo "0")
    local cost_difference=$(echo "scale=2; $new_cost - $current_cost" | bc 2>/dev/null || echo "0")

    log INFO "💰 Cost Analysis:"
    log INFO "   Current: $current_nodes × $current_type = €${current_cost}/month"
    log INFO "   New:     $new_nodes × $new_type = €${new_cost}/month"

    if (( $(echo "$cost_difference > 0" | bc -l) )); then
        log WARN "   Impact: +€${cost_difference}/month (increase)"
    elif (( $(echo "$cost_difference < 0" | bc -l) )); then
        cost_difference=${cost_difference#-}  # Remove negative sign
        log INFO "   Impact: -€${cost_difference}/month (savings)"
    else
        log INFO "   Impact: No cost change"
    fi

    echo "$cost_difference"
}

check_workload_impact() {
    local current_nodes="$1"
    local new_nodes="$2"

    log STEP "Analyzing workload impact..."

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping workload analysis"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info &>/dev/null; then
        log WARN "Cannot connect to cluster, skipping workload analysis"
        return 0
    fi

    # Get current workload information
    local total_pods=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l || echo "0")
    local running_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep " Running " | wc -l || echo "0")
    local coder_workspaces=$(kubectl get pods -n coder --no-headers 2>/dev/null | grep -c "workspace" || echo "0")

    log INFO "📊 Current Workload:"
    log INFO "   Total pods: $total_pods"
    log INFO "   Running pods: $running_pods"
    log INFO "   Active workspaces: $coder_workspaces"

    # Check resource utilization if scaling down
    if [[ "$new_nodes" -lt "$current_nodes" ]]; then
        log WARN "⚠️  Scaling Down Analysis:"

        # Check if workspaces might be affected
        if [[ "$coder_workspaces" -gt 0 ]]; then
            log WARN "   $coder_workspaces active workspaces may be rescheduled"

            if [[ "$SCALE_DOWN" != "true" ]]; then
                log ERROR "Scaling down with active workspaces requires --scale-down flag"
                log ERROR "This ensures you acknowledge potential workspace disruption"
                exit 1
            fi
        fi

        # Check node resource utilization
        if kubectl top nodes &>/dev/null; then
            log INFO "   Node utilization check:"
            kubectl top nodes --no-headers | while read -r node cpu memory; do
                log INFO "     $node: CPU=${cpu}, Memory=${memory}"
            done
        fi
    fi

    log INFO "✅ Workload impact analysis completed"
}

create_scaling_plan() {
    local current_nodes="$1"
    local current_type="$2"
    local new_nodes="$3"
    local new_type="$4"

    log STEP "Creating scaling plan..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local plan_file="${env_dir}/scaling-plan.json"

    cat > "$plan_file" <<EOF
{
  "scaling_plan": {
    "environment": "$ENVIRONMENT",
    "timestamp": "$(date -Iseconds)",
    "current_state": {
      "nodes": $current_nodes,
      "node_type": "$current_type",
      "min_nodes": ${MIN_NODES:-$current_nodes},
      "max_nodes": ${MAX_NODES:-$current_nodes}
    },
    "target_state": {
      "nodes": $new_nodes,
      "node_type": "$new_type",
      "min_nodes": ${MIN_NODES:-$new_nodes},
      "max_nodes": ${MAX_NODES:-$new_nodes}
    },
    "operation": "$([ "$new_nodes" -gt "$current_nodes" ] && echo "scale_up" || echo "scale_down")",
    "dry_run": $DRY_RUN,
    "auto_approve": $AUTO_APPROVE
  }
}
EOF

    log INFO "✅ Scaling plan created: $plan_file"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🔍 Dry Run - Scaling Plan Preview:"
        log INFO "   Current: $current_nodes × $current_type"
        log INFO "   Target:  $new_nodes × $new_type"
        [[ -n "$MIN_NODES" ]] && log INFO "   Auto-scale min: $MIN_NODES"
        [[ -n "$MAX_NODES" ]] && log INFO "   Auto-scale max: $MAX_NODES"
        return 0
    fi

    echo "$plan_file"
}

apply_terraform_changes() {
    local plan_file="$1"

    log STEP "Applying Terraform changes..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    # Update Terraform variables
    local tfvars_file="scaling.tfvars"
    cat > "$tfvars_file" <<EOF
# Auto-generated scaling configuration
# Generated: $(date)

EOF

    [[ -n "$NODE_COUNT" ]] && echo "node_count = $NODE_COUNT" >> "$tfvars_file"
    [[ -n "$NODE_TYPE" ]] && echo "node_type = \"$NODE_TYPE\"" >> "$tfvars_file"
    [[ -n "$MIN_NODES" ]] && echo "min_nodes = $MIN_NODES" >> "$tfvars_file"
    [[ -n "$MAX_NODES" ]] && echo "max_nodes = $MAX_NODES" >> "$tfvars_file"

    # Create Terraform plan
    local tf_plan_file="scaling.tfplan"
    if terraform plan -var-file="$tfvars_file" -out="$tf_plan_file"; then
        log INFO "✅ Terraform plan created successfully"
    else
        log ERROR "Terraform plan creation failed"
        cd - &>/dev/null
        return 1
    fi

    # Apply if not dry run
    if [[ "$AUTO_APPROVE" == "false" ]]; then
        echo
        log WARN "⚠️  About to apply scaling changes to: $ENVIRONMENT"
        echo
        read -p "Continue with scaling? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Scaling cancelled by user"
            rm -f "$tfvars_file" "$tf_plan_file"
            cd - &>/dev/null
            return 0
        fi
    fi

    # Apply the plan
    log INFO "Applying Terraform changes..."
    if timeout "$TIMEOUT" terraform apply "$tf_plan_file"; then
        log INFO "✅ Terraform changes applied successfully"
    else
        log ERROR "Terraform apply failed"
        cd - &>/dev/null
        return 1
    fi

    # Clean up
    rm -f "$tfvars_file" "$tf_plan_file"
    cd - &>/dev/null

    log INFO "✅ Scaling operation completed"
}

wait_for_nodes() {
    log STEP "Waiting for nodes to become ready..."

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping node readiness check"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    local target_nodes=${NODE_COUNT:-1}
    local waited=0
    local max_wait=600  # 10 minutes

    while [[ $waited -lt $max_wait ]]; do
        if kubectl cluster-info &>/dev/null; then
            local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready " | wc -l || echo "0")
            local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")

            log INFO "Node status: $ready_nodes/$total_nodes ready (target: $target_nodes)"

            if [[ "$ready_nodes" -eq "$target_nodes" ]]; then
                log INFO "✅ All target nodes are ready"
                return 0
            fi
        fi

        sleep 30
        waited=$((waited + 30))
        log INFO "Waiting for nodes... (${waited}s/${max_wait}s)"
    done

    log WARN "Timeout waiting for nodes to become ready"
    return 1
}

reschedule_pods() {
    log STEP "Rescheduling pods after scaling..."

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping pod rescheduling"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    # Check for pending pods
    local pending_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep " Pending " | wc -l || echo "0")

    if [[ "$pending_pods" -gt 0 ]]; then
        log WARN "$pending_pods pods are pending - checking resource availability"

        # List pending pods
        kubectl get pods -A --no-headers 2>/dev/null | grep " Pending " | while read -r namespace pod rest; do
            log INFO "Pending pod: $namespace/$pod"
        done

        # Wait a bit for scheduler to work
        sleep 60

        # Check again
        pending_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep " Pending " | wc -l || echo "0")
        if [[ "$pending_pods" -gt 0 ]]; then
            log WARN "$pending_pods pods still pending after rescheduling"
        else
            log INFO "✅ All pods successfully rescheduled"
        fi
    else
        log INFO "✅ No pending pods found"
    fi
}

validate_scaling() {
    if [[ "$VALIDATE_AFTER" == "false" ]]; then
        return 0
    fi

    log STEP "Validating scaling results..."

    # Run validation script if it exists
    local validate_script="${PROJECT_ROOT}/scripts/validate.sh"
    if [[ -f "$validate_script" ]]; then
        log INFO "Running post-scaling validation..."
        if "$validate_script" --env="$ENVIRONMENT" --components=cluster --quick; then
            log INFO "✅ Post-scaling validation passed"
        else
            log WARN "Post-scaling validation found issues"
        fi
    else
        log WARN "Validation script not found, skipping validation"
    fi
}

rollback_scaling() {
    local plan_file="$1"

    log STEP "Rolling back scaling changes..."

    if [[ ! -f "$plan_file" ]]; then
        log ERROR "Cannot rollback: scaling plan file not found"
        return 1
    fi

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    # Extract previous state from plan file
    local prev_nodes=$(jq -r '.scaling_plan.current_state.nodes' "$plan_file")
    local prev_type=$(jq -r '.scaling_plan.current_state.node_type' "$plan_file")

    log INFO "Rolling back to: $prev_nodes × $prev_type"

    # Create rollback tfvars
    local rollback_tfvars="rollback.tfvars"
    cat > "$rollback_tfvars" <<EOF
# Rollback configuration
node_count = $prev_nodes
node_type = "$prev_type"
EOF

    if terraform plan -var-file="$rollback_tfvars" -out="rollback.tfplan" && \
       terraform apply "rollback.tfplan"; then
        log INFO "✅ Rollback completed successfully"
        rm -f "$rollback_tfvars" "rollback.tfplan"
    else
        log ERROR "Rollback failed"
        rm -f "$rollback_tfvars" "rollback.tfplan"
        return 1
    fi

    cd - &>/dev/null
}

print_summary() {
    log STEP "Scaling Summary"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}🔍 Scaling plan completed (dry run) 🔍${NC}"
    else
        echo -e "${GREEN}🚀 Cluster scaling completed! 🚀${NC}"
    fi
    echo

    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"

    if [[ -n "$NODE_COUNT" ]]; then
        echo -e "${WHITE}Target Nodes:${NC} $NODE_COUNT"
    fi
    if [[ -n "$NODE_TYPE" ]]; then
        echo -e "${WHITE}Node Type:${NC} $NODE_TYPE"
    fi
    if [[ -n "$MIN_NODES" ]]; then
        echo -e "${WHITE}Auto-scale Min:${NC} $MIN_NODES"
    fi
    if [[ -n "$MAX_NODES" ]]; then
        echo -e "${WHITE}Auto-scale Max:${NC} $MAX_NODES"
    fi

    # Show current cluster status
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"
        if kubectl cluster-info &>/dev/null; then
            local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready " | wc -l || echo "N/A")
            local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "N/A")
            echo -e "${WHITE}Current Status:${NC} $ready_nodes/$total_nodes nodes ready"
        fi
    fi

    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "   • Review the scaling plan above"
        echo "   • Re-run without --dry-run to apply changes"
        echo "   • Consider cost impact before proceeding"
    else
        echo "   • Monitor cluster health and performance"
        echo "   • Verify workspaces are functioning normally"
        echo "   • Update resource quotas if needed"
        echo "   • Consider adjusting auto-scaling policies"
    fi

    echo "   • Run validation: ./scripts/validate.sh --env=$ENVIRONMENT"
    echo
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && "$DRY_RUN" == "false" ]]; then
        log ERROR "Scaling operation failed with exit code: $exit_code"
        log ERROR "Check the logs for details: ${LOG_FILE:-N/A}"

        # Offer rollback if we have a plan file
        local plan_file="${PROJECT_ROOT}/environments/${ENVIRONMENT}/scaling-plan.json"
        if [[ -f "$plan_file" && "$AUTO_APPROVE" == "false" ]]; then
            echo
            read -p "Attempt to rollback scaling changes? (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rollback_scaling "$plan_file"
            fi
        fi
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
            --nodes=*)
                NODE_COUNT="${1#*=}"
                shift
                ;;
            --node-type=*)
                NODE_TYPE="${1#*=}"
                shift
                ;;
            --min-nodes=*)
                MIN_NODES="${1#*=}"
                shift
                ;;
            --max-nodes=*)
                MAX_NODES="${1#*=}"
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --scale-down)
                SCALE_DOWN=true
                shift
                ;;
            --no-validate)
                VALIDATE_AFTER=false
                shift
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
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

    if [[ -z "$NODE_COUNT" && -z "$MIN_NODES" && -z "$MAX_NODES" ]]; then
        log ERROR "At least one scaling parameter is required (--nodes, --min-nodes, or --max-nodes)"
        print_usage
        exit 1
    fi

    print_banner
    setup_logging

    log INFO "Starting cluster scaling for environment: $ENVIRONMENT"
    [[ "$DRY_RUN" == "true" ]] && log INFO "🔍 Running in dry-run mode"

    validate_environment

    # Get current state
    local state_info=$(get_current_state)
    eval "$state_info"  # Sets CURRENT_NODES, CURRENT_NODE_TYPE, etc.

    # Set defaults
    NODE_COUNT=${NODE_COUNT:-$CURRENT_NODES}
    NODE_TYPE=${NODE_TYPE:-$CURRENT_NODE_TYPE}

    # Validate scaling parameters
    if [[ "$NODE_COUNT" -lt 1 ]]; then
        log ERROR "Node count must be at least 1"
        exit 1
    fi

    # Safety check for scaling down
    if [[ "$NODE_COUNT" -lt "$CURRENT_NODES" && "$SCALE_DOWN" != "true" ]]; then
        log ERROR "Scaling down requires --scale-down flag for safety"
        exit 1
    fi

    # Calculate cost impact
    local cost_diff=$(calculate_cost_impact "$CURRENT_NODES" "$CURRENT_NODE_TYPE" "$NODE_COUNT" "$NODE_TYPE")

    # Analyze workload impact
    check_workload_impact "$CURRENT_NODES" "$NODE_COUNT"

    # Create scaling plan
    local plan_file=$(create_scaling_plan "$CURRENT_NODES" "$CURRENT_NODE_TYPE" "$NODE_COUNT" "$NODE_TYPE")

    if [[ "$DRY_RUN" == "true" ]]; then
        print_summary
        exit 0
    fi

    # Execute scaling
    apply_terraform_changes "$plan_file"
    wait_for_nodes
    reschedule_pods
    validate_scaling
    print_summary
}

# Run main function with all arguments
main "$@"