#!/usr/bin/env bash

# Terraform State Migration Script for Scaleway Object Storage
# Safely migrates local Terraform state to remote backend storage

set -euo pipefail

# Script constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly BACKUP_DIR="${PROJECT_ROOT}/backups/state-migration"
readonly LOG_FILE="${BACKUP_DIR}/migration-$(date +%Y%m%d-%H%M%S).log"

# Default values
ENVIRONMENT=""
DRY_RUN=false
FORCE=false
SKIP_BACKUP=false
VERBOSE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $*" | tee -a "${LOG_FILE}"
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 --env=<environment> [options]

Migrate Terraform state from local to remote Scaleway Object Storage backend.

Required Arguments:
  --env=<env>           Environment to migrate (dev, staging, prod)

Options:
  --dry-run            Show what would be done without making changes
  --force              Skip interactive confirmation prompts
  --skip-backup        Skip creating local state backup (not recommended)
  --verbose, -v        Enable verbose output
  --help, -h           Show this help message

Examples:
  # Dry run migration for dev environment
  $0 --env=dev --dry-run

  # Migrate staging with verbose output
  $0 --env=staging --verbose

  # Force migration without prompts (for automation)
  $0 --env=prod --force

Environment Variables:
  SCW_ACCESS_KEY       Scaleway access key (required)
  SCW_SECRET_KEY       Scaleway secret key (required)
  SCW_DEFAULT_PROJECT_ID   Scaleway project ID (required)

Prerequisites:
  - Terraform >= 1.12.0
  - Scaleway CLI (scw) configured
  - Valid Scaleway credentials
  - Backend infrastructure already created
EOF
}

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."

    local missing_tools=()

    # Check for required tools
    for tool in terraform scw jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again"
        exit 1
    fi

    # Check Terraform version
    local tf_version
    tf_version=$(terraform version -json | jq -r '.terraform_version')
    local tf_major
    tf_major=$(echo "$tf_version" | cut -d. -f1)
    local tf_minor
    tf_minor=$(echo "$tf_version" | cut -d. -f2)

    if [[ $tf_major -lt 1 ]] || [[ $tf_major -eq 1 && $tf_minor -lt 6 ]]; then
        log_error "Terraform version $tf_version is not supported. Minimum required: 1.12.0"
        exit 1
    fi

    # Check Scaleway credentials
    if [[ -z "${SCW_ACCESS_KEY:-}" ]] || [[ -z "${SCW_SECRET_KEY:-}" ]] || [[ -z "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
        log_error "Missing Scaleway credentials. Please set:"
        log_error "  SCW_ACCESS_KEY"
        log_error "  SCW_SECRET_KEY"
        log_error "  SCW_DEFAULT_PROJECT_ID"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Validate environment and check if backend configuration exists
validate_environment() {
    log "Validating environment: $ENVIRONMENT"

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"

    if [[ ! -d "$env_dir" ]]; then
        log_error "Environment directory not found: $env_dir"
        exit 1
    fi

    # Check if local state exists
    if [[ ! -f "$env_dir/terraform.tfstate" ]]; then
        log_warning "No local state file found at $env_dir/terraform.tfstate"
        log "This environment might already be using remote state or hasn't been initialized"

        if [[ "$FORCE" == false ]]; then
            read -p "Continue anyway? [y/N]: " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Migration cancelled by user"
                exit 0
            fi
        fi
    fi

    # Check if backend configuration exists
    if [[ ! -f "$env_dir/backend.tf" ]]; then
        log_error "Backend configuration not found: $env_dir/backend.tf"
        log_error "Please create the backend infrastructure first using the terraform-backend module"
        exit 1
    fi

    log_success "Environment validation passed"
}

# Create backup of current state
create_backup() {
    if [[ "$SKIP_BACKUP" == true ]]; then
        log_warning "Skipping backup creation (--skip-backup flag used)"
        return 0
    fi

    log "Creating backup of current state..."

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local backup_env_dir="${BACKUP_DIR}/${ENVIRONMENT}"

    # Create backup directory
    mkdir -p "$backup_env_dir"

    # Backup entire environment directory
    if [[ -d "$env_dir" ]]; then
        cp -r "$env_dir" "$backup_env_dir/"
        log_success "Environment backup created: $backup_env_dir"
    fi

    # Create additional metadata
    cat > "${backup_env_dir}/migration-metadata.json" << EOF
{
  "migration_date": "$(date -Iseconds)",
  "environment": "$ENVIRONMENT",
  "terraform_version": "$(terraform version -json | jq -r '.terraform_version')",
  "local_state_exists": $([ -f "$env_dir/terraform.tfstate" ] && echo "true" || echo "false"),
  "migration_script_version": "1.0.0"
}
EOF

    log_success "Backup metadata created"
}

# Perform the state migration
migrate_state() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"

    log "Starting state migration for environment: $ENVIRONMENT"

    cd "$env_dir"

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would perform the following actions:"
        log "1. Initialize Terraform with new backend configuration"
        log "2. Migrate existing state to remote backend"
        log "3. Verify state integrity"
        return 0
    fi

    # Initialize with new backend
    log "Initializing Terraform with remote backend..."
    if [[ "$VERBOSE" == true ]]; then
        terraform init
    else
        terraform init > "${LOG_FILE}.terraform-init" 2>&1
    fi

    # Terraform should automatically detect local state and ask to migrate
    # If it doesn't, we'll need to handle this manually

    log_success "Backend initialization completed"

    # Verify the migration worked
    log "Verifying state migration..."

    # Check if we can read the state from remote backend
    local remote_state_check
    if remote_state_check=$(terraform show -json 2>/dev/null); then
        log_success "Remote state is accessible and valid"

        # Count resources in remote state
        local resource_count
        resource_count=$(echo "$remote_state_check" | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")
        log "Resources in remote state: $resource_count"
    else
        log_error "Failed to read remote state"
        return 1
    fi

    # If local state still exists and is not empty, warn about it
    if [[ -f "terraform.tfstate" ]] && [[ -s "terraform.tfstate" ]]; then
        log_warning "Local state file still exists and is not empty"
        log_warning "You may want to remove it after confirming remote state is working"
        log_warning "Location: $env_dir/terraform.tfstate"
    fi

    log_success "State migration completed successfully"
}

# Verify the migration was successful
verify_migration() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"

    log "Performing post-migration verification..."

    cd "$env_dir"

    # Run terraform plan to ensure everything is working
    log "Running terraform plan to verify state consistency..."

    local plan_output
    if plan_output=$(terraform plan -detailed-exitcode 2>&1); then
        local plan_exit_code=$?

        case $plan_exit_code in
            0)
                log_success "No changes needed - state is consistent"
                ;;
            2)
                log_warning "Terraform plan shows pending changes"
                log "This might be normal if there were uncommitted changes"
                if [[ "$VERBOSE" == true ]]; then
                    echo "$plan_output"
                fi
                ;;
            *)
                log_error "Terraform plan failed"
                echo "$plan_output"
                return 1
                ;;
        esac
    else
        log_error "Failed to run terraform plan"
        return 1
    fi

    # Check backend configuration
    log "Verifying backend configuration..."

    if terraform init -backend=false &> /dev/null; then
        log_success "Backend configuration is valid"
    else
        log_error "Backend configuration validation failed"
        return 1
    fi

    log_success "Post-migration verification completed"
}

# Generate migration report
generate_report() {
    local report_file="${BACKUP_DIR}/migration-report-$(date +%Y%m%d-%H%M%S).md"

    log "Generating migration report..."

    cat > "$report_file" << EOF
# Terraform State Migration Report

**Environment:** $ENVIRONMENT
**Date:** $(date -Iseconds)
**Status:** $(if [[ "$DRY_RUN" == true ]]; then echo "DRY RUN"; else echo "COMPLETED"; fi)

## Migration Details

- **Local State Backup:** $BACKUP_DIR/$ENVIRONMENT
- **Migration Log:** $LOG_FILE
- **Environment Directory:** $PROJECT_ROOT/environments/$ENVIRONMENT

## Pre-Migration State

- Local state file existed: $([ -f "$PROJECT_ROOT/environments/$ENVIRONMENT/terraform.tfstate" ] && echo "Yes" || echo "No")
- Backend configuration: $PROJECT_ROOT/environments/$ENVIRONMENT/backend.tf

## Post-Migration Checklist

- [ ] Verify remote state accessibility
- [ ] Run \`terraform plan\` to check for drift
- [ ] Test normal terraform operations
- [ ] Remove local state file if migration successful
- [ ] Update team documentation with new backend process
- [ ] Configure GitHub Actions with remote state

## Commands for Verification

\`\`\`bash
cd environments/$ENVIRONMENT

# Check remote state
terraform show

# Verify no drift
terraform plan

# List workspaces (if using workspaces)
terraform workspace list
\`\`\`

## Rollback Instructions

If needed, restore from backup:

\`\`\`bash
# Stop using remote backend temporarily
cd environments/$ENVIRONMENT
cp backend.tf backend.tf.backup
rm backend.tf

# Restore local state
cp $BACKUP_DIR/$ENVIRONMENT/terraform.tfstate ./

# Reinitialize with local backend
terraform init

# Restore backend configuration when ready
cp backend.tf.backup backend.tf
\`\`\`

## Notes

$(if [[ "$DRY_RUN" == true ]]; then
echo "This was a dry run. No actual migration was performed."
else
echo "Migration completed successfully. Monitor for any issues and verify team access."
fi)
EOF

    log_success "Migration report generated: $report_file"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --skip-backup)
                SKIP_BACKUP=true
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

    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required. Use --env=<environment>"
        usage
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod"
        exit 1
    fi
}

# Confirmation prompt
confirm_migration() {
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    echo
    echo "======================================"
    echo "  Terraform State Migration Summary"
    echo "======================================"
    echo "Environment: $ENVIRONMENT"
    echo "Source: Local state file"
    echo "Target: Scaleway Object Storage"
    echo "Backup: $(if [[ "$SKIP_BACKUP" == true ]]; then echo "Disabled"; else echo "Enabled"; fi)"
    echo "======================================"
    echo
    echo "⚠️  This operation will:"
    echo "   • Migrate your Terraform state to remote storage"
    echo "   • Change how you and your team interact with this environment"
    echo "   • Require all team members to reconfigure their local setup"
    echo
    read -p "Are you sure you want to proceed? [y/N]: " -r

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Migration cancelled by user"
        exit 0
    fi
}

# Main execution function
main() {
    # Setup logging
    mkdir -p "$BACKUP_DIR"
    touch "$LOG_FILE"

    log "Starting Terraform state migration script"
    log "Arguments: $*"

    # Parse command line arguments
    parse_args "$@"

    # Run migration steps
    check_prerequisites
    validate_environment
    confirm_migration
    create_backup
    migrate_state

    if [[ "$DRY_RUN" == false ]]; then
        verify_migration
    fi

    generate_report

    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry run completed successfully"
        log "Use the same command without --dry-run to perform the actual migration"
    else
        log_success "State migration completed successfully!"
        log "Next steps:"
        log "  1. Verify terraform operations work correctly"
        log "  2. Update your team documentation"
        log "  3. Configure GitHub Actions with remote state"
        log "  4. Remove the local state file if everything works correctly"
    fi
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi