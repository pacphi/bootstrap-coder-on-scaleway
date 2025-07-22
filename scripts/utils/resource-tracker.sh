#!/bin/bash

# Coder on Scaleway - Resource Tracker
# Track and inventory all resources across environments

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
OUTPUT_FORMAT="table"
EXPORT_FILE=""
INCLUDE_COSTS=true
DETAILED_VIEW=false
SHOW_TERRAFORM_STATE=false

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║          Resource Tracker             ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --env=ENV              Environment to track (dev|staging|prod|all)
    --format=FORMAT        Output format (table|json|csv) [default: table]
    --export=FILE          Export inventory to file
    --detailed             Show detailed resource information
    --show-terraform       Include Terraform state information
    --no-costs             Exclude cost information
    --help                 Show this help message

Examples:
    $0 --env=all
    $0 --env=prod --detailed
    $0 --env=staging --export=staging-inventory.json --format=json
    $0 --env=dev --show-terraform

Output:
    Lists all resources including:
    • Kubernetes clusters and nodes
    • PostgreSQL databases
    • Load balancers and networking
    • Storage volumes
    • Estimated costs

EOF
}

log() {
    local level="$1"
    shift
    local message="$*"

    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) echo -e "${PURPLE}[DEBUG]${NC} $message" ;;
        STEP)  echo -e "${CYAN}[STEP]${NC}  $message" ;;
    esac
}

check_environment_exists() {
    local env="$1"
    local env_dir="${PROJECT_ROOT}/environments/${env}"

    if [[ ! -d "$env_dir" ]]; then
        return 1
    fi

    if [[ ! -f "${env_dir}/main.tf" ]]; then
        return 1
    fi

    return 0
}

get_terraform_resources() {
    local env="$1"
    local env_dir="${PROJECT_ROOT}/environments/${env}"

    if [[ ! -d "$env_dir" ]]; then
        echo "[]"
        return
    fi

    cd "$env_dir"

    # Check if Terraform is initialized
    if [[ ! -d ".terraform" ]]; then
        echo "[]"
        return
    fi

    # Get resources from state
    local resources=()

    if terraform state list &>/dev/null; then
        while IFS= read -r resource; do
            if [[ -n "$resource" ]]; then
                local resource_info
                resource_info=$(terraform state show "$resource" 2>/dev/null | head -20 || echo "")

                # Extract basic info
                local resource_type=$(echo "$resource" | cut -d. -f1)
                local resource_name=$(echo "$resource" | cut -d. -f2)

                # Try to get resource ID and status
                local resource_id=""
                local resource_status=""

                if echo "$resource_info" | grep -q "id.*="; then
                    resource_id=$(echo "$resource_info" | grep "id.*=" | head -1 | sed 's/.*= "\([^"]*\)".*/\1/' || echo "")
                fi

                if echo "$resource_info" | grep -q "status.*="; then
                    resource_status=$(echo "$resource_info" | grep "status.*=" | head -1 | sed 's/.*= "\([^"]*\)".*/\1/' || echo "running")
                fi

                resources+=("$resource_type:$resource_name:$resource_id:$resource_status")
            fi
        done < <(terraform state list 2>/dev/null)
    fi

    printf '%s\n' "${resources[@]}"
}

get_cluster_info() {
    local env="$1"
    local env_dir="${PROJECT_ROOT}/environments/${env}"

    if [[ ! -d "$env_dir" ]]; then
        return
    fi

    cd "$env_dir"

    # Try to get cluster information from Terraform outputs
    local cluster_id=""
    local cluster_name=""
    local cluster_status=""
    local node_count=""

    if terraform output cluster_id &>/dev/null; then
        cluster_id=$(terraform output -raw cluster_id 2>/dev/null || echo "")
    fi

    if terraform output cluster_name &>/dev/null; then
        cluster_name=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    fi

    # Try to connect to cluster if kubeconfig exists
    local kubeconfig="${HOME}/.kube/config-coder-${env}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"

        if kubectl cluster-info &>/dev/null; then
            cluster_status="Running"
            node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        else
            cluster_status="Unreachable"
        fi
    fi

    echo "$cluster_id:$cluster_name:$cluster_status:$node_count"
}

get_database_info() {
    local env="$1"
    local env_dir="${PROJECT_ROOT}/environments/${env}"

    if [[ ! -d "$env_dir" ]]; then
        return
    fi

    cd "$env_dir"

    local db_endpoint=""
    local db_port=""
    local db_name=""
    local db_status="Unknown"

    if terraform output database_endpoint &>/dev/null; then
        db_endpoint=$(terraform output -raw database_endpoint 2>/dev/null || echo "")
    fi

    if terraform output database_port &>/dev/null; then
        db_port=$(terraform output -raw database_port 2>/dev/null || echo "")
    fi

    if terraform output database_name &>/dev/null; then
        db_name=$(terraform output -raw database_name 2>/dev/null || echo "")
    fi

    # Try to test database connectivity (basic check)
    if [[ -n "$db_endpoint" && -n "$db_port" ]]; then
        if timeout 3 bash -c "</dev/tcp/${db_endpoint}/${db_port}" 2>/dev/null; then
            db_status="Running"
        else
            db_status="Unreachable"
        fi
    fi

    echo "$db_endpoint:$db_port:$db_name:$db_status"
}

get_networking_info() {
    local env="$1"
    local env_dir="${PROJECT_ROOT}/environments/${env}"

    if [[ ! -d "$env_dir" ]]; then
        return
    fi

    cd "$env_dir"

    local lb_ip=""
    local access_url=""
    local vpc_id=""

    if terraform output load_balancer_ip &>/dev/null; then
        lb_ip=$(terraform output -raw load_balancer_ip 2>/dev/null || echo "")
    fi

    if terraform output access_url &>/dev/null; then
        access_url=$(terraform output -raw access_url 2>/dev/null || echo "")
    fi

    if terraform output vpc_id &>/dev/null; then
        vpc_id=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    fi

    echo "$lb_ip:$access_url:$vpc_id"
}

estimate_environment_cost() {
    local env="$1"

    # Use the cost calculator if available
    local cost_script="${PROJECT_ROOT}/scripts/utils/cost-calculator.sh"
    if [[ -f "$cost_script" ]]; then
        bash "$cost_script" --env="$env" --format=json 2>/dev/null | jq -r '.total_cost' 2>/dev/null || echo "0"
    else
        # Fallback estimates
        case "$env" in
            dev)     echo "53.70" ;;
            staging) echo "97.85" ;;
            prod)    echo "374.50" ;;
            *)       echo "0" ;;
        esac
    fi
}

print_environment_table() {
    local env="$1"

    log STEP "Environment: $env"
    echo

    # Get all resource information
    local cluster_info
    cluster_info=$(get_cluster_info "$env")
    local cluster_id=$(echo "$cluster_info" | cut -d: -f1)
    local cluster_name=$(echo "$cluster_info" | cut -d: -f2)
    local cluster_status=$(echo "$cluster_info" | cut -d: -f3)
    local node_count=$(echo "$cluster_info" | cut -d: -f4)

    local db_info
    db_info=$(get_database_info "$env")
    local db_endpoint=$(echo "$db_info" | cut -d: -f1)
    local db_port=$(echo "$db_info" | cut -d: -f2)
    local db_name=$(echo "$db_info" | cut -d: -f3)
    local db_status=$(echo "$db_info" | cut -d: -f4)

    local net_info
    net_info=$(get_networking_info "$env")
    local lb_ip=$(echo "$net_info" | cut -d: -f1)
    local access_url=$(echo "$net_info" | cut -d: -f2)
    local vpc_id=$(echo "$net_info" | cut -d: -f3)

    # Print resource table
    printf "%-20s %-30s %-15s %-10s\n" "RESOURCE TYPE" "IDENTIFIER" "STATUS" "DETAILS"
    printf "%s\n" "$(printf '%.0s-' {1..85})"

    # Kubernetes Cluster
    if [[ -n "$cluster_name" ]]; then
        printf "%-20s %-30s %-15s %-10s\n" "K8s Cluster" "${cluster_name:-N/A}" "${cluster_status:-Unknown}" "${node_count} nodes"
    else
        printf "%-20s %-30s %-15s %-10s\n" "K8s Cluster" "Not deployed" "N/A" ""
    fi

    # PostgreSQL Database
    if [[ -n "$db_name" ]]; then
        printf "%-20s %-30s %-15s %-10s\n" "PostgreSQL DB" "${db_name:-N/A}" "${db_status:-Unknown}" "${db_port:-5432}"
    else
        printf "%-20s %-30s %-15s %-10s\n" "PostgreSQL DB" "Not deployed" "N/A" ""
    fi

    # Load Balancer
    if [[ -n "$lb_ip" ]]; then
        printf "%-20s %-30s %-15s %-10s\n" "Load Balancer" "${lb_ip}" "Active" "HTTP/HTTPS"
    else
        printf "%-20s %-30s %-15s %-10s\n" "Load Balancer" "Not deployed" "N/A" ""
    fi

    # VPC/Networking
    if [[ -n "$vpc_id" ]]; then
        printf "%-20s %-30s %-15s %-10s\n" "VPC Network" "${vpc_id}" "Active" "Private"
    else
        printf "%-20s %-30s %-15s %-10s\n" "VPC Network" "Not deployed" "N/A" ""
    fi

    printf "%s\n" "$(printf '%.0s-' {1..85})"

    # Access Information
    if [[ -n "$access_url" ]]; then
        echo
        echo -e "${YELLOW}📡 Access Information:${NC}"
        echo "   Coder URL: $access_url"
        if [[ -n "$lb_ip" ]]; then
            echo "   Load Balancer IP: $lb_ip"
        fi
    fi

    # Cost Information
    if [[ "$INCLUDE_COSTS" == "true" ]]; then
        local estimated_cost
        estimated_cost=$(estimate_environment_cost "$env")
        echo
        echo -e "${YELLOW}💰 Estimated Monthly Cost: €${estimated_cost}${NC}"
    fi

    # Terraform State Information
    if [[ "$SHOW_TERRAFORM_STATE" == "true" ]]; then
        echo
        echo -e "${YELLOW}🏗️  Terraform Resources:${NC}"
        local tf_resources
        tf_resources=$(get_terraform_resources "$env")

        if [[ -n "$tf_resources" ]]; then
            echo "$tf_resources" | while IFS= read -r resource; do
                local type=$(echo "$resource" | cut -d: -f1)
                local name=$(echo "$resource" | cut -d: -f2)
                local id=$(echo "$resource" | cut -d: -f3)
                local status=$(echo "$resource" | cut -d: -f4)
                echo "   $type.$name ($status)"
            done
        else
            echo "   No Terraform resources found"
        fi
    fi

    echo
}

print_environment_json() {
    local env="$1"

    local cluster_info
    cluster_info=$(get_cluster_info "$env")
    local cluster_id=$(echo "$cluster_info" | cut -d: -f1)
    local cluster_name=$(echo "$cluster_info" | cut -d: -f2)
    local cluster_status=$(echo "$cluster_info" | cut -d: -f3)
    local node_count=$(echo "$cluster_info" | cut -d: -f4)

    local db_info
    db_info=$(get_database_info "$env")
    local db_endpoint=$(echo "$db_info" | cut -d: -f1)
    local db_port=$(echo "$db_info" | cut -d: -f2)
    local db_name=$(echo "$db_info" | cut -d: -f3)
    local db_status=$(echo "$db_info" | cut -d: -f4)

    local net_info
    net_info=$(get_networking_info "$env")
    local lb_ip=$(echo "$net_info" | cut -d: -f1)
    local access_url=$(echo "$net_info" | cut -d: -f2)
    local vpc_id=$(echo "$net_info" | cut -d: -f3)

    local estimated_cost
    estimated_cost=$(estimate_environment_cost "$env")

    cat << EOF
{
  "environment": "$env",
  "timestamp": "$(date -Iseconds)",
  "cluster": {
    "id": "$cluster_id",
    "name": "$cluster_name",
    "status": "$cluster_status",
    "node_count": $node_count
  },
  "database": {
    "endpoint": "$db_endpoint",
    "port": "$db_port",
    "name": "$db_name",
    "status": "$db_status"
  },
  "networking": {
    "load_balancer_ip": "$lb_ip",
    "access_url": "$access_url",
    "vpc_id": "$vpc_id"
  },
  "cost": {
    "estimated_monthly": $estimated_cost,
    "currency": "EUR"
  }
}
EOF
}

print_environment_csv() {
    local env="$1"

    local cluster_info
    cluster_info=$(get_cluster_info "$env")
    local cluster_name=$(echo "$cluster_info" | cut -d: -f2)
    local cluster_status=$(echo "$cluster_info" | cut -d: -f3)
    local node_count=$(echo "$cluster_info" | cut -d: -f4)

    local db_info
    db_info=$(get_database_info "$env")
    local db_name=$(echo "$db_info" | cut -d: -f3)
    local db_status=$(echo "$db_info" | cut -d: -f4)

    local net_info
    net_info=$(get_networking_info "$env")
    local lb_ip=$(echo "$net_info" | cut -d: -f1)
    local access_url=$(echo "$net_info" | cut -d: -f2)

    local estimated_cost
    estimated_cost=$(estimate_environment_cost "$env")

    echo "Environment,Resource Type,Name,Status,Details,Monthly Cost"
    echo "$env,Kubernetes Cluster,$cluster_name,$cluster_status,$node_count nodes,$estimated_cost"
    echo "$env,PostgreSQL Database,$db_name,$db_status,Database,$estimated_cost"
    echo "$env,Load Balancer,$lb_ip,Active,HTTP/HTTPS,$estimated_cost"
    echo "$env,Access URL,$access_url,Active,Web Interface,$estimated_cost"
}

track_environment() {
    local env="$1"

    if ! check_environment_exists "$env"; then
        log WARN "Environment '$env' not found or not configured"
        return
    fi

    case "$OUTPUT_FORMAT" in
        table)
            print_environment_table "$env"
            ;;
        json)
            print_environment_json "$env"
            ;;
        csv)
            print_environment_csv "$env"
            ;;
    esac
}

track_all_environments() {
    local envs=("dev" "staging" "prod")
    local first=true

    case "$OUTPUT_FORMAT" in
        table)
            for env in "${envs[@]}"; do
                if check_environment_exists "$env"; then
                    track_environment "$env"
                fi
            done
            ;;
        json)
            echo "["
            for env in "${envs[@]}"; do
                if check_environment_exists "$env"; then
                    if [[ "$first" == "false" ]]; then
                        echo ","
                    fi
                    print_environment_json "$env"
                    first=false
                fi
            done
            echo "]"
            ;;
        csv)
            echo "Environment,Resource Type,Name,Status,Details,Monthly Cost"
            for env in "${envs[@]}"; do
                if check_environment_exists "$env"; then
                    print_environment_csv "$env" | tail -n +2
                fi
            done
            ;;
    esac
}

export_inventory() {
    local output_file="$1"
    local temp_file=$(mktemp)

    # Redirect output to temp file
    if [[ "$ENVIRONMENT" == "all" ]]; then
        track_all_environments > "$temp_file"
    else
        track_environment "$ENVIRONMENT" > "$temp_file"
    fi

    # Move to final location
    mv "$temp_file" "$output_file"
    log INFO "Inventory exported to: $output_file"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
                shift
                ;;
            --export=*)
                EXPORT_FILE="${1#*=}"
                shift
                ;;
            --detailed)
                DETAILED_VIEW=true
                shift
                ;;
            --show-terraform)
                SHOW_TERRAFORM_STATE=true
                shift
                ;;
            --no-costs)
                INCLUDE_COSTS=false
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

    # Validate inputs
    case "$ENVIRONMENT" in
        dev|staging|prod|all) ;;
        *)
            log ERROR "Invalid environment: $ENVIRONMENT"
            exit 1
            ;;
    esac

    case "$OUTPUT_FORMAT" in
        table|json|csv) ;;
        *)
            log ERROR "Invalid output format: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac

    if [[ "$OUTPUT_FORMAT" == "table" ]] && [[ -z "$EXPORT_FILE" ]]; then
        print_banner
    fi

    # Export or display inventory
    if [[ -n "$EXPORT_FILE" ]]; then
        export_inventory "$EXPORT_FILE"
    else
        if [[ "$ENVIRONMENT" == "all" ]]; then
            track_all_environments
        else
            track_environment "$ENVIRONMENT"
        fi
    fi
}

# Run main function with all arguments
main "$@"