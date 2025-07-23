#!/usr/bin/env bash

# Terraform State Management Utility for Scaleway Object Storage
# Provides tools for inspecting, backing up, and managing remote state

set -euo pipefail

# Script constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups/state-backups"

# Default values
ENVIRONMENT=""
ACTION=""
WORKSPACE=""
OUTPUT_FORMAT="table"
VERBOSE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $*"
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 <action> --env=<environment> [options]

Manage Terraform state in Scaleway Object Storage.

Actions:
  show              Show current state summary
  list              List all resources in state
  backup            Create a backup of current state
  restore           Restore state from backup
  inspect           Detailed state inspection
  drift             Check for configuration drift
  cleanup           Clean up old state versions
  workspaces        Manage Terraform workspaces

Required Arguments:
  --env=<env>       Environment to manage (dev, staging, prod)

Options:
  --workspace=<ws>  Terraform workspace (default: default)
  --format=<fmt>    Output format (table, json, yaml) - default: table
  --verbose, -v     Enable verbose output
  --help, -h        Show this help message

Examples:
  # Show state summary
  $0 show --env=dev

  # List all resources in JSON format
  $0 list --env=prod --format=json

  # Create state backup
  $0 backup --env=staging

  # Check for configuration drift
  $0 drift --env=dev

  # Clean up old state versions
  $0 cleanup --env=prod

Environment Variables:
  SCW_ACCESS_KEY       Scaleway access key (required)
  SCW_SECRET_KEY       Scaleway secret key (required)
  SCW_DEFAULT_PROJECT_ID   Scaleway project ID (required)
EOF
}

# Check prerequisites
check_prerequisites() {
    if [[ "$VERBOSE" == true ]]; then
        log "Checking prerequisites..."
    fi

    # Check for required tools
    local missing_tools=()
    for tool in terraform jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Check Scaleway credentials
    if [[ -z "${SCW_ACCESS_KEY:-}" ]] || [[ -z "${SCW_SECRET_KEY:-}" ]] || [[ -z "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
        log_error "Missing Scaleway credentials"
        exit 1
    fi

    # Check environment directory
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    if [[ ! -d "$env_dir" ]]; then
        log_error "Environment directory not found: $env_dir"
        exit 1
    fi

    # Check backend configuration
    if [[ ! -f "$env_dir/backend.tf" ]]; then
        log_error "Backend configuration not found: $env_dir/backend.tf"
        log_error "Run setup-backend.sh first to create remote state infrastructure"
        exit 1
    fi

    if [[ "$VERBOSE" == true ]]; then
        log_success "Prerequisites check passed"
    fi
}

# Change to environment directory and ensure backend is initialized
setup_environment() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    cd "$env_dir"

    if [[ "$VERBOSE" == true ]]; then
        log "Working in environment: $ENVIRONMENT"
        log "Directory: $env_dir"
    fi

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    # Switch workspace if specified
    if [[ -n "$WORKSPACE" ]] && [[ "$WORKSPACE" != "default" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Switching to workspace: $WORKSPACE"
        fi
        terraform workspace select "$WORKSPACE" 2>/dev/null || terraform workspace new "$WORKSPACE"
    fi
}

# Format output based on specified format
format_output() {
    local data="$1"
    local format="$2"

    case "$format" in
        json)
            echo "$data" | jq .
            ;;
        yaml)
            echo "$data" | jq -r 'to_entries | map("\(.key): \(.value)") | .[]'
            ;;
        table|*)
            echo "$data"
            ;;
    esac
}

# Show state summary
action_show() {
    log "Showing state summary for environment: $ENVIRONMENT"

    local state_data
    if ! state_data=$(terraform show -json 2>/dev/null); then
        log_error "Failed to read state. Ensure the state exists and is accessible."
        return 1
    fi

    local terraform_version
    terraform_version=$(echo "$state_data" | jq -r '.terraform_version // "unknown"')

    local resource_count
    resource_count=$(echo "$state_data" | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")

    local output_count
    output_count=$(echo "$state_data" | jq '.values.outputs | length' 2>/dev/null || echo "0")

    # Get workspace info
    local current_workspace
    current_workspace=$(terraform workspace show 2>/dev/null || echo "default")

    # Get backend info
    local backend_type
    backend_type=$(terraform version -json | jq -r '.terraform_version' | head -1)

    case "$OUTPUT_FORMAT" in
        json)
            cat << EOF | jq .
{
  "environment": "$ENVIRONMENT",
  "workspace": "$current_workspace",
  "terraform_version": "$terraform_version",
  "resource_count": $resource_count,
  "output_count": $output_count,
  "state_serial": $(echo "$state_data" | jq '.serial // 0'),
  "last_modified": "$(date -Iseconds)"
}
EOF
            ;;
        *)
            cat << EOF

Environment State Summary
========================
Environment:        $ENVIRONMENT
Workspace:          $current_workspace
Terraform Version:  $terraform_version
Resources:          $resource_count
Outputs:            $output_count
State Serial:       $(echo "$state_data" | jq '.serial // 0')
Backend:            Scaleway Object Storage
Last Checked:       $(date)

EOF
            ;;
    esac
}

# List all resources in state
action_list() {
    log "Listing resources in state for environment: $ENVIRONMENT"

    local state_data
    if ! state_data=$(terraform show -json 2>/dev/null); then
        log_error "Failed to read state"
        return 1
    fi

    case "$OUTPUT_FORMAT" in
        json)
            echo "$state_data" | jq '.values.root_module.resources[] | {
                address: .address,
                type: .type,
                name: .name,
                provider: .provider_name
            }'
            ;;
        *)
            echo
            echo "Resources in State"
            echo "=================="
            printf "%-50s %-20s %-15s\n" "ADDRESS" "TYPE" "PROVIDER"
            printf "%-50s %-20s %-15s\n" "$(printf '%*s' 50 | tr ' ' '-')" "$(printf '%*s' 20 | tr ' ' '-')" "$(printf '%*s' 15 | tr ' ' '-')"

            echo "$state_data" | jq -r '.values.root_module.resources[]? | [.address, .type, .provider_name] | @tsv' | \
            while IFS=$'\t' read -r address type provider; do
                printf "%-50s %-20s %-15s\n" "$address" "$type" "$provider"
            done
            echo
            ;;
    esac
}

# Create state backup
action_backup() {
    log "Creating state backup for environment: $ENVIRONMENT"

    mkdir -p "$BACKUP_DIR"

    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_name="${ENVIRONMENT}-${timestamp}"
    local backup_dir="${BACKUP_DIR}/${backup_name}"

    mkdir -p "$backup_dir"

    # Backup state file
    if terraform state pull > "$backup_dir/terraform.tfstate"; then
        log_success "State backed up to: $backup_dir/terraform.tfstate"
    else
        log_error "Failed to create state backup"
        return 1
    fi

    # Create metadata
    cat > "$backup_dir/metadata.json" << EOF
{
  "environment": "$ENVIRONMENT",
  "workspace": "$(terraform workspace show 2>/dev/null || echo "default")",
  "backup_date": "$(date -Iseconds)",
  "terraform_version": "$(terraform version -json | jq -r '.terraform_version')",
  "resource_count": $(terraform show -json 2>/dev/null | jq '.values.root_module.resources | length' || echo 0),
  "backup_method": "state-manager-script"
}
EOF

    # Create readme
    cat > "$backup_dir/README.md" << EOF
# State Backup: $backup_name

**Environment:** $ENVIRONMENT
**Date:** $(date)
**Terraform Version:** $(terraform version -json | jq -r '.terraform_version')

## Files

- \`terraform.tfstate\` - Complete state backup
- \`metadata.json\` - Backup metadata
- \`README.md\` - This file

## Restore Instructions

To restore this state backup:

\`\`\`bash
# Using the state manager
./scripts/utils/state-manager.sh restore --env=$ENVIRONMENT --backup=$backup_name

# Or manually
cd environments/$ENVIRONMENT
terraform state push $backup_dir/terraform.tfstate
\`\`\`

## Verification

After restore, verify with:
\`\`\`bash
terraform plan
terraform show
\`\`\`
EOF

    log_success "Backup created: $backup_name"
    echo "Location: $backup_dir"
}

# Restore state from backup
action_restore() {
    if [[ -z "${BACKUP_NAME:-}" ]]; then
        log_error "Backup name required for restore. Use --backup=<name>"
        return 1
    fi

    local backup_dir="${BACKUP_DIR}/${BACKUP_NAME}"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_dir"
        return 1
    fi

    if [[ ! -f "$backup_dir/terraform.tfstate" ]]; then
        log_error "State file not found in backup: $backup_dir/terraform.tfstate"
        return 1
    fi

    log_warning "This will replace the current state with the backup"
    log_warning "Backup: $BACKUP_NAME"
    log_warning "Environment: $ENVIRONMENT"

    read -p "Continue with restore? [y/N]: " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled"
        return 0
    fi

    log "Restoring state from backup: $BACKUP_NAME"

    if terraform state push "$backup_dir/terraform.tfstate"; then
        log_success "State restored successfully"
        log "Run 'terraform plan' to verify the restored state"
    else
        log_error "Failed to restore state"
        return 1
    fi
}

# Inspect state in detail
action_inspect() {
    log "Inspecting state for environment: $ENVIRONMENT"

    local state_data
    if ! state_data=$(terraform show -json 2>/dev/null); then
        log_error "Failed to read state"
        return 1
    fi

    case "$OUTPUT_FORMAT" in
        json)
            echo "$state_data"
            ;;
        *)
            echo
            echo "Detailed State Inspection"
            echo "========================"

            # Basic info
            echo "Terraform Version: $(echo "$state_data" | jq -r '.terraform_version')"
            echo "State Serial: $(echo "$state_data" | jq '.serial')"
            echo "State Lineage: $(echo "$state_data" | jq -r '.lineage')"
            echo

            # Resources by type
            echo "Resources by Type:"
            echo "$state_data" | jq -r '.values.root_module.resources[]?.type' | sort | uniq -c | sort -nr
            echo

            # Providers
            echo "Providers:"
            echo "$state_data" | jq -r '.values.root_module.resources[]?.provider_name' | sort | uniq -c
            echo

            # Outputs
            local outputs
            outputs=$(echo "$state_data" | jq '.values.outputs // {}')
            if [[ "$outputs" != "{}" ]]; then
                echo "Outputs:"
                echo "$outputs" | jq -r 'to_entries[] | "  \(.key): \(.value.value)"'
                echo
            fi
            ;;
    esac
}

# Check for configuration drift
action_drift() {
    log "Checking for configuration drift in environment: $ENVIRONMENT"

    local plan_output
    local plan_exit_code

    if plan_output=$(terraform plan -detailed-exitcode 2>&1); then
        plan_exit_code=$?
    else
        plan_exit_code=$?
    fi

    case $plan_exit_code in
        0)
            log_success "No drift detected - infrastructure matches configuration"
            ;;
        1)
            log_error "Error running terraform plan"
            echo "$plan_output"
            return 1
            ;;
        2)
            log_warning "Configuration drift detected"
            case "$OUTPUT_FORMAT" in
                json)
                    echo '{"drift_detected": true, "plan_output": "'"$(echo "$plan_output" | sed 's/"/\\"/g' | tr '\n' ' ')"'"}'
                    ;;
                *)
                    echo
                    echo "Drift Details:"
                    echo "=============="
                    echo "$plan_output"
                    echo
                    log_warning "Run 'terraform apply' to fix drift"
                    ;;
            esac
            ;;
    esac
}

# Clean up old state versions
action_cleanup() {
    log_warning "State cleanup functionality requires Scaleway CLI integration"
    log "This feature will clean up old state versions in Object Storage"
    log "Manual cleanup can be done through Scaleway console or CLI"

    # For now, just show information about state versions
    log "Current state info:"
    action_show
}

# Manage workspaces
action_workspaces() {
    log "Managing workspaces for environment: $ENVIRONMENT"

    case "${WORKSPACE_ACTION:-list}" in
        list)
            echo
            echo "Available Workspaces:"
            echo "===================="
            terraform workspace list
            echo
            echo "Current workspace: $(terraform workspace show)"
            ;;
        new)
            if [[ -z "$WORKSPACE" ]]; then
                log_error "Workspace name required. Use --workspace=<name>"
                return 1
            fi
            terraform workspace new "$WORKSPACE"
            log_success "Created workspace: $WORKSPACE"
            ;;
        select)
            if [[ -z "$WORKSPACE" ]]; then
                log_error "Workspace name required. Use --workspace=<name>"
                return 1
            fi
            terraform workspace select "$WORKSPACE"
            log_success "Switched to workspace: $WORKSPACE"
            ;;
        delete)
            if [[ -z "$WORKSPACE" ]]; then
                log_error "Workspace name required. Use --workspace=<name>"
                return 1
            fi
            terraform workspace delete "$WORKSPACE"
            log_success "Deleted workspace: $WORKSPACE"
            ;;
    esac
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    ACTION="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --workspace=*)
                WORKSPACE="${1#*=}"
                shift
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
                shift
                ;;
            --backup=*)
                BACKUP_NAME="${1#*=}"
                shift
                ;;
            --workspace-action=*)
                WORKSPACE_ACTION="${1#*=}"
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required. Use --env=<environment>"
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
        exit 1
    fi

    # Validate output format
    if [[ ! "$OUTPUT_FORMAT" =~ ^(table|json|yaml)$ ]]; then
        log_error "Invalid format: $OUTPUT_FORMAT. Must be one of: table, json, yaml"
        exit 1
    fi

    # Validate action
    if [[ ! "$ACTION" =~ ^(show|list|backup|restore|inspect|drift|cleanup|workspaces)$ ]]; then
        log_error "Invalid action: $ACTION. Must be one of: show, list, backup, restore, inspect, drift, cleanup, workspaces"
        exit 1
    fi
}

# Main execution function
main() {
    parse_args "$@"
    check_prerequisites
    setup_environment

    case "$ACTION" in
        show)
            action_show
            ;;
        list)
            action_list
            ;;
        backup)
            action_backup
            ;;
        restore)
            action_restore
            ;;
        inspect)
            action_inspect
            ;;
        drift)
            action_drift
            ;;
        cleanup)
            action_cleanup
            ;;
        workspaces)
            action_workspaces
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi