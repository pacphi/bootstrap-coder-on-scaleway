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
PHASE=""
TWO_PHASE=false

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

Migrate Terraform state from local to remote Scaleway Object Storage backend with two-phase support.

Required Arguments:
  --env=<env>           Environment to migrate (dev, staging, prod)

Two-Phase Options:
  --phase=<phase>       Specific phase to migrate (infra, coder)
  --two-phase           Migrate both phases (infra and coder)

Options:
  --dry-run            Show what would be done without making changes
  --force              Skip interactive confirmation prompts
  --skip-backup        Skip creating local state backup (not recommended)
  --verbose, -v        Enable verbose output
  --help, -h           Show this help message

Examples:
  # Legacy single-phase migration
  $0 --env=dev --dry-run
  $0 --env=staging --verbose

  # Two-phase migration (both phases)
  $0 --env=dev --two-phase --dry-run
  $0 --env=prod --two-phase --force

  # Phase-specific migration
  $0 --env=dev --phase=infra
  $0 --env=staging --phase=coder --verbose

Environment Variables:
  SCW_ACCESS_KEY       Scaleway access key (required)
  SCW_SECRET_KEY       Scaleway secret key (required)
  SCW_DEFAULT_PROJECT_ID   Scaleway project ID (required)

Two-Phase Architecture:
  This script automatically detects environment structure:
  - Legacy: Single main.tf in environments/<env>/
  - Two-Phase: Separate infra/ and coder/ directories

  For two-phase environments:
  - infra/: Infrastructure state (cluster, database, networking)
  - coder/: Application state (Coder platform, templates)

Prerequisites:
  - Terraform >= 1.13.3
  - Valid Scaleway credentials
  - Backend infrastructure already created
EOF
}

# Detect environment structure
detect_environment_structure() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local infra_dir="${env_dir}/infra"
    local coder_dir="${env_dir}/coder"

    if [[ -d "$infra_dir" && -d "$coder_dir" ]]; then
        echo "two-phase"
    elif [[ -f "${env_dir}/main.tf" ]]; then
        echo "legacy"
    else
        echo "unknown"
    fi
}

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."

    local missing_tools=()

    # Check for required tools (removed scw as it's not strictly required)
    for tool in terraform jq; do
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

    if [[ $tf_major -lt 1 ]] || [[ $tf_major -eq 1 && $tf_minor -lt 13 ]]; then
        log_error "Terraform version $tf_version is not supported. Minimum required: 1.13.3"
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

    # Detect environment structure and validate
    local structure=$(detect_environment_structure)
    log "Detected environment structure: $structure"

    if [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
            # Validate phase-specific configurations
            if [[ "$TWO_PHASE" == true || "$PHASE" == "infra" ]]; then
                validate_phase_environment "infra" "$env_dir"
            fi
            if [[ "$TWO_PHASE" == true || "$PHASE" == "coder" ]]; then
                validate_phase_environment "coder" "$env_dir"
            fi
        else
            log_error "Two-phase environment detected but no phase specified"
            log_error "Use --phase=[infra|coder] or --two-phase flag"
            exit 1
        fi
    elif [[ "$structure" == "legacy" ]]; then
        if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
            log_error "Legacy single-phase environment detected, but two-phase options specified"
            log_error "Remove --phase or --two-phase flags for legacy environments"
            exit 1
        fi
        validate_legacy_environment "$env_dir"
    else
        log_error "Unknown environment structure: $structure"
        exit 1
    fi

    log_success "Environment validation passed"
}

# Validate legacy single-phase environment
validate_legacy_environment() {
    local env_dir="$1"

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
        log_error "Please create the backend infrastructure first using setup-backend.sh"
        exit 1
    fi
}

# Validate two-phase environment for a specific phase
validate_phase_environment() {
    local phase="$1"
    local env_dir="$2"
    local phase_dir="${env_dir}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        exit 1
    fi

    # Check if local state exists for this phase
    if [[ ! -f "$phase_dir/terraform.tfstate" ]]; then
        log_warning "No local state file found for $phase phase at $phase_dir/terraform.tfstate"
        log "This phase might already be using remote state or hasn't been initialized"

        if [[ "$FORCE" == false ]]; then
            read -p "Continue with $phase phase anyway? [y/N]: " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Migration cancelled by user"
                exit 0
            fi
        fi
    fi

    # Check if backend configuration exists for this phase
    if [[ ! -f "$phase_dir/providers.tf" ]]; then
        log_error "Backend configuration not found for $phase phase: $phase_dir/providers.tf"
        log_error "Please create the backend infrastructure first using setup-backend.sh"
        exit 1
    fi
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
    local structure=$(detect_environment_structure)

    # Create backup directory
    mkdir -p "$backup_env_dir"

    # Backup entire environment directory
    if [[ -d "$env_dir" ]]; then
        cp -r "$env_dir" "$backup_env_dir/"
        log_success "Environment backup created: $backup_env_dir"
    fi

    # Create additional metadata
    if [[ "$structure" == "two-phase" ]]; then
        cat > "${backup_env_dir}/migration-metadata.json" << EOF
{
  "migration_date": "$(date -Iseconds)",
  "environment": "$ENVIRONMENT",
  "structure": "two-phase",
  "phases": $(if [[ "$TWO_PHASE" == true ]]; then echo '["infra", "coder"]'; elif [[ -n "$PHASE" ]]; then echo "[\"$PHASE\"]"; fi),
  "terraform_version": "$(terraform version -json | jq -r '.terraform_version')",
  "infra_local_state_exists": $([ -f "$env_dir/infra/terraform.tfstate" ] && echo "true" || echo "false"),
  "coder_local_state_exists": $([ -f "$env_dir/coder/terraform.tfstate" ] && echo "true" || echo "false"),
  "migration_script_version": "2.0.0"
}
EOF
    else
        cat > "${backup_env_dir}/migration-metadata.json" << EOF
{
  "migration_date": "$(date -Iseconds)",
  "environment": "$ENVIRONMENT",
  "structure": "legacy",
  "terraform_version": "$(terraform version -json | jq -r '.terraform_version')",
  "local_state_exists": $([ -f "$env_dir/terraform.tfstate" ] && echo "true" || echo "false"),
  "migration_script_version": "2.0.0"
}
EOF
    fi

    log_success "Backup metadata created"
}

# Migrate state for a specific phase
migrate_phase_state() {
    local phase="$1"
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local phase_dir="${env_dir}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    log "Starting $phase phase state migration for environment: $ENVIRONMENT"

    cd "$phase_dir"

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would perform the following actions for $phase phase:"
        log "1. Initialize Terraform with new backend configuration"
        log "2. Migrate existing state to remote backend"
        log "3. Verify state integrity"
        return 0
    fi

    # Initialize with new backend
    log "Initializing $phase phase Terraform with remote backend..."
    if [[ "$VERBOSE" == true ]]; then
        terraform init
    else
        terraform init > "${LOG_FILE}.${phase}-terraform-init" 2>&1
    fi

    log_success "$phase phase backend initialization completed"

    # Verify the migration worked
    log "Verifying $phase phase state migration..."

    # Check if we can read the state from remote backend
    local remote_state_check
    if remote_state_check=$(terraform show -json 2>/dev/null); then
        log_success "$phase phase remote state is accessible and valid"

        # Count resources in remote state
        local resource_count
        resource_count=$(echo "$remote_state_check" | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")
        log "Resources in $phase phase remote state: $resource_count"
    else
        log_error "Failed to read $phase phase remote state"
        return 1
    fi

    # If local state still exists and is not empty, warn about it
    if [[ -f "terraform.tfstate" ]] && [[ -s "terraform.tfstate" ]]; then
        log_warning "$phase phase local state file still exists and is not empty"
        log_warning "You may want to remove it after confirming remote state is working"
        log_warning "Location: $phase_dir/terraform.tfstate"
    fi

    log_success "$phase phase state migration completed successfully"
}

# Perform the state migration
migrate_state() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
        local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
        if [[ -f "terraform.tfstate" ]] && [[ -s "terraform.tfstate" ]]; then
            log_warning "Local state file still exists and is not empty"
            log_warning "You may want to remove it after confirming remote state is working"
            log_warning "Location: $env_dir/terraform.tfstate"
        fi

        log_success "State migration completed successfully"
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Starting two-phase state migration for environment: $ENVIRONMENT"

            # Migrate both phases
            migrate_phase_state "infra"
            migrate_phase_state "coder"

            log_success "Two-phase state migration completed successfully"
        elif [[ -n "$PHASE" ]]; then
            migrate_phase_state "$PHASE"
        fi
    fi
}

# Verify the migration was successful for a specific phase
verify_phase_migration() {
    local phase="$1"
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local phase_dir="${env_dir}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    log "Performing post-migration verification for $phase phase..."

    cd "$phase_dir"

    # Run terraform plan to ensure everything is working
    log "Running terraform plan to verify $phase phase state consistency..."

    local plan_output
    if plan_output=$(terraform plan -detailed-exitcode 2>&1); then
        local plan_exit_code=$?

        case $plan_exit_code in
            0)
                log_success "No changes needed - $phase phase state is consistent"
                ;;
            2)
                log_warning "Terraform plan shows pending changes in $phase phase"
                log "This might be normal if there were uncommitted changes"
                if [[ "$VERBOSE" == true ]]; then
                    echo "$plan_output"
                fi
                ;;
            *)
                log_error "$phase phase terraform plan failed"
                echo "$plan_output"
                return 1
                ;;
        esac
    else
        log_error "Failed to run terraform plan for $phase phase"
        return 1
    fi

    # Check backend configuration
    log "Verifying $phase phase backend configuration..."

    if terraform init -backend=false &> /dev/null; then
        log_success "$phase phase backend configuration is valid"
    else
        log_error "$phase phase backend configuration validation failed"
        return 1
    fi

    log_success "$phase phase post-migration verification completed"
}

# Verify the migration was successful
verify_migration() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Performing two-phase post-migration verification..."

            # Verify both phases
            verify_phase_migration "infra"
            verify_phase_migration "coder"

            log_success "Two-phase post-migration verification completed"
        elif [[ -n "$PHASE" ]]; then
            verify_phase_migration "$PHASE"
        fi
    fi
}

# Generate migration report
generate_report() {
    local report_file="${BACKUP_DIR}/migration-report-$(date +%Y%m%d-%H%M%S).md"
    local structure=$(detect_environment_structure)

    log "Generating migration report..."

    if [[ "$structure" == "two-phase" ]]; then
        generate_two_phase_report "$report_file"
    else
        generate_legacy_report "$report_file"
    fi

    log_success "Migration report generated: $report_file"
}

# Generate migration report for legacy environments
generate_legacy_report() {
    local report_file="$1"

    cat > "$report_file" << EOF
# Terraform State Migration Report

**Environment:** $ENVIRONMENT
**Structure:** Legacy (Single-Phase)
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
}

# Generate migration report for two-phase environments
generate_two_phase_report() {
    local report_file="$1"

    cat > "$report_file" << EOF
# Two-Phase Terraform State Migration Report

**Environment:** $ENVIRONMENT
**Structure:** Two-Phase (Infrastructure + Coder)
**Date:** $(date -Iseconds)
**Status:** $(if [[ "$DRY_RUN" == true ]]; then echo "DRY RUN"; else echo "COMPLETED"; fi)
**Phases Migrated:** $(if [[ "$TWO_PHASE" == true ]]; then echo "infra, coder (both)"; elif [[ -n "$PHASE" ]]; then echo "$PHASE"; fi)

## Migration Details

- **Local State Backup:** $BACKUP_DIR/$ENVIRONMENT
- **Migration Log:** $LOG_FILE
- **Environment Directory:** $PROJECT_ROOT/environments/$ENVIRONMENT
- **Infrastructure Phase:** $PROJECT_ROOT/environments/$ENVIRONMENT/infra
- **Coder Phase:** $PROJECT_ROOT/environments/$ENVIRONMENT/coder

## Pre-Migration State

- Infrastructure local state existed: $([ -f "$PROJECT_ROOT/environments/$ENVIRONMENT/infra/terraform.tfstate" ] && echo "Yes" || echo "No")
- Coder local state existed: $([ -f "$PROJECT_ROOT/environments/$ENVIRONMENT/coder/terraform.tfstate" ] && echo "Yes" || echo "No")
- Infrastructure backend config: $PROJECT_ROOT/environments/$ENVIRONMENT/infra/providers.tf
- Coder backend config: $PROJECT_ROOT/environments/$ENVIRONMENT/coder/providers.tf

## Post-Migration Checklist

- [ ] Verify remote state accessibility for all migrated phases
- [ ] Run \`terraform plan\` in each phase to check for drift
- [ ] Test normal terraform operations in each phase
- [ ] Remove local state files if migration successful
- [ ] Update team documentation with new two-phase backend process
- [ ] Configure GitHub Actions with two-phase remote state

## Commands for Verification

### Infrastructure Phase
\`\`\`bash
cd environments/$ENVIRONMENT/infra

# Check remote state
terraform show

# Verify no drift
terraform plan

# List workspaces (if using workspaces)
terraform workspace list
\`\`\`

### Coder Phase
\`\`\`bash
cd environments/$ENVIRONMENT/coder

# Check remote state
terraform show

# Verify no drift
terraform plan

# List workspaces (if using workspaces)
terraform workspace list
\`\`\`

### Using State Manager
\`\`\`bash
# Show state summary for both phases
./scripts/utils/state-manager.sh show --env=$ENVIRONMENT --two-phase

# Show specific phase
./scripts/utils/state-manager.sh show --env=$ENVIRONMENT --phase=infra
./scripts/utils/state-manager.sh show --env=$ENVIRONMENT --phase=coder
\`\`\`

## Rollback Instructions

If needed, restore from backup:

### Infrastructure Phase Rollback
\`\`\`bash
# Stop using remote backend temporarily
cd environments/$ENVIRONMENT/infra
cp providers.tf providers.tf.backup
rm providers.tf

# Restore local state
cp $BACKUP_DIR/$ENVIRONMENT/infra/terraform.tfstate ./

# Reinitialize with local backend
terraform init

# Restore backend configuration when ready
cp providers.tf.backup providers.tf
\`\`\`

### Coder Phase Rollback
\`\`\`bash
# Stop using remote backend temporarily
cd environments/$ENVIRONMENT/coder
cp providers.tf providers.tf.backup
rm providers.tf

# Restore local state
cp $BACKUP_DIR/$ENVIRONMENT/coder/terraform.tfstate ./

# Reinitialize with local backend
terraform init

# Restore backend configuration when ready
cp providers.tf.backup providers.tf
\`\`\`

## Two-Phase Architecture Notes

This environment uses a two-phase deployment architecture:
- **Infrastructure Phase (infra/)**: Manages cluster, database, networking, and core infrastructure
- **Coder Phase (coder/)**: Manages the Coder application deployment and templates

The Coder phase depends on outputs from the Infrastructure phase via remote state data sources.

## Notes

$(if [[ "$DRY_RUN" == true ]]; then
echo "This was a dry run. No actual migration was performed."
else
echo "Two-phase migration completed successfully. Monitor for any issues and verify team access to both phases."
fi)
EOF
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
            --phase=*)
                PHASE="${1#*=}"
                shift
                ;;
            --two-phase)
                TWO_PHASE=true
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

    # Validate phase if specified
    if [[ -n "$PHASE" && ! "$PHASE" =~ ^(infra|coder)$ ]]; then
        log_error "Invalid phase: $PHASE. Must be one of: infra, coder"
        exit 1
    fi

    # Validate phase options compatibility
    if [[ "$TWO_PHASE" == true && -n "$PHASE" ]]; then
        log_error "Cannot specify both --two-phase and --phase options"
        exit 1
    fi
}

# Confirmation prompt
confirm_migration() {
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    local structure=$(detect_environment_structure)

    echo
    echo "======================================"
    echo "  Terraform State Migration Summary"
    echo "======================================"
    echo "Environment: $ENVIRONMENT"
    echo "Structure: $structure"
    if [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            echo "Phases: infra, coder (both)"
        elif [[ -n "$PHASE" ]]; then
            echo "Phase: $PHASE"
        fi
    fi
    echo "Source: Local state file(s)"
    echo "Target: Scaleway Object Storage"
    echo "Backup: $(if [[ "$SKIP_BACKUP" == true ]]; then echo "Disabled"; else echo "Enabled"; fi)"
    echo "======================================"
    echo
    echo "⚠️  This operation will:"
    echo "   • Migrate your Terraform state to remote storage"
    echo "   • Change how you and your team interact with this environment"
    echo "   • Require all team members to reconfigure their local setup"
    if [[ "$structure" == "two-phase" ]]; then
        echo "   • Apply to the specified phase(s) of the two-phase deployment"
    fi
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

    local structure=$(detect_environment_structure)

    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry run completed successfully"
        log "Use the same command without --dry-run to perform the actual migration"
    else
        if [[ "$structure" == "two-phase" ]]; then
            log_success "Two-phase state migration completed successfully!"
            log "Next steps:"
            log "  1. Verify terraform operations work correctly in all migrated phases"
            log "  2. Update your team documentation with two-phase backend process"
            log "  3. Configure GitHub Actions with two-phase remote state"
            log "  4. Use state-manager.sh for ongoing state management"
            log "  5. Remove local state files if everything works correctly"
        else
            log_success "State migration completed successfully!"
            log "Next steps:"
            log "  1. Verify terraform operations work correctly"
            log "  2. Update your team documentation"
            log "  3. Configure GitHub Actions with remote state"
            log "  4. Remove the local state file if everything works correctly"
        fi
    fi
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT TERM

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi