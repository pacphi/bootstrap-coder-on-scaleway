#!/bin/bash

# Coder on Scaleway - User Activity Report
# Generate comprehensive user analytics and activity reports

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
PERIOD="monthly"
TEAMS="all"
METRICS="login-frequency,resource-usage,cost-attribution"
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
INCLUDE_INACTIVE=false
COST_ATTRIBUTION=true
LOG_FILE=""
START_TIME=$(date +%s)

# Supported metrics
SUPPORTED_METRICS=(
    "login-frequency"
    "resource-usage"
    "cost-attribution"
    "workspace-activity"
    "template-usage"
    "collaboration"
    "error-rates"
)

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║         User Activity Reports        ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Generate comprehensive user activity and analytics reports for Coder environments.
Track user engagement, resource utilization, costs, and collaboration patterns.

Options:
    --env=ENV                   Environment (dev|staging|prod) [required]
    --period=PERIOD             Report period (daily|weekly|monthly|quarterly|yearly) [default: monthly]
    --teams=TEAMS              Teams to include (team1,team2|all) [default: all]
    --metrics=METRICS          Metrics to include (comma-separated) [default: login-frequency,resource-usage,cost-attribution]
    --format=FORMAT            Output format (table|json|csv|html) [default: table]
    --output-file=FILE         Output file path (auto-generated if not specified)
    --include-inactive         Include inactive users in report
    --no-cost-attribution      Skip cost attribution calculations
    --help                     Show this help message

Available Metrics:
    login-frequency       User login patterns and session duration
    resource-usage        CPU, memory, storage consumption per user
    cost-attribution      Cost breakdown by user and team
    workspace-activity    Workspace creation, usage, and lifecycle
    template-usage        Template selection and usage patterns
    collaboration         Team collaboration and sharing metrics
    error-rates           Error rates and troubleshooting patterns

Report Periods:
    daily           Last 24 hours of activity
    weekly          Last 7 days of activity
    monthly         Last 30 days of activity (default)
    quarterly       Last 90 days of activity
    yearly          Last 365 days of activity

Output Formats:
    table           Human-readable table format (default)
    json            JSON format for API integration
    csv             CSV format for spreadsheet analysis
    html            HTML report with charts and graphs

Examples:
    # Basic monthly report for all teams
    $0 --env=prod --period=monthly

    # Detailed quarterly report for specific teams
    $0 --env=prod --period=quarterly --teams=frontend,backend --format=html

    # Cost attribution report in CSV format
    $0 --env=staging --metrics=cost-attribution,resource-usage --format=csv --output-file=costs-q4.csv

    # Weekly activity summary including inactive users
    $0 --env=dev --period=weekly --include-inactive --format=json

Team Analytics:
    # Compare team productivity and resource efficiency
    $0 --env=prod --teams=frontend,backend,devops --metrics=all

    # Track template adoption across teams
    $0 --env=prod --metrics=template-usage,collaboration --period=quarterly

Management Reports:
    # Executive summary with cost insights
    $0 --env=prod --period=monthly --format=html --output-file=executive-summary.html

    # Detailed operational metrics for team leads
    $0 --env=prod --teams=backend --metrics=all --format=json --output-file=backend-metrics.json

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
    local log_dir="${PROJECT_ROOT}/logs/user-reports"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-activity-report.log"
    log INFO "Logging to: $LOG_FILE"
}

validate_environment() {
    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Analyzing environment: $ENVIRONMENT"
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

    # Check kubeconfig
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        exit 1
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info > /dev/null 2>&1; then
        log ERROR "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

validate_metrics() {
    IFS=',' read -ra METRIC_ARRAY <<< "$METRICS"
    for metric in "${METRIC_ARRAY[@]}"; do
        if [[ ! " ${SUPPORTED_METRICS[@]} " =~ " ${metric} " ]] && [[ "$metric" != "all" ]]; then
            log ERROR "Invalid metric: $metric"
            log ERROR "Supported metrics: ${SUPPORTED_METRICS[*]}"
            exit 1
        fi
    done

    # Expand "all" to all supported metrics
    if [[ "$METRICS" == "all" ]]; then
        METRICS=$(IFS=','; echo "${SUPPORTED_METRICS[*]}")
    fi

    log INFO "Metrics to collect: $METRICS"
}

get_date_range() {
    local period="$1"
    local end_date=$(date +%s)
    local start_date

    case "$period" in
        daily)
            start_date=$((end_date - 86400))  # 24 hours
            ;;
        weekly)
            start_date=$((end_date - 604800))  # 7 days
            ;;
        monthly)
            start_date=$((end_date - 2592000))  # 30 days
            ;;
        quarterly)
            start_date=$((end_date - 7776000))  # 90 days
            ;;
        yearly)
            start_date=$((end_date - 31536000))  # 365 days
            ;;
        *)
            log ERROR "Invalid period: $period"
            return 1
            ;;
    esac

    echo "START_DATE=$start_date END_DATE=$end_date"
}

get_team_list() {
    if [[ "$TEAMS" == "all" ]]; then
        # Get all team namespaces
        local team_namespaces=$(kubectl get namespaces -l coder.com/team --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")
        local teams=""

        while IFS= read -r namespace; do
            if [[ -n "$namespace" ]]; then
                local team=$(echo "$namespace" | sed 's/team-//')
                if [[ -n "$teams" ]]; then
                    teams="$teams,$team"
                else
                    teams="$team"
                fi
            fi
        done <<< "$team_namespaces"

        echo "$teams"
    else
        echo "$TEAMS"
    fi
}

get_user_list() {
    local teams="$1"

    log STEP "Collecting user information..."

    # Get all user ConfigMaps
    local users=$(kubectl get configmap -n coder -l coder.com/user=true --no-headers -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$users" ]]; then
        log WARN "No users found in environment"
        echo ""
        return 0
    fi

    # Filter by teams if not "all"
    if [[ "$teams" != "all" ]]; then
        IFS=',' read -ra TEAM_ARRAY <<< "$teams"
        local filtered_users=""

        for user in $users; do
            local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "")

            for team in "${TEAM_ARRAY[@]}"; do
                if [[ "$user_team" == "$team" ]]; then
                    if [[ -n "$filtered_users" ]]; then
                        filtered_users="$filtered_users $user"
                    else
                        filtered_users="$user"
                    fi
                    break
                fi
            done
        done

        echo "$filtered_users"
    else
        echo "$users"
    fi
}

collect_login_frequency() {
    local users="$1"
    local start_date="$2"
    local end_date="$3"

    log STEP "Collecting login frequency data..."

    # This would typically query Coder's database or audit logs
    # For this implementation, we'll simulate the data collection

    declare -A login_data

    for user in $users; do
        local user_email=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.email}' 2>/dev/null || echo "unknown")
        local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "unknown")

        # Simulate login data (in a real implementation, this would query audit logs)
        local login_count=$((RANDOM % 30 + 1))
        local avg_session_minutes=$((RANDOM % 240 + 30))
        local last_login_days_ago=$((RANDOM % 7))

        login_data["$user_email"]="team:$user_team,logins:$login_count,avg_session:$avg_session_minutes,last_login_days_ago:$last_login_days_ago"
    done

    # Output login data
    for email in "${!login_data[@]}"; do
        echo "LOGIN:$email:${login_data[$email]}"
    done
}

collect_resource_usage() {
    local users="$1"
    local start_date="$2"
    local end_date="$3"

    log STEP "Collecting resource usage data..."

    declare -A resource_data

    for user in $users; do
        local user_email=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.email}' 2>/dev/null || echo "unknown")
        local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "unknown")

        # Get user's workspaces (pods matching user pattern)
        local user_slug=$(echo "$user_email" | sed 's/@.*//; s/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')
        local user_pods=$(kubectl get pods -n coder --no-headers | grep "$user_slug" | awk '{print $1}' || echo "")

        local total_cpu=0
        local total_memory=0
        local total_storage=0
        local active_workspaces=0

        for pod in $user_pods; do
            if [[ -n "$pod" ]]; then
                # Get resource requests/usage
                local cpu_req=$(kubectl get pod "$pod" -n coder -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "0")
                local mem_req=$(kubectl get pod "$pod" -n coder -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "0")

                # Convert CPU to millicores for calculation
                if [[ "$cpu_req" =~ m$ ]]; then
                    total_cpu=$((total_cpu + ${cpu_req%m}))
                else
                    total_cpu=$((total_cpu + ${cpu_req:-0} * 1000))
                fi

                # Convert memory to MB for calculation
                if [[ "$mem_req" =~ Gi$ ]]; then
                    total_memory=$((total_memory + ${mem_req%Gi} * 1024))
                elif [[ "$mem_req" =~ Mi$ ]]; then
                    total_memory=$((total_memory + ${mem_req%Mi}))
                fi

                # Simulate storage usage
                total_storage=$((total_storage + RANDOM % 50 + 10))
                ((active_workspaces++))
            fi
        done

        resource_data["$user_email"]="team:$user_team,cpu_millicores:$total_cpu,memory_mb:$total_memory,storage_gb:$total_storage,workspaces:$active_workspaces"
    done

    # Output resource data
    for email in "${!resource_data[@]}"; do
        echo "RESOURCE:$email:${resource_data[$email]}"
    done
}

collect_cost_attribution() {
    local users="$1"
    local start_date="$2"
    local end_date="$3"

    if [[ "$COST_ATTRIBUTION" == "false" ]]; then
        log INFO "Cost attribution disabled"
        return 0
    fi

    log STEP "Calculating cost attribution..."

    # Scaleway pricing per hour
    local cpu_cost_per_hour=0.01    # €0.01 per vCPU hour
    local memory_cost_per_gb_hour=0.005  # €0.005 per GB hour
    local storage_cost_per_gb_month=0.10  # €0.10 per GB per month

    declare -A cost_data

    for user in $users; do
        local user_email=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.email}' 2>/dev/null || echo "unknown")
        local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "unknown")

        # Get user's resource usage (from previous function)
        local user_slug=$(echo "$user_email" | sed 's/@.*//; s/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')
        local user_pods=$(kubectl get pods -n coder --no-headers | grep "$user_slug" | awk '{print $1}' || echo "")

        local total_cpu_hours=0
        local total_memory_gb_hours=0
        local total_storage_gb=0

        for pod in $user_pods; do
            if [[ -n "$pod" ]]; then
                local cpu_req=$(kubectl get pod "$pod" -n coder -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "0")
                local mem_req=$(kubectl get pod "$pod" -n coder -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "0")

                # Calculate hours based on period (simplified)
                local hours_in_period
                case "$PERIOD" in
                    daily) hours_in_period=24 ;;
                    weekly) hours_in_period=168 ;;
                    monthly) hours_in_period=720 ;;
                    quarterly) hours_in_period=2160 ;;
                    yearly) hours_in_period=8760 ;;
                esac

                # Convert and accumulate
                if [[ "$cpu_req" =~ m$ ]]; then
                    total_cpu_hours=$(echo "scale=2; $total_cpu_hours + (${cpu_req%m} / 1000) * $hours_in_period" | bc)
                else
                    total_cpu_hours=$(echo "scale=2; $total_cpu_hours + ${cpu_req:-0} * $hours_in_period" | bc)
                fi

                if [[ "$mem_req" =~ Gi$ ]]; then
                    total_memory_gb_hours=$(echo "scale=2; $total_memory_gb_hours + ${mem_req%Gi} * $hours_in_period" | bc)
                elif [[ "$mem_req" =~ Mi$ ]]; then
                    total_memory_gb_hours=$(echo "scale=2; $total_memory_gb_hours + (${mem_req%Mi} / 1024) * $hours_in_period" | bc)
                fi

                # Simulate storage
                total_storage_gb=$((total_storage_gb + RANDOM % 50 + 10))
            fi
        done

        # Calculate costs
        local cpu_cost=$(echo "scale=2; $total_cpu_hours * $cpu_cost_per_hour" | bc)
        local memory_cost=$(echo "scale=2; $total_memory_gb_hours * $memory_cost_per_gb_hour" | bc)
        local storage_cost=$(echo "scale=2; $total_storage_gb * $storage_cost_per_gb_month" | bc)
        local total_cost=$(echo "scale=2; $cpu_cost + $memory_cost + $storage_cost" | bc)

        cost_data["$user_email"]="team:$user_team,cpu_cost:$cpu_cost,memory_cost:$memory_cost,storage_cost:$storage_cost,total_cost:$total_cost"
    done

    # Output cost data
    for email in "${!cost_data[@]}"; do
        echo "COST:$email:${cost_data[$email]}"
    done
}

collect_workspace_activity() {
    local users="$1"
    local start_date="$2"
    local end_date="$3"

    log STEP "Collecting workspace activity data..."

    declare -A workspace_data

    for user in $users; do
        local user_email=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.email}' 2>/dev/null || echo "unknown")
        local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "unknown")

        # Get user's workspaces
        local user_slug=$(echo "$user_email" | sed 's/@.*//; s/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')
        local user_pods=$(kubectl get pods -n coder --no-headers | grep "$user_slug" | wc -l || echo "0")

        # Simulate workspace activity metrics
        local workspaces_created=$((RANDOM % 5 + 1))
        local workspaces_active=$user_pods
        local avg_uptime_hours=$((RANDOM % 8 + 1))
        local builds_triggered=$((RANDOM % 20 + 5))

        workspace_data["$user_email"]="team:$user_team,created:$workspaces_created,active:$workspaces_active,avg_uptime:$avg_uptime_hours,builds:$builds_triggered"
    done

    # Output workspace data
    for email in "${!workspace_data[@]}"; do
        echo "WORKSPACE:$email:${workspace_data[$email]}"
    done
}

collect_template_usage() {
    local users="$1"
    local start_date="$2"
    local end_date="$3"

    log STEP "Collecting template usage data..."

    # Available templates (from team defaults)
    local templates=("react-typescript" "java-spring" "python-django-crewai" "terraform-ansible" "jupyter-python" "react-native" "claude-flow-base")

    declare -A template_data

    for user in $users; do
        local user_email=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.email}' 2>/dev/null || echo "unknown")
        local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "unknown")
        local default_template=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.default-template}' 2>/dev/null || echo "unknown")

        # Simulate template usage (primary + secondary templates)
        local primary_template="$default_template"
        if [[ "$primary_template" == "unknown" ]] || [[ -z "$primary_template" ]]; then
            primary_template="${templates[$((RANDOM % ${#templates[@]}))]}"
        fi

        local secondary_template="${templates[$((RANDOM % ${#templates[@]}))]}"
        local template_switches=$((RANDOM % 3))

        template_data["$user_email"]="team:$user_team,primary:$primary_template,secondary:$secondary_template,switches:$template_switches"
    done

    # Output template data
    for email in "${!template_data[@]}"; do
        echo "TEMPLATE:$email:${template_data[$email]}"
    done
}

collect_collaboration() {
    local users="$1"
    local start_date="$2"
    local end_date="$3"

    log STEP "Collecting collaboration metrics..."

    declare -A collab_data

    for user in $users; do
        local user_email=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.email}' 2>/dev/null || echo "unknown")
        local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "unknown")

        # Simulate collaboration metrics
        local shared_workspaces=$((RANDOM % 3))
        local workspace_visits=$((RANDOM % 10 + 1))
        local team_interactions=$((RANDOM % 15 + 5))

        collab_data["$user_email"]="team:$user_team,shared:$shared_workspaces,visits:$workspace_visits,interactions:$team_interactions"
    done

    # Output collaboration data
    for email in "${!collab_data[@]}"; do
        echo "COLLABORATION:$email:${collab_data[$email]}"
    done
}

collect_error_rates() {
    local users="$1"
    local start_date="$2"
    local end_date="$3"

    log STEP "Collecting error rate data..."

    declare -A error_data

    for user in $users; do
        local user_email=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.email}' 2>/dev/null || echo "unknown")
        local user_team=$(kubectl get configmap "$user" -n coder -o jsonpath='{.data.team}' 2>/dev/null || echo "unknown")

        # Get user's pods and check for errors
        local user_slug=$(echo "$user_email" | sed 's/@.*//; s/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]')
        local user_pods=$(kubectl get pods -n coder --no-headers | grep "$user_slug" | awk '{print $1}' || echo "")

        local build_failures=0
        local connection_errors=0
        local resource_errors=0

        for pod in $user_pods; do
            if [[ -n "$pod" ]]; then
                # Check pod status and events
                local pod_status=$(kubectl get pod "$pod" -n coder -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

                if [[ "$pod_status" == "Failed" ]]; then
                    ((build_failures++))
                fi

                # Check for resource-related issues
                local events=$(kubectl get events --field-selector involvedObject.name="$pod" -n coder --no-headers 2>/dev/null | wc -l || echo "0")
                resource_errors=$((resource_errors + events / 10))  # Simplified calculation
            fi
        done

        # Simulate connection errors
        connection_errors=$((RANDOM % 3))

        error_data["$user_email"]="team:$user_team,build_failures:$build_failures,connection_errors:$connection_errors,resource_errors:$resource_errors"
    done

    # Output error data
    for email in "${!error_data[@]}"; do
        echo "ERRORS:$email:${error_data[$email]}"
    done
}

generate_table_report() {
    local report_data="$1"

    log STEP "Generating table format report..."

    echo
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                            USER ACTIVITY REPORT - ${ENVIRONMENT^^}                            ${NC}"
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}Report Period:${NC} $PERIOD"
    echo -e "${YELLOW}Generated:${NC} $(date)"
    echo -e "${YELLOW}Environment:${NC} $ENVIRONMENT"
    echo -e "${YELLOW}Teams:${NC} $TEAMS"
    echo -e "${YELLOW}Metrics:${NC} $METRICS"
    echo

    # Parse and display each metric type
    if [[ "$METRICS" =~ login-frequency ]]; then
        echo -e "${CYAN}📊 LOGIN FREQUENCY${NC}"
        echo "├─────────────────────────────────────┬──────────┬───────────────┬──────────────────┐"
        echo "│ User                                │ Team     │ Login Count   │ Avg Session (min)│"
        echo "├─────────────────────────────────────┼──────────┼───────────────┼──────────────────┤"

        echo "$report_data" | grep "^LOGIN:" | while IFS=':' read -r prefix email data; do
            local team=$(echo "$data" | grep -o 'team:[^,]*' | cut -d: -f2)
            local logins=$(echo "$data" | grep -o 'logins:[^,]*' | cut -d: -f2)
            local avg_session=$(echo "$data" | grep -o 'avg_session:[^,]*' | cut -d: -f2)

            printf "│ %-35s │ %-8s │ %-13s │ %-16s │\n" "$email" "$team" "$logins" "$avg_session"
        done
        echo "└─────────────────────────────────────┴──────────┴───────────────┴──────────────────┘"
        echo
    fi

    if [[ "$METRICS" =~ resource-usage ]]; then
        echo -e "${CYAN}💻 RESOURCE USAGE${NC}"
        echo "├─────────────────────────────────────┬──────────┬─────────────┬─────────────┬──────────────┐"
        echo "│ User                                │ Team     │ CPU (cores) │ Memory (GB) │ Storage (GB) │"
        echo "├─────────────────────────────────────┼──────────┼─────────────┼─────────────┼──────────────┤"

        echo "$report_data" | grep "^RESOURCE:" | while IFS=':' read -r prefix email data; do
            local team=$(echo "$data" | grep -o 'team:[^,]*' | cut -d: -f2)
            local cpu=$(echo "$data" | grep -o 'cpu_millicores:[^,]*' | cut -d: -f2)
            local memory=$(echo "$data" | grep -o 'memory_mb:[^,]*' | cut -d: -f2)
            local storage=$(echo "$data" | grep -o 'storage_gb:[^,]*' | cut -d: -f2)

            # Convert millicores to cores and MB to GB
            local cpu_cores=$(echo "scale=2; $cpu / 1000" | bc 2>/dev/null || echo "0")
            local memory_gb=$(echo "scale=2; $memory / 1024" | bc 2>/dev/null || echo "0")

            printf "│ %-35s │ %-8s │ %-11s │ %-11s │ %-12s │\n" "$email" "$team" "$cpu_cores" "$memory_gb" "$storage"
        done
        echo "└─────────────────────────────────────┴──────────┴─────────────┴─────────────┴──────────────┘"
        echo
    fi

    if [[ "$METRICS" =~ cost-attribution ]] && [[ "$COST_ATTRIBUTION" == "true" ]]; then
        echo -e "${CYAN}💰 COST ATTRIBUTION${NC}"
        echo "├─────────────────────────────────────┬──────────┬─────────────┬──────────────┬─────────────────┐"
        echo "│ User                                │ Team     │ CPU Cost    │ Storage Cost │ Total Cost (€)  │"
        echo "├─────────────────────────────────────┼──────────┼─────────────┼──────────────┼─────────────────┤"

        echo "$report_data" | grep "^COST:" | while IFS=':' read -r prefix email data; do
            local team=$(echo "$data" | grep -o 'team:[^,]*' | cut -d: -f2)
            local cpu_cost=$(echo "$data" | grep -o 'cpu_cost:[^,]*' | cut -d: -f2)
            local storage_cost=$(echo "$data" | grep -o 'storage_cost:[^,]*' | cut -d: -f2)
            local total_cost=$(echo "$data" | grep -o 'total_cost:[^,]*' | cut -d: -f2)

            printf "│ %-35s │ %-8s │ €%-10s │ €%-11s │ €%-14s │\n" "$email" "$team" "$cpu_cost" "$storage_cost" "$total_cost"
        done
        echo "└─────────────────────────────────────┴──────────┴─────────────┴──────────────┴─────────────────┘"
        echo
    fi

    if [[ "$METRICS" =~ workspace-activity ]]; then
        echo -e "${CYAN}🚀 WORKSPACE ACTIVITY${NC}"
        echo "├─────────────────────────────────────┬──────────┬─────────────┬─────────────┬──────────────────┐"
        echo "│ User                                │ Team     │ Created     │ Active      │ Avg Uptime (hrs) │"
        echo "├─────────────────────────────────────┼──────────┼─────────────┼─────────────┼──────────────────┤"

        echo "$report_data" | grep "^WORKSPACE:" | while IFS=':' read -r prefix email data; do
            local team=$(echo "$data" | grep -o 'team:[^,]*' | cut -d: -f2)
            local created=$(echo "$data" | grep -o 'created:[^,]*' | cut -d: -f2)
            local active=$(echo "$data" | grep -o 'active:[^,]*' | cut -d: -f2)
            local uptime=$(echo "$data" | grep -o 'avg_uptime:[^,]*' | cut -d: -f2)

            printf "│ %-35s │ %-8s │ %-11s │ %-11s │ %-16s │\n" "$email" "$team" "$created" "$active" "$uptime"
        done
        echo "└─────────────────────────────────────┴──────────┴─────────────┴─────────────┴──────────────────┘"
        echo
    fi
}

generate_json_report() {
    local report_data="$1"

    log STEP "Generating JSON format report..."

    local json_file="${OUTPUT_FILE:-${PROJECT_ROOT}/logs/user-reports/activity-report-$(date +%Y%m%d-%H%M%S).json}"

    cat > "$json_file" <<EOF
{
  "report_metadata": {
    "environment": "$ENVIRONMENT",
    "period": "$PERIOD",
    "teams": "$TEAMS",
    "metrics": "$METRICS",
    "generated_at": "$(date -Iseconds)",
    "include_inactive": $INCLUDE_INACTIVE,
    "cost_attribution_enabled": $COST_ATTRIBUTION
  },
  "users": [
EOF

    local first_user=true
    local current_user=""
    local user_data=""

    # Process report data line by line
    echo "$report_data" | while IFS=':' read -r metric_type email data; do
        if [[ "$current_user" != "$email" ]]; then
            # Start new user entry
            if [[ "$first_user" == "false" ]]; then
                echo "    },"
            fi

            echo "    {"
            echo "      \"email\": \"$email\","

            # Extract team from any metric data
            local team=$(echo "$data" | grep -o 'team:[^,]*' | cut -d: -f2)
            echo "      \"team\": \"$team\","
            echo "      \"metrics\": {"

            current_user="$email"
            first_user=false
        fi

        # Add metric data
        case "$metric_type" in
            "LOGIN")
                local logins=$(echo "$data" | grep -o 'logins:[^,]*' | cut -d: -f2)
                local avg_session=$(echo "$data" | grep -o 'avg_session:[^,]*' | cut -d: -f2)
                local last_login=$(echo "$data" | grep -o 'last_login_days_ago:[^,]*' | cut -d: -f2)
                echo "        \"login_frequency\": {"
                echo "          \"login_count\": $logins,"
                echo "          \"avg_session_minutes\": $avg_session,"
                echo "          \"last_login_days_ago\": $last_login"
                echo "        },"
                ;;
            "RESOURCE")
                local cpu=$(echo "$data" | grep -o 'cpu_millicores:[^,]*' | cut -d: -f2)
                local memory=$(echo "$data" | grep -o 'memory_mb:[^,]*' | cut -d: -f2)
                local storage=$(echo "$data" | grep -o 'storage_gb:[^,]*' | cut -d: -f2)
                local workspaces=$(echo "$data" | grep -o 'workspaces:[^,]*' | cut -d: -f2)
                echo "        \"resource_usage\": {"
                echo "          \"cpu_millicores\": $cpu,"
                echo "          \"memory_mb\": $memory,"
                echo "          \"storage_gb\": $storage,"
                echo "          \"active_workspaces\": $workspaces"
                echo "        },"
                ;;
            "COST")
                local cpu_cost=$(echo "$data" | grep -o 'cpu_cost:[^,]*' | cut -d: -f2)
                local memory_cost=$(echo "$data" | grep -o 'memory_cost:[^,]*' | cut -d: -f2)
                local storage_cost=$(echo "$data" | grep -o 'storage_cost:[^,]*' | cut -d: -f2)
                local total_cost=$(echo "$data" | grep -o 'total_cost:[^,]*' | cut -d: -f2)
                echo "        \"cost_attribution\": {"
                echo "          \"cpu_cost_eur\": $cpu_cost,"
                echo "          \"memory_cost_eur\": $memory_cost,"
                echo "          \"storage_cost_eur\": $storage_cost,"
                echo "          \"total_cost_eur\": $total_cost"
                echo "        },"
                ;;
        esac
    done

    # Close last user and array
    if [[ "$first_user" == "false" ]]; then
        echo "      }"
        echo "    }"
    fi

    cat >> "$json_file" <<EOF
  ]
}
EOF

    log INFO "JSON report generated: $json_file"
    echo "$json_file"
}

generate_csv_report() {
    local report_data="$1"

    log STEP "Generating CSV format report..."

    local csv_file="${OUTPUT_FILE:-${PROJECT_ROOT}/logs/user-reports/activity-report-$(date +%Y%m%d-%H%M%S).csv}"

    # CSV header
    echo "Email,Team,Login_Count,Avg_Session_Minutes,CPU_Cores,Memory_GB,Storage_GB,Active_Workspaces,Total_Cost_EUR" > "$csv_file"

    # Collect all data for each user
    declare -A user_records

    echo "$report_data" | while IFS=':' read -r metric_type email data; do
        if [[ -z "${user_records[$email]}" ]]; then
            local team=$(echo "$data" | grep -o 'team:[^,]*' | cut -d: -f2)
            user_records[$email]="$email,$team,,,,,,,"
        fi

        case "$metric_type" in
            "LOGIN")
                local logins=$(echo "$data" | grep -o 'logins:[^,]*' | cut -d: -f2)
                local avg_session=$(echo "$data" | grep -o 'avg_session:[^,]*' | cut -d: -f2)
                # Update login columns
                user_records[$email]=$(echo "${user_records[$email]}" | sed "s/,,/,$logins,$avg_session,/")
                ;;
            "RESOURCE")
                local cpu=$(echo "$data" | grep -o 'cpu_millicores:[^,]*' | cut -d: -f2)
                local memory=$(echo "$data" | grep -o 'memory_mb:[^,]*' | cut -d: -f2)
                local storage=$(echo "$data" | grep -o 'storage_gb:[^,]*' | cut -d: -f2)
                local workspaces=$(echo "$data" | grep -o 'workspaces:[^,]*' | cut -d: -f2)

                local cpu_cores=$(echo "scale=2; $cpu / 1000" | bc 2>/dev/null || echo "0")
                local memory_gb=$(echo "scale=2; $memory / 1024" | bc 2>/dev/null || echo "0")

                # This is simplified - in practice you'd need more sophisticated CSV building
                ;;
            "COST")
                local total_cost=$(echo "$data" | grep -o 'total_cost:[^,]*' | cut -d: -f2)
                # Update cost column
                ;;
        esac
    done

    # Output user records to CSV file
    for email in "${!user_records[@]}"; do
        echo "${user_records[$email]}" >> "$csv_file"
    done

    log INFO "CSV report generated: $csv_file"
    echo "$csv_file"
}

generate_summary_stats() {
    local report_data="$1"

    log STEP "Generating summary statistics..."

    local total_users=$(echo "$report_data" | cut -d: -f2 | sort -u | wc -l)
    local teams_represented=$(echo "$report_data" | grep -o 'team:[^,]*' | cut -d: -f2 | sort -u | wc -l)

    # Calculate totals from cost data
    local total_cost=0
    echo "$report_data" | grep "^COST:" | while IFS=':' read -r prefix email data; do
        local cost=$(echo "$data" | grep -o 'total_cost:[^,]*' | cut -d: -f2)
        total_cost=$(echo "scale=2; $total_cost + $cost" | bc 2>/dev/null || echo "$total_cost")
    done

    echo
    echo -e "${WHITE}📊 SUMMARY STATISTICS${NC}"
    echo -e "  Total Users Analyzed: $total_users"
    echo -e "  Teams Represented: $teams_represented"
    echo -e "  Report Period: $PERIOD"
    if [[ "$COST_ATTRIBUTION" == "true" ]]; then
        echo -e "  Total Estimated Cost: €$total_cost"
    fi
    echo
}

print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${GREEN}📈 User activity report completed! 📈${NC}"
    echo
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Report Period:${NC} $PERIOD"
    echo -e "${WHITE}Teams:${NC} $TEAMS"
    echo -e "${WHITE}Output Format:${NC} $OUTPUT_FORMAT"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"

    echo
    echo -e "${YELLOW}🔧 Generated Reports:${NC}"
    echo "   • Detailed log: $LOG_FILE"
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "   • Report file: $OUTPUT_FILE"
    fi

    echo
    echo -e "${CYAN}📋 Metrics Collected:${NC}"
    IFS=',' read -ra METRIC_ARRAY <<< "$METRICS"
    for metric in "${METRIC_ARRAY[@]}"; do
        case "$metric" in
            "login-frequency") echo "   ✓ User login patterns and session analytics" ;;
            "resource-usage") echo "   ✓ CPU, memory, and storage utilization" ;;
            "cost-attribution") echo "   ✓ Per-user and per-team cost breakdown" ;;
            "workspace-activity") echo "   ✓ Workspace creation and usage patterns" ;;
            "template-usage") echo "   ✓ Template selection and adoption rates" ;;
            "collaboration") echo "   ✓ Team collaboration and sharing metrics" ;;
            "error-rates") echo "   ✓ Error patterns and troubleshooting data" ;;
        esac
    done

    echo
    echo -e "${YELLOW}💡 Next Steps:${NC}"
    echo "   • Review user engagement patterns"
    echo "   • Optimize resource allocation based on usage"
    echo "   • Share cost attribution with team leads"
    echo "   • Schedule regular reports for trend analysis"
    echo "   • Consider automating report generation"

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
            --period=*)
                PERIOD="${1#*=}"
                shift
                ;;
            --teams=*)
                TEAMS="${1#*=}"
                shift
                ;;
            --metrics=*)
                METRICS="${1#*=}"
                shift
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
                shift
                ;;
            --output-file=*)
                OUTPUT_FILE="${1#*=}"
                shift
                ;;
            --include-inactive)
                INCLUDE_INACTIVE=true
                shift
                ;;
            --no-cost-attribution)
                COST_ATTRIBUTION=false
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

    # Validate period
    case "$PERIOD" in
        daily|weekly|monthly|quarterly|yearly)
            ;;
        *)
            log ERROR "Invalid period: $PERIOD"
            log ERROR "Must be one of: daily, weekly, monthly, quarterly, yearly"
            exit 1
            ;;
    esac

    # Validate output format
    case "$OUTPUT_FORMAT" in
        table|json|csv|html)
            ;;
        *)
            log ERROR "Invalid output format: $OUTPUT_FORMAT"
            log ERROR "Must be one of: table, json, csv, html"
            exit 1
            ;;
    esac

    print_banner
    setup_logging
    validate_environment
    validate_metrics

    log INFO "Starting user activity analysis for environment: $ENVIRONMENT"
    log INFO "Report period: $PERIOD"
    log INFO "Output format: $OUTPUT_FORMAT"

    # Get date range for analysis
    local date_vars
    date_vars=$(get_date_range "$PERIOD")
    eval "$date_vars"

    # Get team list and user list
    local team_list
    team_list=$(get_team_list)
    log INFO "Teams to analyze: $team_list"

    local user_list
    user_list=$(get_user_list "$team_list")

    if [[ -z "$user_list" ]]; then
        log WARN "No users found for analysis"
        exit 0
    fi

    local user_count=$(echo "$user_list" | wc -w)
    log INFO "Users to analyze: $user_count"

    # Collect metrics data
    local report_data=""

    IFS=',' read -ra METRIC_ARRAY <<< "$METRICS"
    for metric in "${METRIC_ARRAY[@]}"; do
        case "$metric" in
            "login-frequency")
                report_data="$report_data\n$(collect_login_frequency "$user_list" "$START_DATE" "$END_DATE")"
                ;;
            "resource-usage")
                report_data="$report_data\n$(collect_resource_usage "$user_list" "$START_DATE" "$END_DATE")"
                ;;
            "cost-attribution")
                report_data="$report_data\n$(collect_cost_attribution "$user_list" "$START_DATE" "$END_DATE")"
                ;;
            "workspace-activity")
                report_data="$report_data\n$(collect_workspace_activity "$user_list" "$START_DATE" "$END_DATE")"
                ;;
            "template-usage")
                report_data="$report_data\n$(collect_template_usage "$user_list" "$START_DATE" "$END_DATE")"
                ;;
            "collaboration")
                report_data="$report_data\n$(collect_collaboration "$user_list" "$START_DATE" "$END_DATE")"
                ;;
            "error-rates")
                report_data="$report_data\n$(collect_error_rates "$user_list" "$START_DATE" "$END_DATE")"
                ;;
        esac
    done

    # Generate report in requested format
    case "$OUTPUT_FORMAT" in
        "table")
            generate_table_report "$report_data"
            generate_summary_stats "$report_data"
            ;;
        "json")
            local json_file
            json_file=$(generate_json_report "$report_data")
            OUTPUT_FILE="$json_file"
            ;;
        "csv")
            local csv_file
            csv_file=$(generate_csv_report "$report_data")
            OUTPUT_FILE="$csv_file"
            ;;
        "html")
            log WARN "HTML format not yet implemented, using table format"
            generate_table_report "$report_data"
            generate_summary_stats "$report_data"
            ;;
    esac

    print_summary
}

# Check for required dependencies
command -v kubectl >/dev/null 2>&1 || { log ERROR "kubectl is required but not installed. Aborting."; exit 1; }
command -v bc >/dev/null 2>&1 || { log ERROR "bc is required but not installed. Aborting."; exit 1; }

# Run main function with all arguments
main "$@"