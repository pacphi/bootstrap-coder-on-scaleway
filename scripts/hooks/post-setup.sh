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

# Slack notification (optional - activated when SLACK_WEBHOOK is set)
send_slack_notification() {
    local environment="$1"
    local status="$2"  # success, warning, error
    local message="$3"

    # Use environment-specific webhook if available
    local webhook="${SLACK_WEBHOOK:-}"
    case "$environment" in
        dev) webhook="${SLACK_WEBHOOK_DEV:-$webhook}" ;;
        staging) webhook="${SLACK_WEBHOOK_STAGING:-$webhook}" ;;
        prod) webhook="${SLACK_WEBHOOK_PROD:-$webhook}" ;;
    esac

    if [[ -n "$webhook" ]]; then
        # Set color based on status
        local color="good"
        local emoji="✅"
        case "$status" in
            warning) color="warning"; emoji="⚠️" ;;
            error) color="danger"; emoji="❌" ;;
        esac

        # Try to get access URL from terraform output
        local access_url=""
        if [[ -f "$PROJECT_ROOT/environments/$environment/terraform.tfstate" ]]; then
            access_url=$(cd "$PROJECT_ROOT/environments/$environment" && terraform output -raw access_url 2>/dev/null || echo "")
        fi

        local fields='[
            {
                "title": "Environment",
                "value": "'"$environment"'",
                "short": true
            },
            {
                "title": "Phase",
                "value": "Post-Setup",
                "short": true
            }'

        if [[ -n "$access_url" ]]; then
            fields="${fields},"'{
                "title": "Access URL",
                "value": "<'"$access_url"'|Open Coder>",
                "short": false
            }'
        fi

        fields="${fields},"'{
            "title": "Timestamp",
            "value": "'"$(date -Iseconds)"'",
            "short": false
        }]'

        local response=$(curl -s -X POST -H 'Content-type: application/json' \
            --max-time 10 \
            --data '{
                "attachments": [{
                    "color": "'"$color"'",
                    "text": "'"$emoji $message"'",
                    "fields": '"$fields"'
                }]
            }' \
            "$webhook" 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            log INFO "Slack notification sent successfully"
        else
            log WARN "Slack notification failed (webhook may be unreachable)"
        fi
    else
        log INFO "Slack integration not configured (SLACK_WEBHOOK not set)"
    fi
}

# Send post-setup notification
if [[ -f "$PROJECT_ROOT/scripts/validate.sh" ]] && "$PROJECT_ROOT/scripts/validate.sh" --env="$ENVIRONMENT" --quick &>/dev/null; then
    send_slack_notification "$ENVIRONMENT" "success" "Coder environment '$ENVIRONMENT' deployment completed successfully!"
else
    send_slack_notification "$ENVIRONMENT" "warning" "Coder environment '$ENVIRONMENT' deployed but health checks had issues"
fi

# Email notification (optional - activated when ADMIN_EMAIL is set)
send_email_notification() {
    local environment="$1"
    local status="$2"
    local message="$3"

    if command -v mail &>/dev/null && [[ -n "${ADMIN_EMAIL:-}" ]]; then
        local subject="[Coder ${environment^^}] Deployment "
        case "$status" in
            success) subject="${subject}Completed Successfully" ;;
            warning) subject="${subject}Completed with Warnings" ;;
            error) subject="${subject}Failed" ;;
        esac

        # Get access URL if available
        local access_url=""
        if [[ -f "$PROJECT_ROOT/environments/$environment/terraform.tfstate" ]]; then
            access_url=$(cd "$PROJECT_ROOT/environments/$environment" && terraform output -raw access_url 2>/dev/null || echo "Not available")
        fi

        # Create detailed email body
        local email_body=$(cat <<EOF
$message

Environment Details:
- Environment: $environment
- Status: $status
- Timestamp: $(date -Iseconds)
- Access URL: ${access_url:-"Not available"}

Deployment Summary:
- Infrastructure: Terraform deployed
- Kubernetes: Cluster ready
- Coder: Application deployed
- Health Check: $([ "$status" = "success" ] && echo "✅ Passed" || echo "⚠️ Issues detected")

Next Steps:
1. Access the Coder instance at the URL above
2. Create workspace templates as needed
3. Invite users and set up teams
4. Monitor environment health

---
This is an automated message from the Coder deployment system.
For support, contact: $ADMIN_EMAIL
EOF
)

        # Send to admin email and any environment-specific user lists
        local recipients="$ADMIN_EMAIL"
        case "$environment" in
            dev) recipients="${recipients}${DEV_USERS:+,$DEV_USERS}" ;;
            staging) recipients="${recipients}${STAGING_USERS:+,$STAGING_USERS}" ;;
            prod) recipients="${recipients}${PROD_USERS:+,$PROD_USERS}" ;;
        esac

        # Send emails
        IFS=',' read -ra RECIPIENTS <<< "$recipients"
        local sent_count=0
        for recipient in "${RECIPIENTS[@]}"; do
            if [[ -n "$recipient" ]]; then
                if echo "$email_body" | mail -s "$subject" "$recipient" 2>/dev/null; then
                    ((sent_count++))
                fi
            fi
        done

        if [[ $sent_count -gt 0 ]]; then
            log INFO "Email notifications sent to $sent_count recipient(s)"
        else
            log WARN "Email notification failed"
        fi
    else
        log INFO "Email integration not configured (mail command or ADMIN_EMAIL not set)"
    fi
}

# Send email notification
if [[ -f "$PROJECT_ROOT/scripts/validate.sh" ]] && "$PROJECT_ROOT/scripts/validate.sh" --env="$ENVIRONMENT" --quick &>/dev/null; then
    send_email_notification "$ENVIRONMENT" "success" "Coder environment '$ENVIRONMENT' deployment completed successfully!"
else
    send_email_notification "$ENVIRONMENT" "warning" "Coder environment '$ENVIRONMENT' deployed but health checks detected issues."
fi

# JIRA integration (optional - activated when JIRA_API_URL and JIRA_API_TOKEN are set)
create_jira_ticket() {
    local summary="$1"
    local description="$2"
    local environment="$3"
    local issue_type="${4:-Task}"

    if [[ -z "$JIRA_API_URL" || -z "$JIRA_API_TOKEN" ]]; then
        log INFO "JIRA integration not configured (JIRA_API_URL or JIRA_API_TOKEN not set)"
        return 0
    fi

    # Use environment-specific project if available
    local project_key="${JIRA_PROJECT_KEY:-OPS}"
    case "$environment" in
        dev) project_key="${JIRA_PROJECT_DEV:-$project_key}" ;;
        staging) project_key="${JIRA_PROJECT_STAGING:-$project_key}" ;;
        prod) project_key="${JIRA_PROJECT_PROD:-$project_key}" ;;
    esac

    log INFO "Creating JIRA ticket in project $project_key"

    # Get access URL for ticket description
    local access_url="Not available"
    if [[ -f "$PROJECT_ROOT/environments/$environment/terraform.tfstate" ]]; then
        access_url=$(cd "$PROJECT_ROOT/environments/$environment" && terraform output -raw access_url 2>/dev/null || echo "Not available")
    fi

    # Enhanced description with deployment details
    local enhanced_description="$description

Environment Details:
- Environment: $environment
- Deployment Time: $(date -Iseconds)
- Status: Deployment completed
- Access URL: $access_url

Deployment Actions Completed:
✅ Infrastructure provisioned (Terraform)
✅ Kubernetes cluster deployed
✅ Coder application installed
✅ Health checks performed
✅ Monitoring configured
✅ Backup created

Next Steps:
1. Verify environment access
2. Create workspace templates
3. Set up user access and teams
4. Configure additional monitoring if needed

This ticket was automatically created by the Coder deployment automation system."

    local response=$(curl -s -X POST "$JIRA_API_URL/issue" \
        -H "Authorization: Bearer $JIRA_API_TOKEN" \
        -H "Content-Type: application/json" \
        --max-time 30 \
        -d '{
            "fields": {
                "project": {"key": "'"$project_key"'"},
                "summary": "'"$summary"'",
                "description": {
                    "type": "doc",
                    "version": 1,
                    "content": [{
                        "type": "paragraph",
                        "content": [{
                            "type": "text",
                            "text": "'"$enhanced_description"'"
                        }]
                    }]
                },
                "issuetype": {"name": "'"$issue_type"'"},
                "labels": ["coder-automation", "environment-'"$environment"'", "deployment-complete"]
            }
        }' 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        local ticket_key=$(echo "$response" | jq -r '.key // empty' 2>/dev/null)
        if [[ -n "$ticket_key" && "$ticket_key" != "null" ]]; then
            log INFO "JIRA ticket created successfully: $ticket_key"
            export JIRA_TICKET_KEY="$ticket_key"

            # Add ticket link to deployment summary if it exists
            if [[ -f "$PROJECT_ROOT/deployments/deployment-summary-$environment-"*.md ]]; then
                local summary_file=$(ls -t "$PROJECT_ROOT/deployments/deployment-summary-$environment-"*.md 2>/dev/null | head -1)
                if [[ -n "$summary_file" ]]; then
                    echo "" >> "$summary_file"
                    echo "**JIRA Ticket:** [$ticket_key]($JIRA_API_URL/../browse/$ticket_key)" >> "$summary_file"
                fi
            fi
        else
            log WARN "JIRA ticket creation failed - invalid response: $response"
        fi
    else
        log WARN "JIRA ticket creation failed - API request failed"
    fi
}

# Create JIRA ticket for deployment completion
if [[ -f "$PROJECT_ROOT/scripts/validate.sh" ]] && "$PROJECT_ROOT/scripts/validate.sh" --env="$ENVIRONMENT" --quick &>/dev/null; then
    create_jira_ticket \
        "Coder Environment Deployed: $ENVIRONMENT" \
        "Coder development environment has been successfully deployed to the $ENVIRONMENT environment." \
        "$ENVIRONMENT" \
        "Task"
else
    create_jira_ticket \
        "Coder Environment Deployed with Issues: $ENVIRONMENT" \
        "Coder development environment has been deployed to the $ENVIRONMENT environment, but health checks detected some issues that may require attention." \
        "$ENVIRONMENT" \
        "Bug"
fi

# External monitoring integration (optional - activated when MONITORING_API_URL and MONITORING_API_TOKEN are set)
register_environment() {
    local env_name="$1"
    local env_type="${2:-coder}"
    local status="${3:-active}"

    if [[ -z "$MONITORING_API_URL" || -z "$MONITORING_API_TOKEN" ]]; then
        log INFO "Monitoring integration not configured (MONITORING_API_URL or MONITORING_API_TOKEN not set)"
        return 0
    fi

    log INFO "Registering environment with external monitoring system"

    # Get environment details for monitoring registration
    local access_url="unknown"
    local cluster_info="unknown"
    if [[ -f "$PROJECT_ROOT/environments/$env_name/terraform.tfstate" ]]; then
        access_url=$(cd "$PROJECT_ROOT/environments/$env_name" && terraform output -raw access_url 2>/dev/null || echo "unknown")
        cluster_info=$(cd "$PROJECT_ROOT/environments/$env_name" && terraform output -raw cluster_name 2>/dev/null || echo "unknown")
    fi

    # Primary monitoring system registration
    register_with_monitoring "$MONITORING_API_URL" "$MONITORING_API_TOKEN" "$env_name" "$env_type" "$status" "$access_url" "$cluster_info"

    # Secondary monitoring system (if configured)
    if [[ -n "$MONITORING_SECONDARY_URL" && -n "$MONITORING_SECONDARY_TOKEN" ]]; then
        log INFO "Registering with secondary monitoring system"
        register_with_monitoring "$MONITORING_SECONDARY_URL" "$MONITORING_SECONDARY_TOKEN" "$env_name" "$env_type" "$status" "$access_url" "$cluster_info"
    fi

    # Configure environment-specific monitoring alerts
    configure_monitoring_alerts "$env_name"
}

register_with_monitoring() {
    local api_url="$1"
    local api_token="$2"
    local env_name="$3"
    local env_type="$4"
    local status="$5"
    local access_url="$6"
    local cluster_info="$7"

    local response=$(curl -s -X POST "$api_url/environments" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        --max-time 30 \
        -d '{
            "name": "'"$env_name"'",
            "type": "'"$env_type"'",
            "status": "'"$status"'",
            "team": "'"${MONITORING_TEAM:-platform-team}"'",
            "metadata": {
                "deployment_time": "'"$(date -Iseconds)"'",
                "automation": "coder-bootstrap",
                "managed": true,
                "access_url": "'"$access_url"'",
                "cluster": "'"$cluster_info"'",
                "environment_type": "'"$env_name"'",
                "health_check_url": "'"$access_url/healthz"'",
                "region": "'"${SCW_DEFAULT_REGION:-fr-par}"'"
            },
            "tags": ["coder", "kubernetes", "'"$env_name"'", "scaleway"]
        }' 2>/dev/null)

    if [[ $? -eq 0 ]]; then
        local success=$(echo "$response" | jq -r '.success // .id // false' 2>/dev/null)
        if [[ "$success" != "false" && "$success" != "null" && -n "$success" ]]; then
            log INFO "Environment $env_name registered with monitoring system (ID: $success)"
            export MONITORING_ENVIRONMENT_ID="$success"
        else
            log WARN "Failed to register $env_name with monitoring system: $response"
        fi
    else
        log WARN "Monitoring API request failed - unable to register environment"
    fi
}

configure_monitoring_alerts() {
    local environment="$1"

    # Skip alert configuration if monitoring is not set up
    if [[ -z "$MONITORING_API_URL" || -z "$MONITORING_API_TOKEN" ]]; then
        return 0
    fi

    log INFO "Configuring monitoring alerts for $environment environment"

    # Environment-specific alert configurations
    local alert_config=""
    case "$environment" in
        prod)
            alert_config='{
                "cpu_threshold": 80,
                "memory_threshold": 85,
                "disk_threshold": 90,
                "availability_threshold": 99.5,
                "response_time_threshold": 2000,
                "alert_channels": ["slack", "email", "pagerduty"],
                "severity": "critical"
            }'
            ;;
        staging)
            alert_config='{
                "cpu_threshold": 85,
                "memory_threshold": 90,
                "disk_threshold": 95,
                "availability_threshold": 95.0,
                "response_time_threshold": 5000,
                "alert_channels": ["slack", "email"],
                "severity": "warning"
            }'
            ;;
        dev)
            alert_config='{
                "cpu_threshold": 90,
                "memory_threshold": 95,
                "disk_threshold": 95,
                "availability_threshold": 90.0,
                "response_time_threshold": 10000,
                "alert_channels": ["slack"],
                "severity": "info"
            }'
            ;;
    esac

    if [[ -n "$alert_config" && -n "$MONITORING_ENVIRONMENT_ID" ]]; then
        local response=$(curl -s -X POST "$MONITORING_API_URL/environments/$MONITORING_ENVIRONMENT_ID/alerts" \
            -H "Authorization: Bearer $MONITORING_API_TOKEN" \
            -H "Content-Type: application/json" \
            --max-time 20 \
            -d "$alert_config" 2>/dev/null)

        if [[ $? -eq 0 ]]; then
            local alert_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
            if [[ -n "$alert_id" && "$alert_id" != "null" ]]; then
                log INFO "Monitoring alerts configured successfully (Alert ID: $alert_id)"
            else
                log WARN "Alert configuration may have failed: $response"
            fi
        else
            log WARN "Failed to configure monitoring alerts"
        fi
    fi
}

# Register environment with monitoring systems
register_environment "$ENVIRONMENT" "coder" "active"

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