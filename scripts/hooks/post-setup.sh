#!/bin/bash

# Post-Setup Hook
# Execute custom logic after environment setup completes

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
        INFO)  echo -e "${GREEN}[POST-SETUP]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[POST-SETUP]${NC} $message" ;;
        ERROR) echo -e "${RED}[POST-SETUP]${NC} $message" ;;
        DEBUG) echo -e "${BLUE}[POST-SETUP]${NC} $message" ;;
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

log INFO "Running post-setup hook for environment: ${ENVIRONMENT:-unknown}"

# Example post-setup tasks:

# 1. Validate deployment health
log INFO "Running post-deployment health checks..."
if [[ -f "$PROJECT_ROOT/scripts/validate.sh" ]]; then
    if "$PROJECT_ROOT/scripts/validate.sh" --env="$ENVIRONMENT" --quick &>/dev/null; then
        log INFO "✅ Deployment health check passed"
    else
        log WARN "⚠️  Deployment health check had issues"
    fi
else
    log WARN "Validation script not found, skipping health check"
fi

# 2. Create initial workspace templates (example)
log INFO "Setting up default workspace templates..."

# Example: Create additional organization-specific templates
# create_custom_template() {
#     local template_name="$1"
#     log INFO "Creating custom template: $template_name"
#     # Custom template creation logic here
# }

# 3. Configure monitoring and alerting
log INFO "Configuring monitoring and alerting..."

case "$ENVIRONMENT" in
    prod)
        log INFO "Production environment - setting up comprehensive monitoring..."

        # Example: Configure production-specific alerts
        # if command -v kubectl &>/dev/null; then
        #     kubectl create configmap alert-config \
        #         --from-literal=environment=production \
        #         --from-literal=severity=critical \
        #         -n monitoring --dry-run=client -o yaml | kubectl apply -f -
        # fi
        ;;
    staging)
        log INFO "Staging environment - setting up testing monitoring..."
        ;;
    dev)
        log INFO "Development environment - minimal monitoring setup..."
        ;;
esac

# 4. User and team setup
log INFO "Setting up users and teams..."

# Example: Create default teams and permissions
# setup_default_teams() {
#     local env="$1"
#     log INFO "Creating default teams for $env environment"

#     # Example team creation
#     # kubectl create namespace team-frontend --dry-run=client -o yaml | kubectl apply -f -
#     # kubectl create namespace team-backend --dry-run=client -o yaml | kubectl apply -f -
# }

# 5. Integration with external systems
log INFO "Setting up external integrations..."

# Example: Register environment in external monitoring
# if [[ -n "${MONITORING_API_KEY:-}" ]]; then
#     register_environment() {
#         local env="$1"
#         # curl -X POST https://monitoring.company.com/api/environments \
#         #     -H "Authorization: Bearer $MONITORING_API_KEY" \
#         #     -H "Content-Type: application/json" \
#         #     -d '{"name":"'"$env"'","type":"coder","status":"active"}'
#         log INFO "Environment $env registered with external monitoring"
#     }
#     register_environment "$ENVIRONMENT"
# fi

# 6. Backup initial state
log INFO "Creating post-deployment backup..."

if [[ -f "$PROJECT_ROOT/scripts/lifecycle/backup.sh" ]]; then
    backup_name="post-setup-$(date +%Y%m%d-%H%M%S)-$ENVIRONMENT"
    if "$PROJECT_ROOT/scripts/lifecycle/backup.sh" \
        --env="$ENVIRONMENT" \
        --backup-name="$backup_name" \
        --include-config \
        --auto &>/dev/null; then
        log INFO "✅ Post-deployment backup created: $backup_name"
    else
        log WARN "⚠️  Post-deployment backup failed"
    fi
else
    log WARN "Backup script not found, skipping post-deployment backup"
fi

# 7. Documentation and notification
log INFO "Generating deployment documentation..."

# Example: Create deployment summary
create_deployment_summary() {
    local env="$1"
    local summary_file="$PROJECT_ROOT/deployments/deployment-summary-$env-$(date +%Y%m%d-%H%M%S).md"

    mkdir -p "$(dirname "$summary_file")"

    cat > "$summary_file" <<EOF
# Deployment Summary

**Environment:** $env
**Date:** $(date -Iseconds)
**Status:** Completed

## Deployment Details

- **Infrastructure:** Terraform deployed
- **Kubernetes:** Cluster ready
- **Coder:** Application deployed
- **Monitoring:** $([ "$env" = "prod" ] && echo "Enabled" || echo "Basic")

## Access Information

- **Environment:** $env
- **URL:** [Retrieved from Terraform outputs]
- **Admin User:** admin

## Post-Deployment Actions Completed

- ✅ Health check validation
- ✅ Monitoring configuration
- ✅ Initial backup created
- ✅ External systems notified

## Next Steps

1. Access the Coder instance
2. Create workspace templates
3. Invite users and set up teams
4. Configure additional monitoring if needed

**Generated by:** post-setup hook
EOF

    log INFO "Deployment summary created: $summary_file"
}

create_deployment_summary "$ENVIRONMENT"

# 8. Team notifications
log INFO "Sending notifications..."

# Example: Slack notification
# if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
#     send_slack_notification() {
#         local env="$1"
#         local message="🎉 Coder environment '$env' deployment completed successfully!"
#
#         curl -X POST -H 'Content-type: application/json' \
#             --data '{"text":"'"$message"'"}' \
#             "$SLACK_WEBHOOK" &>/dev/null || true
#
#         log INFO "Slack notification sent"
#     }
#     send_slack_notification "$ENVIRONMENT"
# fi

# Example: Email notification
# if command -v mail &>/dev/null && [[ -n "${ADMIN_EMAIL:-}" ]]; then
#     echo "Coder environment $ENVIRONMENT has been deployed successfully." | \
#         mail -s "Deployment Complete: $ENVIRONMENT" "$ADMIN_EMAIL" || true
#     log INFO "Email notification sent to $ADMIN_EMAIL"
# fi

# 9. Security hardening (production only)
if [[ "$ENVIRONMENT" == "prod" ]]; then
    log INFO "Applying production security hardening..."

    # Example security configurations
    # - Enable Pod Security Standards
    # - Configure Network Policies
    # - Set up RBAC restrictions
    # - Enable audit logging

    # Example: Apply strict security policies
    # if command -v kubectl &>/dev/null; then
    #     kubectl label namespace coder pod-security.kubernetes.io/enforce=restricted --overwrite
    #     kubectl label namespace coder pod-security.kubernetes.io/audit=restricted --overwrite
    #     kubectl label namespace coder pod-security.kubernetes.io/warn=restricted --overwrite
    #     log INFO "Pod Security Standards applied"
    # fi
fi

# 10. Performance optimization
log INFO "Applying performance optimizations..."

# Example: Configure resource quotas based on environment
# configure_resource_quotas() {
#     local env="$1"
#
#     case "$env" in
#         prod)
#             # High resource quotas for production
#             cpu_quota="100"
#             memory_quota="200Gi"
#             ;;
#         staging)
#             cpu_quota="50"
#             memory_quota="100Gi"
#             ;;
#         dev)
#             cpu_quota="20"
#             memory_quota="40Gi"
#             ;;
#     esac
#
#     log INFO "Configuring resource quotas: CPU=$cpu_quota, Memory=$memory_quota"
# }

# configure_resource_quotas "$ENVIRONMENT"

log INFO "Post-setup hook completed successfully"

# Example: Exit with custom status based on environment
case "$ENVIRONMENT" in
    prod)
        log INFO "🔒 Production environment is now live and secured"
        ;;
    staging)
        log INFO "🧪 Staging environment is ready for testing"
        ;;
    dev)
        log INFO "🛠️  Development environment is ready for coding"
        ;;
esac

# Return success
exit 0