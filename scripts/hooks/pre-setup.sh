#!/bin/bash

# Pre-Setup Hook
# Execute custom logic before environment setup

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${GREEN}[PRE-SETUP]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[PRE-SETUP]${NC} $message" ;;
        ERROR) echo -e "${RED}[PRE-SETUP]${NC} $message" ;;
    esac
}

# Parse command line arguments
ENVIRONMENT=""

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

log INFO "Running pre-setup hook for environment: ${ENVIRONMENT:-unknown}"

# Example pre-setup tasks:

# 1. Check system resources
log INFO "Checking system resources..."
if command -v free &>/dev/null; then
    memory_gb=$(free -g | awk 'NR==2{print $2}')
    if [[ "$memory_gb" -lt 8 ]]; then
        log WARN "System has less than 8GB RAM - deployment may be slow"
    fi
fi

# 2. Check disk space
log INFO "Checking available disk space..."
if command -v df &>/dev/null; then
    available_space=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ "$available_space" -lt 10 ]]; then
        log WARN "Less than 10GB disk space available"
    fi
fi

# 3. Environment-specific pre-setup
case "$ENVIRONMENT" in
    prod)
        log INFO "Production environment detected - running additional checks..."

        # Check if it's business hours (example check)
        current_hour=$(date +%H)
        if [[ "$current_hour" -ge 9 && "$current_hour" -le 17 ]]; then
            log WARN "Deploying to production during business hours - consider off-peak deployment"
        fi

        # Example: Check for maintenance windows
        # if [[ -f "/etc/maintenance-window" ]]; then
        #     log ERROR "System is in maintenance window - deployment blocked"
        #     exit 1
        # fi
        ;;
    staging)
        log INFO "Staging environment - checking for active deployments..."
        # Example: Check if staging is already being used
        ;;
    dev)
        log INFO "Development environment - no special restrictions"
        ;;
esac

# 4. Check external dependencies
log INFO "Checking external service connectivity..."

# Example: Check Scaleway API connectivity
if command -v curl &>/dev/null; then
    if ! curl -s --max-time 10 https://api.scaleway.com >/dev/null; then
        log WARN "Scaleway API connectivity check failed"
    fi
fi

# Example: Check container registries
# if ! curl -s --max-time 10 https://registry-1.docker.io >/dev/null; then
#     log WARN "Docker Hub connectivity check failed"
# fi

# 5. Backup critical data (if exists)
log INFO "Checking for existing critical data..."
# Example: Auto-backup existing configurations
# if [[ -f "important-config.yaml" ]]; then
#     cp "important-config.yaml" "important-config.yaml.backup-$(date +%Y%m%d-%H%M%S)"
#     log INFO "Backed up existing configuration"
# fi

# 6. Custom organization-specific checks
log INFO "Running organization-specific pre-checks..."

# Example: Check compliance requirements
# if [[ "$ENVIRONMENT" == "prod" ]]; then
#     # Check if required compliance tools are available
#     if ! command -v compliance-scanner &>/dev/null; then
#         log ERROR "Compliance scanner required for production deployments"
#         exit 1
#     fi
# fi

# Slack notification (optional - activated when SLACK_WEBHOOK is set)
send_slack_notification() {
    local message="$1"
    local environment="$2"

    # Use environment-specific webhook if available
    local webhook="${SLACK_WEBHOOK:-}"
    case "$environment" in
        dev) webhook="${SLACK_WEBHOOK_DEV:-$webhook}" ;;
        staging) webhook="${SLACK_WEBHOOK_STAGING:-$webhook}" ;;
        prod) webhook="${SLACK_WEBHOOK_PROD:-$webhook}" ;;
    esac

    if [[ -n "$webhook" ]]; then
        local response=$(curl -s -X POST -H 'Content-type: application/json' \
            --max-time 10 \
            --data '{
                "attachments": [{
                    "color": "good",
                    "text": "'"$message"'",
                    "fields": [
                        {
                            "title": "Environment",
                            "value": "'"$environment"'",
                            "short": true
                        },
                        {
                            "title": "Phase",
                            "value": "Pre-Setup",
                            "short": true
                        },
                        {
                            "title": "Timestamp",
                            "value": "'"$(date -Iseconds)"'",
                            "short": false
                        }
                    ]
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

# Send pre-setup notification
send_slack_notification "🚀 Starting Coder deployment to $ENVIRONMENT environment" "$ENVIRONMENT"

log INFO "Pre-setup hook completed successfully"

# Return success
exit 0