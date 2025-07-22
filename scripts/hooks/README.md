# Hooks Framework

The hooks framework provides extensible points for custom logic during environment lifecycle operations. Hooks allow you to integrate custom scripts, notifications, compliance checks, and other organization-specific requirements.

## Available Hooks

### Setup Hooks
- **`pre-setup.sh`** - Executed before environment setup begins
- **`post-setup.sh`** - Executed after environment setup completes

### Teardown Hooks
- **`pre-teardown.sh`** - Executed before environment teardown begins
- **`post-teardown.sh`** - Executed after environment teardown completes

## Hook Execution

Hooks are automatically executed by the main lifecycle scripts:

```bash
# Setup process
./scripts/lifecycle/setup.sh --env=prod
# → Executes pre-setup.sh
# → Runs main setup logic
# → Executes post-setup.sh

# Teardown process
./scripts/lifecycle/teardown.sh --env=prod --confirm
# → Executes pre-teardown.sh
# → Runs main teardown logic
# → Executes post-teardown.sh
```

## Hook Parameters

All hooks receive the following parameters:
- `--env=ENVIRONMENT` - Target environment (dev|staging|prod)

Additional context is available via environment variables set by the main scripts.

## Customization Examples

### Pre-Setup Hook Customizations

```bash
# Check system requirements
check_system_resources() {
    local memory_gb=$(free -g | awk 'NR==2{print $2}')
    if [[ "$memory_gb" -lt 16 ]]; then
        log ERROR "Insufficient memory for production deployment"
        exit 1
    fi
}

# Validate maintenance windows
check_maintenance_window() {
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        local current_hour=$(date +%H)
        if [[ "$current_hour" -ge 9 && "$current_hour" -le 17 ]]; then
            log ERROR "Production deployments not allowed during business hours"
            exit 1
        fi
    fi
}

# External system integration
notify_deployment_start() {
    curl -X POST "$SLACK_WEBHOOK" \
        -H 'Content-type: application/json' \
        -d '{"text":"🚀 Starting '"$ENVIRONMENT"' deployment"}'
}
```

### Post-Setup Hook Customizations

```bash
# Configure monitoring
setup_custom_monitoring() {
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        # Configure production alerts
        kubectl apply -f production-alerts.yaml
    fi
}

# User provisioning
create_default_users() {
    local users=("alice" "bob" "charlie")
    for user in "${users[@]}"; do
        # Create user workspaces
        coder users create "$user" --email="$user@company.com"
    done
}

# Integration testing
run_smoke_tests() {
    local coder_url=$(terraform output -raw access_url)
    curl -f "$coder_url/healthz" || {
        log ERROR "Health check failed"
        exit 1
    }
}
```

### Pre-Teardown Hook Customizations

```bash
# Data backup verification
verify_backups() {
    local backup_age=$(find backups/ -name "*$ENVIRONMENT*" -mtime -1 | wc -l)
    if [[ "$backup_age" -eq 0 ]]; then
        log ERROR "No recent backup found - teardown blocked"
        exit 1
    fi
}

# User notification
notify_active_users() {
    local active_workspaces=$(kubectl get pods -n coder | grep -c workspace)
    if [[ "$active_workspaces" -gt 0 ]]; then
        # Send notifications to active users
        send_user_notifications "$ENVIRONMENT" "$active_workspaces"
    fi
}

# Compliance checks
compliance_teardown_check() {
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        # Check if compliance approval exists
        if [[ ! -f "/tmp/compliance-approved-$ENVIRONMENT" ]]; then
            log ERROR "Production teardown requires compliance approval"
            exit 1
        fi
    fi
}
```

### Post-Teardown Hook Customizations

```bash
# Cost tracking
record_cost_savings() {
    local monthly_cost=$(calculate_monthly_cost "$ENVIRONMENT")
    echo "$(date -Iseconds),$ENVIRONMENT,$monthly_cost" >> cost-savings.log
}

# External system cleanup
cleanup_external_systems() {
    # Remove from monitoring systems
    curl -X DELETE "$MONITORING_API/environments/$ENVIRONMENT"

    # Update DNS records
    remove_dns_records "$ENVIRONMENT"

    # Revoke certificates
    revoke_ssl_certificates "$ENVIRONMENT"
}

# Audit logging
create_audit_record() {
    local audit_log="/var/log/coder/teardown-audit.log"
    echo "$(date -Iseconds) TEARDOWN $ENVIRONMENT by $(whoami)" >> "$audit_log"
}
```

## Environment Variables Available

The following environment variables are available in hooks:

### From Main Scripts
- `ENVIRONMENT` - Target environment
- `TEMPLATE` - Selected template (setup only)
- `TEARDOWN_CONFIRMED` - Teardown confirmation (teardown only)
- `TEARDOWN_TIMESTAMP` - When teardown started

### System Information
- `PROJECT_ROOT` - Project root directory
- `KUBECONFIG` - Kubernetes config path
- `SCW_*` - Scaleway credentials (if set)

### Custom Variables
You can set custom variables in pre-hooks for use in post-hooks:

```bash
# In pre-setup.sh
export CUSTOM_DEPLOYMENT_ID="deploy-$(date +%s)"

# In post-setup.sh
log INFO "Deployment ID: $CUSTOM_DEPLOYMENT_ID"
```

## Error Handling

Hooks can control script execution flow:

```bash
# Exit with error to stop execution
if [[ "$critical_check" == "failed" ]]; then
    log ERROR "Critical check failed"
    exit 1  # This will stop the main script
fi

# Exit successfully to continue
log INFO "All checks passed"
exit 0
```

## Integration Examples

### Slack Notifications

```bash
send_slack_message() {
    local message="$1"
    local webhook="${SLACK_WEBHOOK:-}"

    if [[ -n "$webhook" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data '{"text":"'"$message"'"}' \
            "$webhook"
    fi
}
```

### JIRA Integration

```bash
create_jira_ticket() {
    local summary="$1"
    local description="$2"

    curl -X POST "$JIRA_API/issue" \
        -H "Authorization: Bearer $JIRA_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "fields": {
                "project": {"key": "OPS"},
                "summary": "'"$summary"'",
                "description": "'"$description"'",
                "issuetype": {"name": "Task"}
            }
        }'
}
```

### External Monitoring

```bash
update_monitoring() {
    local action="$1"  # "deploy" or "teardown"
    local env="$2"

    curl -X POST "$MONITORING_API/events" \
        -H "Authorization: Bearer $MONITORING_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "event": "environment_'"$action"'",
            "environment": "'"$env"'",
            "timestamp": "'"$(date -Iseconds)"'"
        }'
}
```

## Testing Hooks

Test hooks in isolation:

```bash
# Test pre-setup hook
./scripts/hooks/pre-setup.sh --env=dev

# Test with environment variables
ENVIRONMENT=staging ./scripts/hooks/post-setup.sh --env=staging
```

## Best Practices

1. **Always handle errors gracefully**
   ```bash
   command || {
       log WARN "Command failed but continuing"
       return 0
   }
   ```

2. **Use timeouts for external calls**
   ```bash
   timeout 30 curl "$external_api" || log WARN "API timeout"
   ```

3. **Make hooks idempotent**
   ```bash
   if [[ ! -f "/tmp/hook-completed" ]]; then
       # Run hook logic
       touch "/tmp/hook-completed"
   fi
   ```

4. **Log all actions clearly**
   ```bash
   log INFO "Starting custom integration..."
   log INFO "✅ Custom integration completed"
   ```

5. **Validate inputs and environment**
   ```bash
   if [[ -z "$REQUIRED_VAR" ]]; then
       log ERROR "REQUIRED_VAR not set"
       exit 1
   fi
   ```

## Debugging

Enable debug logging:

```bash
# Set in hook scripts
set -x  # Enable command tracing

# Or use debug logging
log DEBUG "Variable value: $important_var"
```

View hook execution logs:
```bash
# Setup logs
tail -f logs/setup/*-setup.log

# Teardown logs
tail -f logs/teardown/*-teardown.log
```

## Disabling Hooks

To temporarily disable hooks:

```bash
# Rename to prevent execution
mv scripts/hooks/pre-setup.sh scripts/hooks/pre-setup.sh.disabled

# Or use empty hook
echo '#!/bin/bash' > scripts/hooks/pre-setup.sh
echo 'exit 0' >> scripts/hooks/pre-setup.sh
```

The hooks framework provides powerful extensibility while maintaining the core functionality of the lifecycle scripts.