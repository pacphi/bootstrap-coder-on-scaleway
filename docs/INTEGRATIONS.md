# Integration Guide

This guide explains how to set up and configure external integrations with the Coder deployment system. All integrations are **optional** and activated only when the required environment variables are configured.

## Overview

The hooks framework supports five main integration categories:

1. **[Slack Notifications](#slack-notifications)** - Real-time deployment and status notifications
2. **[JIRA Integration](#jira-integration)** - Automatic ticket creation for environment changes
3. **[External Monitoring](#external-monitoring)** - Registration with monitoring systems
4. **[Compliance Systems](#compliance-systems)** - Automated compliance checks and reporting
5. **[User Notifications](#user-notifications)** - Email and messaging for users

## How Integrations Work

### Optional Activation

- Integrations are **disabled by default**
- Activate by setting required environment variables
- Missing integrations log warnings but **don't fail deployments**
- Each integration can be enabled/disabled independently

### Integration Points

Integrations execute during these lifecycle events:

- **Pre-Setup**: Before environment deployment starts
- **Post-Setup**: After environment deployment completes
- **Pre-Teardown**: Before environment destruction begins
- **Post-Teardown**: After environment destruction completes

## Slack Notifications

Get real-time notifications about deployment events in your Slack channels.

### Setup

1. **Create Slack Webhook**
   - Go to your Slack workspace settings
   - Navigate to **Apps** → **Incoming Webhooks**
   - Create a new webhook for your desired channel
   - Copy the webhook URL

2. **Configure Environment Variable**

   ```bash
   export SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
   ```

3. **Optional: Set Channel-Specific Webhooks**

   ```bash
   # Different webhooks for different environments
   export SLACK_WEBHOOK_DEV="https://hooks.slack.com/services/DEV/WEBHOOK/URL"
   export SLACK_WEBHOOK_STAGING="https://hooks.slack.com/services/STAGING/WEBHOOK/URL"
   export SLACK_WEBHOOK_PROD="https://hooks.slack.com/services/PROD/WEBHOOK/URL"
   ```

### Message Types

**Pre-Setup Messages:**

- 🚀 Deployment starting notifications
- ⚠️ Maintenance window warnings
- 📋 Resource requirement checks

**Post-Setup Messages:**

- ✅ Successful deployment confirmations
- 📊 Deployment summary with URLs and access info
- ⚠️ Health check warnings

**Pre-Teardown Messages:**

- 🛑 Teardown initiation warnings
- 👥 Active user notifications
- 💾 Backup status confirmations

**Post-Teardown Messages:**

- 🗑️ Environment cleanup confirmations
- 💰 Cost savings summaries
- 📋 Audit completion reports

### Testing Slack Integration

```bash
# Test Slack connectivity
curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"🧪 Testing Coder Slack integration"}' \
    "$SLACK_WEBHOOK"

# Test with specific hook
SLACK_WEBHOOK="your-webhook" ./scripts/hooks/pre-setup.sh --env=dev
```

### Customization

```bash
# Custom message formatting in hooks
send_slack_message() {
    local message="$1"
    local color="$2"  # good, warning, danger
    local environment="$3"

    local webhook="${SLACK_WEBHOOK:-}"

    # Use environment-specific webhook if available
    case "$environment" in
        dev) webhook="${SLACK_WEBHOOK_DEV:-$webhook}" ;;
        staging) webhook="${SLACK_WEBHOOK_STAGING:-$webhook}" ;;
        prod) webhook="${SLACK_WEBHOOK_PROD:-$webhook}" ;;
    esac

    if [[ -n "$webhook" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data '{
                "attachments": [{
                    "color": "'"$color"'",
                    "text": "'"$message"'",
                    "fields": [
                        {
                            "title": "Environment",
                            "value": "'"$environment"'",
                            "short": true
                        },
                        {
                            "title": "Timestamp",
                            "value": "'"$(date -Iseconds)"'",
                            "short": true
                        }
                    ]
                }]
            }' \
            "$webhook" &>/dev/null || log WARN "Slack notification failed"
    fi
}
```

## JIRA Integration

Automatically create and update JIRA tickets for environment lifecycle events.

### Setup

1. **Create JIRA API Token**
   - Go to JIRA Settings → Personal Access Tokens
   - Create a new token with appropriate permissions
   - Copy the token for configuration

2. **Configure Environment Variables**

   ```bash
   export JIRA_API_URL="https://your-company.atlassian.net/rest/api/3"
   export JIRA_API_TOKEN="your-api-token"
   export JIRA_PROJECT_KEY="OPS"  # Your project key
   export JIRA_USER_EMAIL="automation@company.com"
   ```

3. **Optional: Environment-Specific Projects**

   ```bash
   export JIRA_PROJECT_DEV="DEV"
   export JIRA_PROJECT_STAGING="STAGE"
   export JIRA_PROJECT_PROD="OPS"
   ```

### Ticket Types

**Setup Events:**

- **Issue Type**: Task
- **Summary**: "Deploy Coder Environment: [ENV]"
- **Description**: Deployment details, template, timeline
- **Labels**: coder-deployment, environment-[env]

**Teardown Events:**

- **Issue Type**: Task
- **Summary**: "Teardown Coder Environment: [ENV]"
- **Description**: Teardown reason, backup status, cost savings
- **Labels**: coder-teardown, environment-[env]

### Testing JIRA Integration

```bash
# Test JIRA connectivity
curl -X GET "$JIRA_API_URL/myself" \
    -H "Authorization: Bearer $JIRA_API_TOKEN" \
    -H "Accept: application/json"

# Test ticket creation
create_jira_ticket "Test Integration" "Testing JIRA integration from Coder deployment system"
```

### Customization

```bash
# Enhanced JIRA ticket creation
create_jira_ticket() {
    local summary="$1"
    local description="$2"
    local environment="$3"
    local issue_type="${4:-Task}"

    if [[ -z "$JIRA_API_URL" || -z "$JIRA_API_TOKEN" ]]; then
        log INFO "JIRA integration not configured, skipping ticket creation"
        return 0
    fi

    # Use environment-specific project if available
    local project_key="$JIRA_PROJECT_KEY"
    case "$environment" in
        dev) project_key="${JIRA_PROJECT_DEV:-$project_key}" ;;
        staging) project_key="${JIRA_PROJECT_STAGING:-$project_key}" ;;
        prod) project_key="${JIRA_PROJECT_PROD:-$project_key}" ;;
    esac

    local response=$(curl -s -X POST "$JIRA_API_URL/issue" \
        -H "Authorization: Bearer $JIRA_API_TOKEN" \
        -H "Content-Type: application/json" \
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
                            "text": "'"$description"'"
                        }]
                    }]
                },
                "issuetype": {"name": "'"$issue_type"'"},
                "labels": ["coder-automation", "environment-'"$environment"'"]
            }
        }')

    local ticket_key=$(echo "$response" | jq -r '.key // empty')
    if [[ -n "$ticket_key" ]]; then
        log INFO "JIRA ticket created: $ticket_key"
        export JIRA_TICKET_KEY="$ticket_key"  # Available for other hooks
    else
        log WARN "JIRA ticket creation failed: $response"
    fi
}
```

## External Monitoring

Register environments with external monitoring and observability platforms.

### Setup

1. **Configure Monitoring System**

   ```bash
   export MONITORING_API_URL="https://monitoring.company.com/api/v1"
   export MONITORING_API_TOKEN="your-monitoring-token"
   export MONITORING_TEAM="platform-team"
   ```

2. **Optional: Multiple Monitoring Systems**

   ```bash
   # Primary monitoring (required)
   export MONITORING_PRIMARY_URL="https://primary-monitoring.com/api"
   export MONITORING_PRIMARY_TOKEN="token1"

   # Secondary monitoring (optional)
   export MONITORING_SECONDARY_URL="https://secondary-monitoring.com/api"
   export MONITORING_SECONDARY_TOKEN="token2"

   # Metrics collection
   export METRICS_ENDPOINT="https://metrics.company.com/push"
   export METRICS_TOKEN="metrics-token"
   ```

### Monitoring Events

**Environment Registration:**

- Environment creation/destruction events
- Resource allocation and scaling events
- Health check status updates
- Cost and usage metrics

**Alert Configuration:**

- Environment-specific alerting rules
- Resource threshold monitoring
- Availability and performance alerts

### Testing Monitoring Integration

```bash
# Test monitoring API connectivity
curl -X GET "$MONITORING_API_URL/health" \
    -H "Authorization: Bearer $MONITORING_API_TOKEN"

# Test environment registration
register_environment "test" "coder" "active"
```

### Customization

```bash
# Advanced monitoring integration
register_environment() {
    local env_name="$1"
    local env_type="${2:-coder}"
    local status="${3:-active}"

    if [[ -z "$MONITORING_API_URL" || -z "$MONITORING_API_TOKEN" ]]; then
        log INFO "Monitoring integration not configured, skipping registration"
        return 0
    fi

    # Primary monitoring system
    register_with_monitoring "$MONITORING_API_URL" "$MONITORING_API_TOKEN" "$env_name" "$env_type" "$status"

    # Secondary monitoring system (if configured)
    if [[ -n "$MONITORING_SECONDARY_URL" && -n "$MONITORING_SECONDARY_TOKEN" ]]; then
        register_with_monitoring "$MONITORING_SECONDARY_URL" "$MONITORING_SECONDARY_TOKEN" "$env_name" "$env_type" "$status"
    fi

    # Configure environment-specific alerts
    case "$env_name" in
        prod)
            configure_production_alerts "$env_name"
            ;;
        staging)
            configure_staging_alerts "$env_name"
            ;;
        dev)
            configure_dev_alerts "$env_name"
            ;;
    esac
}

register_with_monitoring() {
    local api_url="$1"
    local api_token="$2"
    local env_name="$3"
    local env_type="$4"
    local status="$5"

    local response=$(curl -s -X POST "$api_url/environments" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'"$env_name"'",
            "type": "'"$env_type"'",
            "status": "'"$status"'",
            "team": "'"$MONITORING_TEAM"'",
            "metadata": {
                "deployment_time": "'"$(date -Iseconds)"'",
                "automation": "coder-bootstrap",
                "managed": true
            }
        }')

    local success=$(echo "$response" | jq -r '.success // false')
    if [[ "$success" == "true" ]]; then
        log INFO "Environment $env_name registered with monitoring system"
    else
        log WARN "Failed to register $env_name with monitoring: $response"
    fi
}
```

## Compliance Systems

Integrate with compliance and audit systems for automated checks and reporting.

### Setup

1. **Configure Compliance System**

   ```bash
   export COMPLIANCE_API_URL="https://compliance.company.com/api"
   export COMPLIANCE_API_TOKEN="compliance-token"
   export COMPLIANCE_POLICY_SET="kubernetes-baseline"
   ```

2. **Environment-Specific Policies**

   ```bash
   export COMPLIANCE_POLICY_DEV="development-baseline"
   export COMPLIANCE_POLICY_STAGING="staging-enhanced"
   export COMPLIANCE_POLICY_PROD="production-strict"
   ```

### Compliance Checks

**Pre-Deployment:**

- Security policy validation
- Resource allocation compliance
- Network policy requirements
- Data protection compliance

**Post-Deployment:**

- Security configuration audit
- Access control validation
- Encryption verification
- Compliance reporting

### Testing Compliance Integration

```bash
# Test compliance API
curl -X GET "$COMPLIANCE_API_URL/health" \
    -H "Authorization: Bearer $COMPLIANCE_API_TOKEN"

# Run compliance check
run_compliance_check "dev" "pre-deployment"
```

### Customization

```bash
# Comprehensive compliance integration
run_compliance_check() {
    local environment="$1"
    local check_type="$2"  # pre-deployment, post-deployment, teardown

    if [[ -z "$COMPLIANCE_API_URL" || -z "$COMPLIANCE_API_TOKEN" ]]; then
        log INFO "Compliance integration not configured, skipping checks"
        return 0
    fi

    # Select policy set based on environment
    local policy_set="$COMPLIANCE_POLICY_SET"
    case "$environment" in
        dev) policy_set="${COMPLIANCE_POLICY_DEV:-$policy_set}" ;;
        staging) policy_set="${COMPLIANCE_POLICY_STAGING:-$policy_set}" ;;
        prod) policy_set="${COMPLIANCE_POLICY_PROD:-$policy_set}" ;;
    esac

    log INFO "Running $check_type compliance check for $environment (policy: $policy_set)"

    local response=$(curl -s -X POST "$COMPLIANCE_API_URL/checks" \
        -H "Authorization: Bearer $COMPLIANCE_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "environment": "'"$environment"'",
            "check_type": "'"$check_type"'",
            "policy_set": "'"$policy_set"'",
            "timestamp": "'"$(date -Iseconds)"'",
            "metadata": {
                "automation": "coder-bootstrap",
                "kubernetes_version": "'$(kubectl version --short --client | grep "Client Version" | cut -d" " -f3)'",
                "environment_type": "'"$environment"'"
            }
        }')

    local check_id=$(echo "$response" | jq -r '.check_id // empty')
    local status=$(echo "$response" | jq -r '.status // "unknown"')

    if [[ -n "$check_id" ]]; then
        log INFO "Compliance check initiated: $check_id (status: $status)"
        export COMPLIANCE_CHECK_ID="$check_id"

        # Wait for check completion if required
        if [[ "$environment" == "prod" && "$check_type" == "pre-deployment" ]]; then
            wait_for_compliance_check "$check_id"
        fi
    else
        log WARN "Compliance check failed to initiate: $response"

        # Block production deployments on compliance failure
        if [[ "$environment" == "prod" && "$check_type" == "pre-deployment" ]]; then
            log ERROR "Production deployment blocked due to compliance check failure"
            exit 1
        fi
    fi
}
```

## User Notifications

Send notifications directly to users and administrators about environment events.

### Setup

1. **Configure Email Settings**

   ```bash
   export SMTP_HOST="smtp.company.com"
   export SMTP_PORT="587"
   export SMTP_USER="automation@company.com"
   export SMTP_PASSWORD="smtp-password"
   export ADMIN_EMAIL="admins@company.com"
   ```

2. **Configure User Lists**

   ```bash
   # Environment-specific user lists
   export DEV_USERS="dev-team@company.com,qa-team@company.com"
   export STAGING_USERS="staging-users@company.com,product-team@company.com"
   export PROD_USERS="all-users@company.com,management@company.com"
   ```

### Notification Types

**Pre-Setup:**

- Deployment initiation notices
- Maintenance window alerts
- Resource impact notifications

**Post-Setup:**

- Environment ready notifications
- Access information delivery
- Getting started guides

**Pre-Teardown:**

- Shutdown warnings with timelines
- Data backup reminders
- Alternative environment suggestions

**Post-Teardown:**

- Environment removal confirmations
- Data archival status
- Cost savings reports

### Testing User Notifications

```bash
# Test email functionality
echo "Test email from Coder automation" | mail -s "Test Email" "$ADMIN_EMAIL"

# Test user notification system
notify_users "dev" "deployment-complete" "Your development environment is ready!"
```

### Customization

```bash
# Comprehensive user notification system
notify_users() {
    local environment="$1"
    local event_type="$2"
    local message="$3"
    local urgent="${4:-false}"

    # Get user list for environment
    local user_list=""
    case "$environment" in
        dev) user_list="$DEV_USERS" ;;
        staging) user_list="$STAGING_USERS" ;;
        prod) user_list="$PROD_USERS" ;;
    esac

    # Always notify admins
    user_list="${user_list},${ADMIN_EMAIL}"

    if [[ -z "$user_list" ]]; then
        log INFO "No users configured for $environment notifications"
        return 0
    fi

    # Send email notifications
    if command -v mail &>/dev/null && [[ -n "$SMTP_HOST" ]]; then
        send_email_notifications "$user_list" "$environment" "$event_type" "$message" "$urgent"
    fi

    # Send Slack direct messages (if configured)
    if [[ -n "$SLACK_BOT_TOKEN" ]]; then
        send_slack_dms "$user_list" "$environment" "$event_type" "$message"
    fi

    # Send SMS for urgent production notifications
    if [[ "$urgent" == "true" && "$environment" == "prod" && -n "$SMS_API_TOKEN" ]]; then
        send_sms_notifications "$user_list" "$message"
    fi
}

send_email_notifications() {
    local user_list="$1"
    local environment="$2"
    local event_type="$3"
    local message="$4"
    local urgent="$5"

    local subject="[Coder ${environment^^}]"
    case "$event_type" in
        deployment-starting) subject="$subject Deployment Starting" ;;
        deployment-complete) subject="$subject Environment Ready" ;;
        teardown-warning) subject="$subject Environment Shutdown Warning" ;;
        teardown-complete) subject="$subject Environment Removed" ;;
    esac

    if [[ "$urgent" == "true" ]]; then
        subject="[URGENT] $subject"
    fi

    # Create formatted email body
    local email_body=$(cat <<EOF
$message

Environment: $environment
Event: $event_type
Timestamp: $(date -Iseconds)

---
This is an automated message from the Coder deployment system.
For support, contact: $ADMIN_EMAIL
EOF
)

    # Send to all users in the list
    IFS=',' read -ra USERS <<< "$user_list"
    for user in "${USERS[@]}"; do
        if [[ -n "$user" ]]; then
            echo "$email_body" | mail -s "$subject" "$user" &>/dev/null || \
                log WARN "Failed to send email to $user"
        fi
    done

    log INFO "Email notifications sent for $event_type in $environment"
}
```

## Environment Variables Reference

### Required for Each Integration

**Slack:**

```bash
export SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

**JIRA:**

```bash
export JIRA_API_URL="https://your-company.atlassian.net/rest/api/3"
export JIRA_API_TOKEN="your-jira-token"
export JIRA_PROJECT_KEY="OPS"
```

**Monitoring:**

```bash
export MONITORING_API_URL="https://monitoring.company.com/api/v1"
export MONITORING_API_TOKEN="your-monitoring-token"
```

**Compliance:**

```bash
export COMPLIANCE_API_URL="https://compliance.company.com/api"
export COMPLIANCE_API_TOKEN="your-compliance-token"
```

**User Notifications:**

```bash
export ADMIN_EMAIL="admin@company.com"
export SMTP_HOST="smtp.company.com"
export SMTP_USER="automation@company.com"
export SMTP_PASSWORD="smtp-password"
```

### Optional Environment-Specific Variables

```bash
# Environment-specific Slack webhooks
export SLACK_WEBHOOK_DEV="dev-channel-webhook"
export SLACK_WEBHOOK_STAGING="staging-channel-webhook"
export SLACK_WEBHOOK_PROD="prod-channel-webhook"

# Environment-specific JIRA projects
export JIRA_PROJECT_DEV="DEV"
export JIRA_PROJECT_STAGING="STAGE"
export JIRA_PROJECT_PROD="OPS"

# Environment-specific user lists
export DEV_USERS="dev-team@company.com"
export STAGING_USERS="qa-team@company.com,product@company.com"
export PROD_USERS="all-users@company.com"

# Environment-specific compliance policies
export COMPLIANCE_POLICY_DEV="development-baseline"
export COMPLIANCE_POLICY_STAGING="staging-enhanced"
export COMPLIANCE_POLICY_PROD="production-strict"
```

## Integration Testing

### Test Individual Integrations

```bash
# Test Slack integration
SLACK_WEBHOOK="your-webhook" ./scripts/hooks/pre-setup.sh --env=dev

# Test JIRA integration
JIRA_API_URL="your-url" JIRA_API_TOKEN="your-token" \
  ./scripts/hooks/post-setup.sh --env=dev

# Test monitoring integration
MONITORING_API_URL="your-url" MONITORING_API_TOKEN="your-token" \
  ./scripts/hooks/post-setup.sh --env=dev
```

### Test All Integrations

```bash
# Set all integration variables and test
export SLACK_WEBHOOK="your-slack-webhook"
export JIRA_API_URL="your-jira-url"
export JIRA_API_TOKEN="your-jira-token"
export MONITORING_API_URL="your-monitoring-url"
export MONITORING_API_TOKEN="your-monitoring-token"

# Run full integration test
./scripts/test-runner.sh --suite=integrations
```

### Integration Health Checks

```bash
# Check integration connectivity
./scripts/validate.sh --env=dev --check-integrations

# Validate integration configuration
./scripts/validate.sh --integrations-only
```

## Troubleshooting

### Common Issues

**Integration Not Activating:**

- Verify environment variables are set correctly
- Check variable names match exactly (case-sensitive)
- Ensure no trailing spaces in URLs or tokens

**API Connectivity Issues:**

- Test API endpoints manually with curl
- Verify network connectivity and firewall rules
- Check API token permissions and expiration

**Message Formatting Problems:**

- Validate JSON syntax in API calls
- Check character encoding for special characters
- Verify API version compatibility

### Debug Mode

Enable debug logging for integrations:

```bash
# Enable integration debugging
export INTEGRATION_DEBUG="true"

# Enable verbose curl output
export CURL_VERBOSE="true"

# Run with debug output
DEBUG=1 ./scripts/hooks/post-setup.sh --env=dev
```

### Log Locations

**Integration Logs:**

- Setup logs: `logs/setup/*-setup.log`
- Teardown logs: `logs/teardown/*-teardown.log`
- Integration debug: `logs/integrations/integration-debug.log`

**Manual Testing:**

```bash
# Test API connectivity
curl -v "$MONITORING_API_URL/health" \
    -H "Authorization: Bearer $MONITORING_API_TOKEN"

# Test Slack webhook
curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"Test message"}' \
    "$SLACK_WEBHOOK"
```

## Security Considerations

### Credential Management

- Store sensitive tokens in secure credential management systems
- Use environment-specific credentials
- Rotate tokens regularly
- Never commit credentials to version control

### Network Security

- Use HTTPS for all API communications
- Implement proper certificate validation
- Configure network firewalls appropriately
- Use IP allowlisting where possible

### Access Control

- Use least-privilege API tokens
- Implement proper authentication for webhooks
- Monitor integration access logs
- Set up alerting for failed authentication attempts

## Best Practices

### Configuration Management

1. Use `.env` files for local development
2. Use secure secret management for production
3. Document all required variables
4. Implement configuration validation

### Error Handling

1. Implement graceful degradation for failed integrations
2. Use retry logic with exponential backoff
3. Log integration failures appropriately
4. Don't fail deployments on integration issues

### Testing

1. Test integrations in development first
2. Implement integration health checks
3. Monitor integration performance
4. Set up alerting for integration failures

### Monitoring

1. Track integration success/failure rates
2. Monitor integration response times
3. Set up alerts for integration outages
4. Implement integration status dashboards

---

**Next Steps:**

1. Choose integrations relevant to your organization
2. Configure required environment variables
3. Test integrations in development environment
4. Gradually enable integrations in staging and production
5. Monitor integration health and performance

For additional help, see the [main documentation](../README.md) or [create an issue](../../issues).
