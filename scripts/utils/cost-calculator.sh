#!/bin/bash

# Coder on Scaleway - Cost Calculator
# Real-time cost calculation and budget management

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
PERIOD="monthly"
ESTIMATE_ONLY=false
SET_BUDGET=false
BUDGET_AMOUNT=""
ALERT_THRESHOLD=80
CURRENCY="EUR"
OUTPUT_FORMAT="table"

# Scaleway pricing (EUR per hour)
declare -A NODE_COSTS=(
    ["GP1-XS"]="0.091"     # €66.43/month (4 vCPU, 16GB RAM)
    ["GP1-S"]="0.187"      # €136.51/month (8 vCPU, 32GB RAM)
    ["GP1-M"]="0.376"      # €274.48/month (16 vCPU, 64GB RAM)
)

declare -A DB_COSTS=(
    ["DB-DEV-S"]="0.0156"   # €11.23/month (2 vCPU, 2GB RAM)
    ["DB-GP-S"]="0.3803"    # €273.82/month (8 vCPU, 32GB RAM)
    ["DB-GP-M"]="0.7595"    # €547.24/month (16 vCPU, 64GB RAM)
)

declare -A LB_COSTS=(
    ["LB-S"]="0.0124"        # €8.90/month
    ["LB-GP-M"]="0.0633"     # €45.60/month
    ["LB-GP-L"]="0.1267"     # €91.20/month
)

# Fixed costs
VPC_COST_HOURLY="0.0029"      # €2.10/month
STORAGE_COST_GB_HOURLY="0.00014"  # €0.10/GB/month

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║           Cost Calculator             ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --env=ENV                Environment to calculate costs for (dev|staging|prod|all)
    --period=PERIOD          Calculation period (hourly|daily|monthly|yearly) [default: monthly]
    --estimate-only          Show estimates without querying actual resources
    --set-budget=AMOUNT      Set budget alert for environment
    --alert-threshold=PCT    Budget alert threshold percentage [default: 80]
    --format=FORMAT          Output format (table|json|csv) [default: table]
    --help                   Show this help message

Examples:
    $0 --env=all
    $0 --env=prod --period=yearly
    $0 --env=dev --set-budget=100 --alert-threshold=90
    $0 --env=staging --format=json

Budget Management:
    $0 --env=prod --set-budget=500 --alert-threshold=80
    # This sets a €500/month budget with 80% alert threshold

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
        STEP)  echo -e "${CYAN}[STEP]${NC}  $message" ;;
    esac
}

calculate_period_multiplier() {
    case "$PERIOD" in
        hourly)  echo "1" ;;
        daily)   echo "24" ;;
        monthly) echo "720" ;;  # 30 * 24
        yearly)  echo "8640" ;; # 30 * 24 * 12
        *)       echo "720" ;;  # Default to monthly
    esac
}

get_environment_config() {
    local env="$1"
    local config_file="${PROJECT_ROOT}/environments/${env}/main.tf"

    if [[ ! -f "$config_file" ]]; then
        log ERROR "Configuration not found for environment: $env"
        return 1
    fi

    # Extract configuration from Terraform files
    # This is a simplified version - in practice you'd parse the actual Terraform config
    case "$env" in
        dev)
            echo "GP1-XS:2 DB-DEV-S:1 LB-S:1"
            ;;
        staging)
            echo "GP1-S:3 DB-GP-S:1 LB-S:1"
            ;;
        prod)
            echo "GP1-M:5 DB-GP-M:1 LB-GP-M:1"
            ;;
    esac
}

calculate_infrastructure_cost() {
    local env="$1"
    local config
    config=$(get_environment_config "$env")

    if [[ -z "$config" ]]; then
        return 1
    fi

    local total_hourly=0
    local multiplier
    multiplier=$(calculate_period_multiplier)

    # Parse configuration and calculate costs
    for item in $config; do
        local resource_type=$(echo "$item" | cut -d: -f1)
        local count=$(echo "$item" | cut -d: -f2)
        local hourly_cost=0

        # Determine resource cost
        if [[ -n "${NODE_COSTS[$resource_type]:-}" ]]; then
            hourly_cost="${NODE_COSTS[$resource_type]}"
        elif [[ -n "${DB_COSTS[$resource_type]:-}" ]]; then
            hourly_cost="${DB_COSTS[$resource_type]}"
        elif [[ -n "${LB_COSTS[$resource_type]:-}" ]]; then
            hourly_cost="${LB_COSTS[$resource_type]}"
        fi

        if [[ "$hourly_cost" != "0" ]]; then
            local resource_total=$(echo "$hourly_cost * $count * $multiplier" | bc -l)
            total_hourly=$(echo "$total_hourly + $resource_total" | bc -l)
        fi
    done

    # Add VPC and networking costs
    local vpc_total=$(echo "$VPC_COST_HOURLY * $multiplier" | bc -l)
    total_hourly=$(echo "$total_hourly + $vpc_total" | bc -l)

    # Add estimated storage costs (varies by environment)
    local storage_gb
    case "$env" in
        dev) storage_gb="50" ;;
        staging) storage_gb="100" ;;
        prod) storage_gb="200" ;;
    esac

    local storage_total=$(echo "$STORAGE_COST_GB_HOURLY * $storage_gb * $multiplier" | bc -l)
    total_hourly=$(echo "$total_hourly + $storage_total" | bc -l)

    printf "%.2f" "$total_hourly"
}

get_resource_breakdown() {
    local env="$1"
    local config
    config=$(get_environment_config "$env")
    local multiplier
    multiplier=$(calculate_period_multiplier)

    local breakdown=()

    for item in $config; do
        local resource_type=$(echo "$item" | cut -d: -f1)
        local count=$(echo "$item" | cut -d: -f2)
        local hourly_cost=0
        local category=""

        if [[ -n "${NODE_COSTS[$resource_type]:-}" ]]; then
            hourly_cost="${NODE_COSTS[$resource_type]}"
            category="Compute"
        elif [[ -n "${DB_COSTS[$resource_type]:-}" ]]; then
            hourly_cost="${DB_COSTS[$resource_type]}"
            category="Database"
        elif [[ -n "${LB_COSTS[$resource_type]:-}" ]]; then
            hourly_cost="${LB_COSTS[$resource_type]}"
            category="Load Balancer"
        fi

        if [[ "$hourly_cost" != "0" ]]; then
            local resource_total=$(echo "$hourly_cost * $count * $multiplier" | bc -l)
            breakdown+=("$category:$resource_type:$count:$(printf "%.2f" "$resource_total")")
        fi
    done

    # Add networking
    local vpc_total=$(echo "$VPC_COST_HOURLY * $multiplier" | bc -l)
    breakdown+=("Networking:VPC+Gateway:1:$(printf "%.2f" "$vpc_total")")

    # Add storage
    local storage_gb
    case "$env" in
        dev) storage_gb="50" ;;
        staging) storage_gb="100" ;;
        prod) storage_gb="200" ;;
    esac

    local storage_total=$(echo "$STORAGE_COST_GB_HOURLY * $storage_gb * $multiplier" | bc -l)
    breakdown+=("Storage:Block Storage:${storage_gb}GB:$(printf "%.2f" "$storage_total")")

    printf '%s\n' "${breakdown[@]}"
}

format_currency() {
    local amount="$1"
    printf "€%.2f" "$amount"
}

print_cost_table() {
    local env="$1"
    local total_cost="$2"

    log STEP "Cost breakdown for environment: $env ($PERIOD)"
    echo

    printf "%-15s %-20s %-10s %-10s\n" "CATEGORY" "RESOURCE" "QUANTITY" "COST"
    printf "%s\n" "$(printf '%.0s-' {1..65})"

    local breakdown
    breakdown=$(get_resource_breakdown "$env")

    while IFS= read -r line; do
        local category=$(echo "$line" | cut -d: -f1)
        local resource=$(echo "$line" | cut -d: -f2)
        local quantity=$(echo "$line" | cut -d: -f3)
        local cost=$(echo "$line" | cut -d: -f4)

        printf "%-15s %-20s %-10s %s\n" "$category" "$resource" "$quantity" "$(format_currency "$cost")"
    done <<< "$breakdown"

    printf "%s\n" "$(printf '%.0s-' {1..65})"
    printf "%-47s %s\n" "TOTAL ($PERIOD)" "$(format_currency "$total_cost")"
    echo
}

print_cost_json() {
    local env="$1"
    local total_cost="$2"
    local breakdown
    breakdown=$(get_resource_breakdown "$env")

    echo "{"
    echo "  \"environment\": \"$env\","
    echo "  \"period\": \"$PERIOD\","
    echo "  \"currency\": \"$CURRENCY\","
    echo "  \"total_cost\": $total_cost,"
    echo "  \"breakdown\": ["

    local first=true
    while IFS= read -r line; do
        local category=$(echo "$line" | cut -d: -f1)
        local resource=$(echo "$line" | cut -d: -f2)
        local quantity=$(echo "$line" | cut -d: -f3)
        local cost=$(echo "$line" | cut -d: -f4)

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi

        echo -n "    {"
        echo -n "\"category\":\"$category\","
        echo -n "\"resource\":\"$resource\","
        echo -n "\"quantity\":\"$quantity\","
        echo -n "\"cost\":$cost"
        echo -n "}"
    done <<< "$breakdown"

    echo ""
    echo "  ]"
    echo "}"
}

print_cost_csv() {
    local env="$1"
    local total_cost="$2"
    local breakdown
    breakdown=$(get_resource_breakdown "$env")

    echo "Environment,Period,Category,Resource,Quantity,Cost"

    while IFS= read -r line; do
        local category=$(echo "$line" | cut -d: -f1)
        local resource=$(echo "$line" | cut -d: -f2)
        local quantity=$(echo "$line" | cut -d: -f3)
        local cost=$(echo "$line" | cut -d: -f4)

        echo "$env,$PERIOD,$category,$resource,$quantity,$cost"
    done <<< "$breakdown"

    echo "$env,$PERIOD,TOTAL,TOTAL,,$total_cost"
}

check_budget_alerts() {
    local env="$1"
    local current_cost="$2"
    local budget_file="${PROJECT_ROOT}/.budgets/${env}.budget"

    if [[ ! -f "$budget_file" ]]; then
        return 0
    fi

    local budget_limit
    budget_limit=$(cat "$budget_file")

    if [[ -z "$budget_limit" || "$budget_limit" == "0" ]]; then
        return 0
    fi

    local usage_percent
    usage_percent=$(echo "scale=0; $current_cost * 100 / $budget_limit" | bc -l)

    if (( $(echo "$usage_percent >= $ALERT_THRESHOLD" | bc -l) )); then
        echo
        log WARN "🚨 BUDGET ALERT for $env environment!"
        log WARN "Current cost: $(format_currency "$current_cost") ($usage_percent% of budget)"
        log WARN "Budget limit: $(format_currency "$budget_limit")"
        log WARN "Alert threshold: $ALERT_THRESHOLD%"

        if (( $(echo "$current_cost > $budget_limit" | bc -l) )); then
            log ERROR "💸 BUDGET EXCEEDED! Consider scaling down or optimizing resources."
        fi
        echo
    fi
}

set_budget_limit() {
    local env="$1"
    local amount="$2"

    mkdir -p "${PROJECT_ROOT}/.budgets"
    local budget_file="${PROJECT_ROOT}/.budgets/${env}.budget"

    echo "$amount" > "$budget_file"
    log INFO "Budget set for $env: $(format_currency "$amount")/$PERIOD"
    log INFO "Alert threshold: $ALERT_THRESHOLD%"

    # Add budget file to gitignore if not already there
    local gitignore="${PROJECT_ROOT}/.gitignore"
    if [[ -f "$gitignore" ]] && ! grep -q "\.budgets/" "$gitignore"; then
        echo ".budgets/" >> "$gitignore"
    fi
}

calculate_environment_costs() {
    local env="$1"

    if [[ "$env" == "all" ]]; then
        log STEP "Calculating costs for all environments"
        echo

        local total_all=0
        for e in dev staging prod; do
            local cost
            cost=$(calculate_infrastructure_cost "$e")

            case "$OUTPUT_FORMAT" in
                table)
                    print_cost_table "$e" "$cost"
                    check_budget_alerts "$e" "$cost"
                    ;;
                json)
                    print_cost_json "$e" "$cost"
                    ;;
                csv)
                    print_cost_csv "$e" "$cost"
                    ;;
            esac

            total_all=$(echo "$total_all + $cost" | bc -l)
        done

        if [[ "$OUTPUT_FORMAT" == "table" ]]; then
            echo
            log INFO "💰 TOTAL COST (all environments): $(format_currency "$total_all")/$PERIOD"
        fi
    else
        local cost
        cost=$(calculate_infrastructure_cost "$env")

        case "$OUTPUT_FORMAT" in
            table)
                print_cost_table "$env" "$cost"
                check_budget_alerts "$env" "$cost"
                ;;
            json)
                print_cost_json "$env" "$cost"
                ;;
            csv)
                print_cost_csv "$env" "$cost"
                ;;
        esac
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --period=*)
                PERIOD="${1#*=}"
                shift
                ;;
            --estimate-only)
                ESTIMATE_ONLY=true
                shift
                ;;
            --set-budget=*)
                SET_BUDGET=true
                BUDGET_AMOUNT="${1#*=}"
                shift
                ;;
            --alert-threshold=*)
                ALERT_THRESHOLD="${1#*=}"
                shift
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
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

    case "$PERIOD" in
        hourly|daily|monthly|yearly) ;;
        *)
            log ERROR "Invalid period: $PERIOD"
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

    if [[ "$OUTPUT_FORMAT" == "table" ]]; then
        print_banner
    fi

    # Set budget if requested
    if [[ "$SET_BUDGET" == "true" ]]; then
        if [[ "$ENVIRONMENT" == "all" ]]; then
            log ERROR "Cannot set budget for 'all' environments. Set individually."
            exit 1
        fi

        if ! [[ "$BUDGET_AMOUNT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            log ERROR "Invalid budget amount: $BUDGET_AMOUNT"
            exit 1
        fi

        set_budget_limit "$ENVIRONMENT" "$BUDGET_AMOUNT"
        return 0
    fi

    # Calculate and display costs
    calculate_environment_costs "$ENVIRONMENT"
}

# Check if bc is available (required for calculations)
if ! command -v bc &> /dev/null; then
    log ERROR "bc (basic calculator) is required but not installed"
    exit 1
fi

# Run main function with all arguments
main "$@"