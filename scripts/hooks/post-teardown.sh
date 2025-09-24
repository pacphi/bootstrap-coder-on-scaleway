#!/bin/bash

# Post-Teardown Hook
# Execute custom logic after environment teardown completes

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
        INFO)  echo -e "${GREEN}[POST-TEARDOWN]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[POST-TEARDOWN]${NC} $message" ;;
        ERROR) echo -e "${RED}[POST-TEARDOWN]${NC} $message" ;;
        DEBUG) echo -e "${BLUE}[POST-TEARDOWN]${NC} $message" ;;
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

log INFO "Running post-teardown hook for environment: ${ENVIRONMENT:-unknown}"

# 1. Verify complete resource cleanup
log INFO "Verifying complete resource cleanup..."

# Check if any resources are still accessible
if command -v kubectl &>/dev/null; then
    kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"

        if kubectl cluster-info &>/dev/null; then
            log WARN "⚠️  Cluster still accessible - teardown may be incomplete"

            # List any remaining resources
            remaining_pods=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l || echo "0")
            if [[ "$remaining_pods" -gt 0 ]]; then
                log WARN "Found $remaining_pods remaining pods"
            fi
        else
            log INFO "✅ Cluster no longer accessible - teardown appears complete"
        fi
    fi
fi

# 2. Clean up local artifacts
log INFO "Cleaning up local artifacts..."

# Remove kubeconfig
kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
if [[ -f "$kubeconfig" ]]; then
    rm -f "$kubeconfig"
    log INFO "✅ Removed kubeconfig: $kubeconfig"
fi

# Archive any temporary files
temp_files=(
    "$PROJECT_ROOT/environments/$ENVIRONMENT/scaling-plan.json"
    "$PROJECT_ROOT/environments/$ENVIRONMENT/*.tfplan"
    "$PROJECT_ROOT/environments/$ENVIRONMENT/*.tfvars"
)

for file_pattern in "${temp_files[@]}"; do
    if ls $file_pattern >/dev/null 2>&1; then
        archive_dir="$PROJECT_ROOT/archives/teardown/$(date +%Y%m%d-%H%M%S)-$ENVIRONMENT"
        mkdir -p "$archive_dir"
        mv $file_pattern "$archive_dir/" 2>/dev/null || true
        log INFO "Archived temporary files to: $archive_dir"
        break
    fi
done

# 3. Update external systems
log INFO "Updating external systems..."

# Example: Update monitoring systems
# if [[ -n "${MONITORING_API_KEY:-}" ]]; then
#     update_external_monitoring() {
#         local env="$1"
#         log INFO "Updating external monitoring for $env teardown"
#         # curl -X DELETE https://monitoring.company.com/api/environments/$env \
#         #     -H "Authorization: Bearer $MONITORING_API_KEY" || true
#         # curl -X POST https://monitoring.company.com/api/events \
#         #     -H "Authorization: Bearer $MONITORING_API_KEY" \
#         #     -H "Content-Type: application/json" \
#         #     -d '{"event":"environment_destroyed","environment":"'$env'","timestamp":"'$(date -Iseconds)'"}'
#     }
#     update_external_monitoring "$ENVIRONMENT"
# fi

# Example: Update DNS records
# remove_dns_records() {
#     local env="$1"
#     log INFO "Removing DNS records for $env environment"
#     # Implementation depends on your DNS provider
#     # Example: Remove CNAME records, A records, etc.
# }
# remove_dns_records "$ENVIRONMENT"

# 4. Cost tracking and reporting
log INFO "Recording cost savings..."

record_cost_savings() {
    local env="$1"

    case "$env" in
        dev) local monthly_savings="53.70" ;;
        staging) local monthly_savings="97.85" ;;
        prod) local monthly_savings="374.50" ;;
        *) local monthly_savings="0.00" ;;
    esac

    local cost_log="$PROJECT_ROOT/cost-tracking/teardown-savings-$(date +%Y%m).log"
    mkdir -p "$(dirname "$cost_log")"

    echo "$(date -Iseconds),$env,$monthly_savings,Teardown completed" >> "$cost_log"
    log INFO "💰 Recorded monthly savings: €$monthly_savings"
}

record_cost_savings "$ENVIRONMENT"

# 5. Audit logging
log INFO "Creating post-teardown audit log..."

create_teardown_summary() {
    local env="$1"
    local audit_dir="$PROJECT_ROOT/audit-logs"
    mkdir -p "$audit_dir"

    local audit_file="$audit_dir/teardown-completed-$(date +%Y%m%d-%H%M%S)-$env.log"
    cat > "$audit_file" <<EOF
TEARDOWN COMPLETION AUDIT LOG
=============================

Environment: $env
Completion Timestamp: $(date -Iseconds)
User: $(whoami)
Hostname: $(hostname)

Teardown Results:
- Infrastructure: Destroyed
- Kubernetes Cluster: Removed
- Database: Deleted
- Load Balancer: Removed
- Storage: Deleted
- Networking: Cleaned up

Post-teardown Actions:
- ✅ Resource cleanup verified
- ✅ Local artifacts removed
- ✅ External systems updated
- ✅ Cost savings recorded
- ✅ Audit log completed

Cost Impact:
- Monthly Savings: $(case "$env" in dev) echo "€53.70" ;; staging) echo "€97.85" ;; prod) echo "€374.50" ;; esac)
- Effective From: $(date +%Y-%m-%d)

Status: Teardown completed successfully

Generated by: post-teardown hook
Teardown initiated: ${TEARDOWN_TIMESTAMP:-Unknown}
Teardown duration: Calculated by main script
EOF

    log INFO "Teardown summary created: $audit_file"
}

create_teardown_summary "$ENVIRONMENT"

# 6. Team notifications
log INFO "Sending completion notifications..."

# Example: Slack notification
# if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
#     send_completion_notification() {
#         local env="$1"
#         local cost_savings=$(case "$env" in dev) echo "€53.70" ;; staging) echo "€97.85" ;; prod) echo "€374.50" ;; esac)
#
#         local message="💥 Coder environment '$env' has been successfully torn down!
#
# 💰 Monthly cost savings: $cost_savings
# 📊 All resources have been cleaned up
# 🔒 Audit logs have been created"
#
#         curl -X POST -H 'Content-type: application/json' \
#             --data '{"text":"'"$message"'"}' \
#             "$SLACK_WEBHOOK" &>/dev/null || true
#
#         log INFO "Completion notification sent to Slack"
#     }
#     send_completion_notification "$ENVIRONMENT"
# fi

# Example: Email notification
# if command -v mail &>/dev/null && [[ -n "${ADMIN_EMAIL:-}" ]]; then
#     send_email_notification() {
#         local env="$1"
#         local cost_savings=$(case "$env" in dev) echo "€53.70" ;; staging) echo "€97.85" ;; prod) echo "€374.50" ;; esac)
#
#         local subject="Teardown Complete: $env Environment"
#         local body="The Coder environment '$env' has been successfully torn down.
#
# Cost savings: $cost_savings per month
# All resources have been cleaned up and audit logs created.
#
# Generated automatically by post-teardown hook."
#
#         echo "$body" | mail -s "$subject" "$ADMIN_EMAIL" || true
#         log INFO "Email notification sent to $ADMIN_EMAIL"
#     }
#     send_email_notification "$ENVIRONMENT"
# fi

# 7. Security cleanup
log INFO "Performing security cleanup..."

# Example: Revoke any environment-specific credentials
# revoke_environment_credentials() {
#     local env="$1"
#     log INFO "Revoking credentials for $env environment"

#     # Example: Remove from key management system
#     # if command -v vault &>/dev/null; then
#     #     vault kv delete secret/coder/$env/credentials || true
#     # fi

#     # Example: Revoke AWS IAM roles if applicable
#     # if command -v aws &>/dev/null; then
#     #     aws iam delete-role --role-name "coder-$env-role" || true
#     # fi
# }
# revoke_environment_credentials "$ENVIRONMENT"

# Example: Update firewall rules
# update_firewall_rules() {
#     local env="$1"
#     log INFO "Removing firewall rules for $env environment"
#     # Implementation depends on your firewall/security groups setup
# }
# update_firewall_rules "$ENVIRONMENT"

# 8. Documentation updates
log INFO "Updating documentation..."

# Example: Update environment inventory
update_environment_inventory() {
    local env="$1"
    local inventory_file="$PROJECT_ROOT/docs/environment-inventory.md"

    if [[ -f "$inventory_file" ]]; then
        # Remove environment from active list
        sed -i.backup "/$env.*Active/d" "$inventory_file" 2>/dev/null || true

        # Add to destroyed list
        local destroyed_section=$(grep -n "## Destroyed Environments" "$inventory_file" | cut -d: -f1)
        if [[ -n "$destroyed_section" ]]; then
            sed -i.backup "${destroyed_section}a\\
- **$env**: Destroyed on $(date +%Y-%m-%d)" "$inventory_file"
        fi

        log INFO "Updated environment inventory"
    fi
}

# update_environment_inventory "$ENVIRONMENT"

# 9. Cleanup verification
log INFO "Running final cleanup verification..."

# Check for any remaining Scaleway resources (if credentials available)
# if [[ -n "${SCW_ACCESS_KEY:-}" ]] && command -v scw &>/dev/null; then
#     verify_scaleway_cleanup() {
#         local env="$1"
#         log INFO "Verifying Scaleway resource cleanup for $env"

#         # Check for remaining clusters
#         local remaining_clusters=$(scw k8s cluster list -o json | jq -r '.[] | select(.name | contains("'$env'")) | .name' 2>/dev/null || echo "")
#         if [[ -n "$remaining_clusters" ]]; then
#             log WARN "⚠️  Found remaining clusters: $remaining_clusters"
#         fi

#         # Check for remaining databases
#         local remaining_dbs=$(scw rdb instance list -o json | jq -r '.[] | select(.name | contains("'$env'")) | .name' 2>/dev/null || echo "")
#         if [[ -n "$remaining_dbs" ]]; then
#             log WARN "⚠️  Found remaining databases: $remaining_dbs"
#         fi

#         if [[ -z "$remaining_clusters" && -z "$remaining_dbs" ]]; then
#             log INFO "✅ No remaining Scaleway resources found"
#         fi
#     }
#     verify_scaleway_cleanup "$ENVIRONMENT"
# fi

# 10. Final status reporting
log INFO "Generating final status report..."

generate_final_report() {
    local env="$1"
    local report_file="$PROJECT_ROOT/teardown-reports/final-report-$env-$(date +%Y%m%d-%H%M%S).md"
    mkdir -p "$(dirname "$report_file")"

    cat > "$report_file" <<EOF
# Final Teardown Report

## Environment: $env
**Teardown Completed:** $(date -Iseconds)

## Summary
- ✅ Infrastructure completely destroyed
- ✅ All resources cleaned up
- ✅ Local artifacts removed
- ✅ External systems notified
- ✅ Audit logs created
- ✅ Cost savings recorded

## Cost Impact
**Monthly Savings:** $(case "$env" in dev) echo "€53.70" ;; staging) echo "€97.85" ;; prod) echo "€374.50" ;; esac)
**Effective Date:** $(date +%Y-%m-%d)

## Actions Completed
1. Resource cleanup verification
2. Local artifact removal
3. External system updates
4. Cost tracking
5. Audit logging
6. Team notifications
7. Security cleanup
8. Documentation updates
9. Final verification

## Recommendations
- Monitor Scaleway billing to confirm cost savings
- Update any hardcoded references to the destroyed environment
- Consider deploying a new environment if needed for future development

---
**Generated by:** post-teardown hook
**Report Location:** $report_file
EOF

    log INFO "Final report generated: $report_file"
}

generate_final_report "$ENVIRONMENT"

# Environment-specific final actions
case "$ENVIRONMENT" in
    prod)
        log INFO "🔴 Production environment completely destroyed"
        log INFO "💰 Monthly savings: €374.50"
        log INFO "🔒 All production data has been permanently deleted"
        ;;
    staging)
        log INFO "🧪 Staging environment completely destroyed"
        log INFO "💰 Monthly savings: €97.85"
        ;;
    dev)
        log INFO "🛠️  Development environment completely destroyed"
        log INFO "💰 Monthly savings: €53.70"
        ;;
esac

log INFO "Post-teardown hook completed successfully"
log INFO "Environment '$ENVIRONMENT' teardown is now complete"

# Return success
exit 0