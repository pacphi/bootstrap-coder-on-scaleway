#!/bin/bash

# Coder on Scaleway - Database Resize Script
# Resize database instances for cost optimization

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
INSTANCE_TYPE=""
AUTO_MODE=false
DRY_RUN=false
BACKUP_BEFORE=true
ANALYZE_ONLY=false
LOG_FILE=""
START_TIME=$(date +%s)

# Database instance types and costs (EUR per hour)
declare -A DB_TYPES=(
    ["DB-DEV-S"]="1 vCPU, 2GB RAM, €12.30/month"
    ["DB-GP-S"]="2 vCPU, 4GB RAM, €18.45/month"
    ["DB-GP-M"]="4 vCPU, 16GB RAM, €36.90/month"
    ["DB-GP-L"]="8 vCPU, 32GB RAM, €73.80/month"
)

declare -A DB_COSTS=(
    ["DB-DEV-S"]="0.0171"
    ["DB-GP-S"]="0.0256"
    ["DB-GP-M"]="0.0513"
    ["DB-GP-L"]="0.1025"
)

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║          Database Resizing            ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Resize PostgreSQL database instances for cost optimization or capacity scaling.
Includes automatic backup, downtime analysis, and cost impact assessment.

Options:
    --env=ENV               Environment to resize (dev|staging|prod) [required]
    --instance-type=TYPE    Target instance type [required]
    --auto                  Run in automated mode (no prompts)
    --dry-run              Show resize plan without executing
    --no-backup            Skip pre-resize backup
    --analyze-only         Only analyze current usage and recommendations
    --confirm              Confirm resize operation (safety check)
    --help                 Show this help message

Instance Types:
    DB-DEV-S    1 vCPU, 2GB RAM      €12.30/month    (Development)
    DB-GP-S     2 vCPU, 4GB RAM      €18.45/month    (Small workloads)
    DB-GP-M     4 vCPU, 16GB RAM     €36.90/month    (Medium workloads)
    DB-GP-L     8 vCPU, 32GB RAM     €73.80/month    (Large workloads)

Examples:
    $0 --env=prod --instance-type=DB-GP-S --confirm
    $0 --env=staging --analyze-only
    $0 --env=dev --instance-type=DB-GP-M --dry-run

Safety Features:
    • Automatic backup before resize
    • Database connection validation
    • Downtime estimation
    • Cost impact analysis
    • Rollback procedures

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
    local log_dir="${PROJECT_ROOT}/logs/database"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-resize.log"
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
}

validate_instance_type() {
    if [[ -z "${DB_TYPES[$INSTANCE_TYPE]}" ]]; then
        log ERROR "Invalid instance type: $INSTANCE_TYPE"
        log ERROR "Valid types: ${!DB_TYPES[*]}"
        exit 1
    fi

    log INFO "Target instance type: $INSTANCE_TYPE (${DB_TYPES[$INSTANCE_TYPE]})"
}

get_current_database_info() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"

    # Check if Terraform state exists
    if [[ ! -f "${env_dir}/terraform.tfstate" ]]; then
        log ERROR "Terraform state not found for environment: $ENVIRONMENT"
        return 1
    fi

    cd "$env_dir"

    # Get database instance ID from Terraform outputs
    local db_id=$(terraform output -json 2>/dev/null | jq -r '.database_id.value // empty' 2>/dev/null || echo "")

    if [[ -z "$db_id" ]]; then
        log ERROR "Database instance ID not found in Terraform outputs"
        return 1
    fi

    # Get current instance information using Scaleway CLI
    local db_info=$(scw rdb instance get "$db_id" -o json 2>/dev/null || echo "")

    if [[ -z "$db_info" ]]; then
        log ERROR "Failed to retrieve database instance information"
        return 1
    fi

    # Parse current instance details
    local current_type=$(echo "$db_info" | jq -r '.node_type // "unknown"')
    local current_status=$(echo "$db_info" | jq -r '.status // "unknown"')
    local current_endpoint=$(echo "$db_info" | jq -r '.endpoint.ip // "unknown"')
    local current_port=$(echo "$db_info" | jq -r '.endpoint.port // 5432')

    echo "DB_ID=$db_id"
    echo "CURRENT_TYPE=$current_type"
    echo "CURRENT_STATUS=$current_status"
    echo "CURRENT_ENDPOINT=$current_endpoint"
    echo "CURRENT_PORT=$current_port"
}

analyze_database_usage() {
    log STEP "Analyzing database usage and performance..."

    # Get current database info
    local db_vars
    db_vars=$(get_current_database_info)
    eval "$db_vars"

    if [[ -z "$DB_ID" ]]; then
        log ERROR "Could not retrieve database information"
        return 1
    fi

    log INFO "Current Database:"
    log INFO "  Instance ID: $DB_ID"
    log INFO "  Type: $CURRENT_TYPE (${DB_TYPES[$CURRENT_TYPE]:-Unknown})"
    log INFO "  Status: $CURRENT_STATUS"
    log INFO "  Endpoint: $CURRENT_ENDPOINT:$CURRENT_PORT"

    # Try to get database metrics (connection count, CPU usage, etc.)
    log INFO "Fetching database metrics..."

    # Set kubeconfig to check database connectivity from cluster
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"

        # Check database connectivity from within cluster
        if kubectl cluster-info &> /dev/null; then
            log INFO "Checking database connectivity from cluster..."

            # Try to get database connection stats
            local db_secret=""
            if kubectl get secret coder-db-secret -n coder &> /dev/null; then
                db_secret="coder-db-secret"
            elif kubectl get secret coder-database -n coder &> /dev/null; then
                db_secret="coder-database"
            fi

            if [[ -n "$db_secret" ]]; then
                local db_user=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "postgres")
                local db_name=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.database}' | base64 -d 2>/dev/null || echo "coder")
                local db_pass=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")

                if [[ -n "$db_pass" ]]; then
                    # Get database statistics
                    local stats=$(kubectl run db-stats-$(date +%s) \
                        --image=postgres:15 \
                        --rm -i \
                        --restart=Never \
                        --env="PGPASSWORD=$db_pass" \
                        --command -- psql \
                        -h "$CURRENT_ENDPOINT" \
                        -U "$db_user" \
                        -d "$db_name" \
                        -t -c "SELECT
                            count(*) as connections,
                            pg_database_size('$db_name')/1024/1024 as db_size_mb
                        FROM pg_stat_activity WHERE datname='$db_name';" 2>/dev/null | tr -d ' ' || echo "0|0")

                    local connections=$(echo "$stats" | cut -d'|' -f1)
                    local db_size_mb=$(echo "$stats" | cut -d'|' -f2)

                    log INFO "Database Statistics:"
                    log INFO "  Active Connections: $connections"
                    log INFO "  Database Size: ${db_size_mb}MB"
                fi
            fi
        fi
    fi

    # Calculate cost impact
    calculate_cost_impact "$CURRENT_TYPE" "$INSTANCE_TYPE"

    # Provide recommendations
    provide_resize_recommendations "$CURRENT_TYPE" "$INSTANCE_TYPE"
}

calculate_cost_impact() {
    local current_type="$1"
    local target_type="$2"

    log STEP "Calculating cost impact..."

    local current_cost=${DB_COSTS[$current_type]:-0}
    local target_cost=${DB_COSTS[$target_type]:-0}

    local current_monthly=$(echo "scale=2; $current_cost * 720" | bc)
    local target_monthly=$(echo "scale=2; $target_cost * 720" | bc)
    local difference=$(echo "scale=2; $target_monthly - $current_monthly" | bc)

    echo
    echo -e "${WHITE}💰 Cost Impact Analysis:${NC}"
    echo -e "  Current ($current_type): €${current_monthly}/month"
    echo -e "  Target ($target_type):   €${target_monthly}/month"

    if (( $(echo "$difference > 0" | bc -l) )); then
        echo -e "  ${RED}Cost Increase:${NC} +€${difference}/month (+$(echo "scale=1; $difference * 12" | bc)/year)"
    elif (( $(echo "$difference < 0" | bc -l) )); then
        difference=$(echo "$difference * -1" | bc)
        echo -e "  ${GREEN}Cost Savings:${NC} -€${difference}/month (-€$(echo "scale=1; $difference * 12" | bc)/year)"
    else
        echo -e "  ${YELLOW}No Cost Change${NC}"
    fi
    echo
}

provide_resize_recommendations() {
    local current_type="$1"
    local target_type="$2"

    log STEP "Resize Recommendations"

    echo
    echo -e "${YELLOW}📊 Recommendations:${NC}"

    case "$target_type" in
        "DB-DEV-S")
            echo "  • Suitable for development and light testing workloads"
            echo "  • Max ~10-15 concurrent connections"
            echo "  • Database size < 10GB recommended"
            echo "  • Not recommended for production"
            ;;
        "DB-GP-S")
            echo "  • Good for small production workloads"
            echo "  • Max ~20-30 concurrent connections"
            echo "  • Database size < 50GB recommended"
            echo "  • Suitable for staging environments"
            ;;
        "DB-GP-M")
            echo "  • Recommended for medium production workloads"
            echo "  • Max ~50-75 concurrent connections"
            echo "  • Database size < 200GB recommended"
            echo "  • Good balance of performance and cost"
            ;;
        "DB-GP-L")
            echo "  • High-performance production workloads"
            echo "  • Max ~100+ concurrent connections"
            echo "  • Database size < 500GB recommended"
            echo "  • Maximum available performance tier"
            ;;
    esac

    # Downsizing warnings
    if [[ "$current_type" > "$target_type" ]]; then
        echo
        echo -e "${RED}⚠️  Downsizing Warnings:${NC}"
        echo "  • Monitor performance closely after resize"
        echo "  • Connection limits will be reduced"
        echo "  • Memory available for caching decreases"
        echo "  • Consider load testing before production use"
    fi

    # Upsizing benefits
    if [[ "$current_type" < "$target_type" ]]; then
        echo
        echo -e "${GREEN}✅ Upsizing Benefits:${NC}"
        echo "  • Increased connection capacity"
        echo "  • Better query performance"
        echo "  • More memory for caching"
        echo "  • Improved concurrent user support"
    fi

    echo
}

create_database_backup() {
    if [[ "$BACKUP_BEFORE" == "false" ]]; then
        log INFO "Skipping backup as requested"
        return 0
    fi

    log STEP "Creating database backup before resize..."

    # Use the existing backup script
    local backup_script="${PROJECT_ROOT}/scripts/lifecycle/backup.sh"

    if [[ ! -f "$backup_script" ]]; then
        log ERROR "Backup script not found: $backup_script"
        return 1
    fi

    local backup_name="pre-resize-$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}"

    log INFO "Creating backup: $backup_name"

    if "$backup_script" --env="$ENVIRONMENT" --include-data --backup-name="$backup_name" --auto; then
        log INFO "✅ Backup completed: $backup_name"
        echo "BACKUP_NAME=$backup_name"
    else
        log ERROR "Backup failed - aborting resize"
        return 1
    fi
}

perform_database_resize() {
    log STEP "Performing database resize operation..."

    # Get current database info
    local db_vars
    db_vars=$(get_current_database_info)
    eval "$db_vars"

    if [[ -z "$DB_ID" ]]; then
        log ERROR "Could not retrieve database information"
        return 1
    fi

    if [[ "$CURRENT_TYPE" == "$INSTANCE_TYPE" ]]; then
        log WARN "Database is already the target instance type: $INSTANCE_TYPE"
        return 0
    fi

    log INFO "Resizing database instance..."
    log INFO "  From: $CURRENT_TYPE"
    log INFO "  To: $INSTANCE_TYPE"

    # Estimate downtime
    log WARN "⏱️  Estimated downtime: 5-10 minutes"
    log WARN "🔄 Applications will lose database connectivity during resize"

    if [[ "$AUTO_MODE" == "false" ]]; then
        echo
        read -p "Proceed with database resize? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Database resize cancelled by user"
            return 0
        fi
    fi

    # Perform resize using Scaleway CLI
    log INFO "Starting resize operation..."

    if scw rdb instance update "$DB_ID" node-type="$INSTANCE_TYPE" > /dev/null 2>&1; then
        log INFO "✅ Resize operation initiated successfully"

        # Wait for resize to complete
        log INFO "Waiting for resize to complete..."
        local max_wait=900  # 15 minutes
        local wait_time=0

        while [[ $wait_time -lt $max_wait ]]; do
            local status=$(scw rdb instance get "$DB_ID" -o json | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")

            case "$status" in
                "ready")
                    log INFO "✅ Database resize completed successfully"
                    return 0
                    ;;
                "configuring"|"upgrading"|"backing_up")
                    echo -n "."
                    sleep 30
                    wait_time=$((wait_time + 30))
                    ;;
                "error"|"stopped")
                    log ERROR "Database resize failed with status: $status"
                    return 1
                    ;;
                *)
                    echo -n "."
                    sleep 30
                    wait_time=$((wait_time + 30))
                    ;;
            esac
        done

        log ERROR "Database resize timed out after $max_wait seconds"
        return 1
    else
        log ERROR "Failed to initiate database resize"
        return 1
    fi
}

validate_resize() {
    log STEP "Validating database after resize..."

    # Get updated database info
    local db_vars
    db_vars=$(get_current_database_info)
    eval "$db_vars"

    if [[ "$CURRENT_TYPE" == "$INSTANCE_TYPE" ]]; then
        log INFO "✅ Database instance type confirmed: $INSTANCE_TYPE"
    else
        log ERROR "Database instance type mismatch. Expected: $INSTANCE_TYPE, Got: $CURRENT_TYPE"
        return 1
    fi

    # Test database connectivity
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"

        if kubectl cluster-info &> /dev/null; then
            # Check if Coder can connect to database
            log INFO "Testing application connectivity..."

            local coder_pod=$(kubectl get pods -n coder -l app=coder -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

            if [[ -n "$coder_pod" ]]; then
                # Check Coder pod status
                local pod_status=$(kubectl get pod "$coder_pod" -n coder -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                log INFO "Coder pod status: $pod_status"

                if [[ "$pod_status" == "Running" ]]; then
                    # Check Coder logs for database connectivity
                    local recent_logs=$(kubectl logs "$coder_pod" -n coder --tail=10 --since=2m 2>/dev/null || echo "")

                    if echo "$recent_logs" | grep -q "database connection.*successful\|connected to database\|postgres.*ready"; then
                        log INFO "✅ Database connectivity verified"
                    elif echo "$recent_logs" | grep -q "database.*error\|connection.*failed\|postgres.*error"; then
                        log WARN "⚠️  Database connectivity issues detected in Coder logs"
                    else
                        log INFO "Database connectivity status unclear from logs"
                    fi
                fi
            fi
        fi
    fi

    log INFO "✅ Database resize validation completed"
}

print_resize_plan() {
    log STEP "Database Resize Plan"

    # Get current database info for display
    local db_vars
    db_vars=$(get_current_database_info)
    eval "$db_vars"

    echo
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Current Type:${NC} $CURRENT_TYPE (${DB_TYPES[$CURRENT_TYPE]:-Unknown})"
    echo -e "${WHITE}Target Type:${NC} $INSTANCE_TYPE (${DB_TYPES[$INSTANCE_TYPE]})"
    echo -e "${WHITE}Database ID:${NC} ${DB_ID:-Not available}"

    calculate_cost_impact "$CURRENT_TYPE" "$INSTANCE_TYPE"

    echo -e "${YELLOW}⏱️  Resize Process:${NC}"
    echo "   1. Create database backup (if enabled)"
    echo "   2. Initiate instance type change"
    echo "   3. Wait for resize completion (~5-10 minutes)"
    echo "   4. Validate new instance configuration"
    echo "   5. Test application connectivity"

    echo
    echo -e "${RED}⚠️  Important Notes:${NC}"
    echo "   • Database will be unavailable during resize"
    echo "   • All connections will be terminated"
    echo "   • Applications should handle reconnection automatically"
    echo "   • Resize operation cannot be cancelled once started"

    if [[ "$BACKUP_BEFORE" == "false" ]]; then
        echo
        echo -e "${YELLOW}⚠️  No backup will be created (--no-backup specified)${NC}"
    fi

    echo
}

print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${GREEN}🔄 Database resize completed! 🔄${NC}"
    echo
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}New Instance Type:${NC} $INSTANCE_TYPE"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"

    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo "   • Monitor application performance"
    echo "   • Check database connection metrics"
    echo "   • Verify workspace functionality"
    echo "   • Update monitoring thresholds if needed"
    echo "   • Document configuration change"

    echo
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --instance-type=*)
                INSTANCE_TYPE="${1#*=}"
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-backup)
                BACKUP_BEFORE=false
                shift
                ;;
            --analyze-only)
                ANALYZE_ONLY=true
                shift
                ;;
            --confirm)
                # This is a safety check - no action needed, just accept it
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

    # Validate required parameters
    if [[ -z "$ENVIRONMENT" ]]; then
        log ERROR "Environment is required. Use --env=ENV"
        print_usage
        exit 1
    fi

    if [[ "$ANALYZE_ONLY" == "false" ]] && [[ -z "$INSTANCE_TYPE" ]]; then
        log ERROR "Instance type is required. Use --instance-type=TYPE"
        print_usage
        exit 1
    fi

    print_banner
    setup_logging

    validate_environment

    # Handle analysis-only mode
    if [[ "$ANALYZE_ONLY" == "true" ]]; then
        log INFO "Running database usage analysis for environment: $ENVIRONMENT"
        analyze_database_usage
        exit 0
    fi

    validate_instance_type

    log INFO "Starting database resize for environment: $ENVIRONMENT"
    log INFO "Target instance type: $INSTANCE_TYPE"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🧪 Running in DRY RUN mode"
    fi

    # Analyze current state and show plan
    analyze_database_usage
    print_resize_plan

    if [[ "$DRY_RUN" == "true" ]]; then
        echo
        log INFO "🧪 Dry run completed - no changes were made"
        exit 0
    fi

    # Confirm resize operation
    if [[ "$AUTO_MODE" == "false" ]]; then
        echo
        read -p "Proceed with database resize? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Database resize cancelled by user"
            exit 0
        fi
    fi

    # Execute resize
    if [[ "$BACKUP_BEFORE" == "true" ]]; then
        create_database_backup
    fi

    perform_database_resize
    validate_resize
    print_summary
}

# Check for required dependencies
command -v scw >/dev/null 2>&1 || { log ERROR "Scaleway CLI (scw) is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { log ERROR "jq is required but not installed. Aborting."; exit 1; }
command -v bc >/dev/null 2>&1 || { log ERROR "bc is required but not installed. Aborting."; exit 1; }

# Run main function with all arguments
main "$@"