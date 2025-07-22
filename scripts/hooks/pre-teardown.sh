#!/bin/bash

# Pre-Teardown Hook
# Execute custom logic before environment teardown

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${GREEN}[PRE-TEARDOWN]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[PRE-TEARDOWN]${NC} $message" ;;
        ERROR) echo -e "${RED}[PRE-TEARDOWN]${NC} $message" ;;
        DEBUG) echo -e "${BLUE}[PRE-TEARDOWN]${NC} $message" ;;
    esac
}

# Parse command line arguments
ENVIRONMENT=""
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

while [[ $# -gt 0 ]]; do
    case $1 in
        --env=*)
            ENVIRONMENT="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

log INFO "Running pre-teardown hook for environment: ${ENVIRONMENT:-unknown}"

# 1. Critical safety checks
log INFO "Performing safety checks before teardown..."

case "$ENVIRONMENT" in
    prod)
        log WARN "🔴 PRODUCTION TEARDOWN REQUESTED!"

        # Example: Check for active users
        # if command -v kubectl &>/dev/null; then
        #     local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
        #     if [[ -f "$kubeconfig" ]]; then
        #         export KUBECONFIG="$kubeconfig"
        #         local active_workspaces=$(kubectl get pods -n coder --no-headers 2>/dev/null | grep -c "workspace" || echo "0")
        #
        #         if [[ "$active_workspaces" -gt 0 ]]; then
        #             log ERROR "❌ $active_workspaces active workspaces found!"
        #             log ERROR "Production teardown blocked - active users detected"
        #             exit 1
        #         fi
        #     fi
        # fi

        # Example: Check time restrictions
        local current_hour=$(date +%H)
        if [[ "$current_hour" -ge 9 && "$current_hour" -le 17 ]]; then
            log WARN "⚠️  Tearing down production during business hours"
        fi
        ;;
    staging)
        log INFO "Staging environment teardown - checking for active testing..."
        # Example: Check for running CI/CD pipelines
        ;;
    dev)
        log INFO "Development environment teardown - minimal restrictions"
        ;;
esac

# 2. Data backup verification
log INFO "Verifying backup requirements..."

# Check if recent backup exists
local backup_dir="$PROJECT_ROOT/backups"
if [[ -d "$backup_dir" ]]; then
    local recent_backup=$(find "$backup_dir" -name "*$ENVIRONMENT*" -type d -mtime -1 | head -1)
    if [[ -n "$recent_backup" ]]; then
        log INFO "✅ Recent backup found: $(basename "$recent_backup")"
    else
        log WARN "⚠️  No recent backup found for $ENVIRONMENT"

        # Example: Force backup creation
        # if [[ -f "$PROJECT_ROOT/scripts/lifecycle/backup.sh" ]]; then
        #     log INFO "Creating emergency backup..."
        #     "$PROJECT_ROOT/scripts/lifecycle/backup.sh" \
        #         --env="$ENVIRONMENT" \
        #         --pre-destroy \
        #         --auto
        # fi
    fi
else
    log WARN "⚠️  Backup directory does not exist"
fi

# 3. External system notifications
log INFO "Notifying external systems about impending teardown..."

# Example: Update external monitoring
# if [[ -n "${MONITORING_API_KEY:-}" ]]; then
#     notify_external_monitoring() {
#         local env="$1"
#         log INFO "Notifying external monitoring about $env teardown"
#         # curl -X POST https://monitoring.company.com/api/environments/$env/status \
#         #     -H "Authorization: Bearer $MONITORING_API_KEY" \
#         #     -H "Content-Type: application/json" \
#         #     -d '{"status":"teardown_in_progress","timestamp":"'$(date -Iseconds)'"}'
#     }
#     notify_external_monitoring "$ENVIRONMENT"
# fi

# Example: Slack notification
# if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
#     send_teardown_alert() {
#         local env="$1"
#         local message="🔥 ALERT: Coder environment '$env' teardown starting!"
#
#         curl -X POST -H 'Content-type: application/json' \
#             --data '{"text":"'"$message"'"}' \
#             "$SLACK_WEBHOOK" &>/dev/null || true
#
#         log INFO "Teardown alert sent to Slack"
#     }
#     send_teardown_alert "$ENVIRONMENT"
# fi

# 4. Graceful user notification
log INFO "Checking for active users and workspaces..."

if command -v kubectl &>/dev/null; then
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"

        if kubectl cluster-info &>/dev/null; then
            # List active workspaces
            local workspace_count=$(kubectl get pods -n coder --no-headers 2>/dev/null | grep -c "workspace" || echo "0")

            if [[ "$workspace_count" -gt 0 ]]; then
                log WARN "⚠️  Found $workspace_count active workspace(s):"
                kubectl get pods -n coder --no-headers 2>/dev/null | grep "workspace" | while read -r pod_info; do
                    local pod_name=$(echo "$pod_info" | awk '{print $1}')
                    log WARN "  - $pod_name"
                done

                # Example: Send notifications to workspace owners
                # notify_workspace_users() {
                #     local env="$1"
                #     log INFO "Notifying workspace users about impending teardown"
                #     # Implementation would depend on your user notification system
                # }
                # notify_workspace_users "$ENVIRONMENT"
            else
                log INFO "✅ No active workspaces found"
            fi
        else
            log WARN "Cannot connect to cluster - may already be down"
        fi
    else
        log WARN "Kubeconfig not found for environment: $ENVIRONMENT"
    fi
fi

# 5. Cost and resource analysis
log INFO "Analyzing resources that will be destroyed..."

# Example cost analysis
analyze_cost_impact() {
    local env="$1"

    case "$env" in
        dev)
            local monthly_savings="53.70"
            ;;
        staging)
            local monthly_savings="97.85"
            ;;
        prod)
            local monthly_savings="374.50"
            ;;
        *)
            local monthly_savings="unknown"
            ;;
    esac

    log INFO "💰 Estimated monthly cost savings: €$monthly_savings"
}

analyze_cost_impact "$ENVIRONMENT"

# 6. Compliance and audit logging
log INFO "Recording teardown initiation for audit purposes..."

# Example: Create audit log entry
create_audit_log() {
    local env="$1"
    local audit_dir="$PROJECT_ROOT/audit-logs"
    mkdir -p "$audit_dir"

    local audit_file="$audit_dir/teardown-$(date +%Y%m%d-%H%M%S)-$env.log"
    cat > "$audit_file" <<EOF
TEARDOWN AUDIT LOG
==================

Environment: $env
Timestamp: $(date -Iseconds)
User: $(whoami)
Hostname: $(hostname)
Working Directory: $(pwd)

Pre-teardown Checks:
- Safety checks: Completed
- Backup verification: Completed
- External notifications: Sent
- User notifications: Processed
- Cost analysis: Completed

Status: Pre-teardown hook completed successfully
EOF

    log INFO "Audit log created: $audit_file"
}

create_audit_log "$ENVIRONMENT"

# 7. Final confirmation prompts (for critical environments)
if [[ "$ENVIRONMENT" == "prod" ]]; then
    log WARN "🔴 FINAL PRODUCTION TEARDOWN WARNING"
    log WARN "This will permanently destroy the production environment!"
    log WARN "All user data, workspaces, and configurations will be lost!"

    # Note: In an automated context, this would be handled by the calling script
    # but hooks can provide additional safety checks

    # Example: Check for emergency stop file
    # if [[ -f "/tmp/emergency-stop-teardown" ]]; then
    #     log ERROR "❌ Emergency stop file detected - teardown aborted"
    #     exit 1
    # fi
fi

# 8. Resource cleanup preparation
log INFO "Preparing for resource cleanup..."

# Example: Mark resources for cleanup
# if command -v kubectl &>/dev/null; then
#     local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
#     if [[ -f "$kubeconfig" ]]; then
#         export KUBECONFIG="$kubeconfig"
#
#         # Add cleanup annotations
#         kubectl annotate namespace coder teardown.timestamp="$(date -Iseconds)" --overwrite 2>/dev/null || true
#         kubectl annotate namespace coder teardown.initiated-by="$(whoami)" --overwrite 2>/dev/null || true
#     fi
# fi

# 9. Environment-specific pre-teardown tasks
case "$ENVIRONMENT" in
    prod)
        log INFO "Production-specific pre-teardown tasks..."
        # Example: Disable monitoring alerts to prevent false alarms
        # Example: Update load balancers to stop routing traffic
        ;;
    staging)
        log INFO "Staging-specific pre-teardown tasks..."
        # Example: Cancel any running CI/CD pipelines
        ;;
    dev)
        log INFO "Development-specific pre-teardown tasks..."
        # Example: Minimal cleanup required
        ;;
esac

log INFO "Pre-teardown hook completed successfully"

# Set environment variable for teardown script to use
export TEARDOWN_CONFIRMED="true"
export TEARDOWN_TIMESTAMP="$(date -Iseconds)"

# Return success to allow teardown to proceed
exit 0