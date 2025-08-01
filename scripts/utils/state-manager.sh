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

Manage Terraform state in Scaleway Object Storage with two-phase deployment support.

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

Two-Phase Options:
  --phase=<phase>   Specific phase to manage (infra, coder)
  --two-phase       Operate on both phases (infra and coder)

Other Options:
  --workspace=<ws>  Terraform workspace (default: default)
  --format=<fmt>    Output format (table, json, yaml) - default: table
  --verbose, -v     Enable verbose output
  --help, -h        Show this help message

Examples:
  # Legacy single-phase operations
  $0 show --env=dev
  $0 backup --env=staging

  # Two-phase operations
  $0 show --env=dev --two-phase
  $0 backup --env=prod --two-phase

  # Phase-specific operations
  $0 show --env=dev --phase=infra
  $0 drift --env=prod --phase=coder
  $0 backup --env=staging --phase=infra

  # List all resources in JSON format (both phases)
  $0 list --env=prod --two-phase --format=json

  # Check for configuration drift in Coder phase
  $0 drift --env=dev --phase=coder

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

    # Detect environment structure and validate
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
            # Validate phase-specific backend configurations
            if [[ "$TWO_PHASE" == true || "$PHASE" == "infra" ]]; then
                if [[ ! -f "$env_dir/infra/providers.tf" ]]; then
                    log_error "Infrastructure backend configuration not found: $env_dir/infra/providers.tf"
                    log_error "Run setup-backend.sh first to create remote state infrastructure"
                    exit 1
                fi
            fi
            if [[ "$TWO_PHASE" == true || "$PHASE" == "coder" ]]; then
                if [[ ! -f "$env_dir/coder/providers.tf" ]]; then
                    log_error "Coder backend configuration not found: $env_dir/coder/providers.tf"
                    log_error "Run setup-backend.sh first to create remote state infrastructure"
                    exit 1
                fi
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
        # Check legacy backend configuration
        if [[ ! -f "$env_dir/providers.tf" ]]; then
            log_error "Backend configuration not found: $env_dir/providers.tf"
            log_error "Run setup-backend.sh first to create remote state infrastructure"
            exit 1
        fi
    else
        log_error "Unknown environment structure: $structure"
        exit 1
    fi

    if [[ "$VERBOSE" == true ]]; then
        log_success "Prerequisites check passed"
    fi
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

# Change to environment directory and ensure backend is initialized
setup_environment() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    local structure=$(detect_environment_structure)

    if [[ "$VERBOSE" == true ]]; then
        log "Working in environment: $ENVIRONMENT"
        log "Structure: $structure"
    fi

    # Handle different structures
    if [[ "$structure" == "legacy" ]]; then
        cd "$env_dir"
        if [[ "$VERBOSE" == true ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        # Store the environment directory for later use
        export ENV_DIR="$env_dir"

        if [[ "$VERBOSE" == true ]]; then
            log "Two-phase environment detected"
            if [[ "$TWO_PHASE" == true ]]; then
                log "Operating on both phases"
            elif [[ -n "$PHASE" ]]; then
                log "Operating on phase: $PHASE"
            fi
        fi
    fi

    # Switch workspace if specified (legacy only for now)
    if [[ "$structure" == "legacy" && -n "$WORKSPACE" && "$WORKSPACE" != "default" ]]; then
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

# Show state summary for a specific phase
show_phase_summary() {
    local phase="$1"
    local phase_dir="${ENV_DIR}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    cd "$phase_dir"

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend for $phase phase..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    local state_data
    if ! state_data=$(terraform show -json 2>/dev/null); then
        log_error "Failed to read state for $phase phase. Ensure the state exists and is accessible."
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

    case "$OUTPUT_FORMAT" in
        json)
            cat << EOF
{
  "phase": "$phase",
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

${phase^} Phase State Summary
$(printf '=%.0s' {1..30})
Phase:              ${phase^}
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

# Show state summary
action_show() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Showing two-phase state summary for environment: $ENVIRONMENT"

            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                echo '{"phases": ['
                show_phase_summary "infra"
                echo ','
                show_phase_summary "coder"
                echo ']}'
            else
                echo -e "\n${BLUE}Two-Phase Environment Summary${NC}"
                echo "===================================="
                echo "Environment: $ENVIRONMENT"
                echo "Structure: Two-Phase (Infrastructure + Coder)"
                echo ""
                show_phase_summary "infra"
                show_phase_summary "coder"
            fi
        elif [[ -n "$PHASE" ]]; then
            log "Showing $PHASE phase state summary for environment: $ENVIRONMENT"
            show_phase_summary "$PHASE"
        fi
    fi
}

# List resources for a specific phase
list_phase_resources() {
    local phase="$1"
    local phase_dir="${ENV_DIR}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    cd "$phase_dir"

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend for $phase phase..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    local state_data
    if ! state_data=$(terraform show -json 2>/dev/null); then
        log_error "Failed to read state for $phase phase"
        return 1
    fi

    case "$OUTPUT_FORMAT" in
        json)
            echo "$state_data" | jq --arg phase "$phase" '.values.root_module.resources[] | {
                phase: $phase,
                address: .address,
                type: .type,
                name: .name,
                provider: .provider_name
            }'
            ;;
        *)
            echo
            echo "${phase^} Phase Resources"
            echo "$(printf '=%.0s' {1..30})"
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

# List all resources in state
action_list() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Listing two-phase resources for environment: $ENVIRONMENT"

            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                echo '{"phases": ['
                list_phase_resources "infra"
                echo ','
                list_phase_resources "coder"
                echo ']}'
            else
                echo -e "\n${BLUE}Two-Phase Resource List${NC}"
                echo "============================="
                echo "Environment: $ENVIRONMENT"
                echo ""
                list_phase_resources "infra"
                list_phase_resources "coder"
            fi
        elif [[ -n "$PHASE" ]]; then
            log "Listing $PHASE phase resources for environment: $ENVIRONMENT"
            list_phase_resources "$PHASE"
        fi
    fi
}

# Create backup for a specific phase
backup_phase_state() {
    local phase="$1"
    local backup_dir="$2"
    local phase_dir="${ENV_DIR}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    cd "$phase_dir"

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend for $phase phase..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    local phase_backup_dir="${backup_dir}/${phase}"
    mkdir -p "$phase_backup_dir"

    # Backup state file
    if terraform state pull > "${phase_backup_dir}/terraform.tfstate"; then
        log_success "$phase phase state backed up to: ${phase_backup_dir}/terraform.tfstate"
    else
        log_error "Failed to create $phase phase state backup"
        return 1
    fi

    # Create phase-specific metadata
    cat > "${phase_backup_dir}/metadata.json" << EOF
{
  "phase": "$phase",
  "environment": "$ENVIRONMENT",
  "workspace": "$(terraform workspace show 2>/dev/null || echo "default")",
  "backup_date": "$(date -Iseconds)",
  "terraform_version": "$(terraform version -json | jq -r '.terraform_version')",
  "resource_count": $(terraform show -json 2>/dev/null | jq '.values.root_module.resources | length' || echo 0),
  "backup_method": "state-manager-script"
}
EOF
}

# Create state backup
action_backup() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        mkdir -p "$BACKUP_DIR"

        local timestamp
        timestamp=$(date +%Y%m%d-%H%M%S)
        local backup_name
        local backup_dir

        if [[ "$TWO_PHASE" == true ]]; then
            log "Creating two-phase state backup for environment: $ENVIRONMENT"
            backup_name="${ENVIRONMENT}-two-phase-${timestamp}"
            backup_dir="${BACKUP_DIR}/${backup_name}"
            mkdir -p "$backup_dir"

            # Backup both phases
            backup_phase_state "infra" "$backup_dir"
            backup_phase_state "coder" "$backup_dir"

            # Create combined metadata
            cat > "${backup_dir}/metadata.json" << EOF
{
  "environment": "$ENVIRONMENT",
  "structure": "two-phase",
  "phases": ["infra", "coder"],
  "backup_date": "$(date -Iseconds)",
  "backup_method": "state-manager-script"
}
EOF
        elif [[ -n "$PHASE" ]]; then
            log "Creating $PHASE phase state backup for environment: $ENVIRONMENT"
            backup_name="${ENVIRONMENT}-${PHASE}-${timestamp}"
            backup_dir="${BACKUP_DIR}/${backup_name}"
            mkdir -p "$backup_dir"

            backup_phase_state "$PHASE" "$backup_dir"
        fi

        # Create readme for two-phase backup
        cat > "${backup_dir}/README.md" << EOF
# Two-Phase State Backup: $backup_name

**Environment:** $ENVIRONMENT
**Structure:** Two-Phase
**Date:** $(date)

## Files

- \`infra/terraform.tfstate\` - Infrastructure phase state backup
- \`infra/metadata.json\` - Infrastructure phase metadata
- \`coder/terraform.tfstate\` - Coder phase state backup
- \`coder/metadata.json\` - Coder phase metadata
- \`metadata.json\` - Combined backup metadata
- \`README.md\` - This file

## Restore Instructions

To restore this two-phase state backup:

\`\`\`bash
# Restore both phases
./scripts/utils/state-manager.sh restore --env=$ENVIRONMENT --backup=$backup_name --two-phase

# Or restore individual phases
./scripts/utils/state-manager.sh restore --env=$ENVIRONMENT --backup=$backup_name --phase=infra
./scripts/utils/state-manager.sh restore --env=$ENVIRONMENT --backup=$backup_name --phase=coder
\`\`\`

## Verification

After restore, verify with:
\`\`\`bash
# Check both phases
./scripts/utils/state-manager.sh show --env=$ENVIRONMENT --two-phase
\`\`\`
EOF

        log_success "Backup created: $backup_name"
        echo "Location: $backup_dir"
    fi
}

# Restore state from backup for a specific phase
restore_phase_state() {
    local phase="$1"
    local backup_dir="$2"
    local phase_dir="${ENV_DIR}/${phase}"
    local phase_backup_dir="${backup_dir}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    if [[ ! -f "${phase_backup_dir}/terraform.tfstate" ]]; then
        log_error "$phase phase state file not found in backup: ${phase_backup_dir}/terraform.tfstate"
        return 1
    fi

    cd "$phase_dir"

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend for $phase phase..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    log "Restoring $phase phase state from backup: $BACKUP_NAME"

    if terraform state push "${phase_backup_dir}/terraform.tfstate"; then
        log_success "$phase phase state restored successfully"
    else
        log_error "Failed to restore $phase phase state"
        return 1
    fi
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

    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            # Check if both phase backups exist
            if [[ ! -f "${backup_dir}/infra/terraform.tfstate" ]] || [[ ! -f "${backup_dir}/coder/terraform.tfstate" ]]; then
                log_error "Two-phase backup not found or incomplete"
                log_error "Expected: ${backup_dir}/infra/terraform.tfstate and ${backup_dir}/coder/terraform.tfstate"
                return 1
            fi

            log_warning "This will replace the current two-phase state with the backup"
            log_warning "Backup: $BACKUP_NAME"
            log_warning "Environment: $ENVIRONMENT"
            log_warning "Phases: infra, coder"

            read -p "Continue with two-phase restore? [y/N]: " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Restore cancelled"
                return 0
            fi

            # Restore both phases
            restore_phase_state "infra" "$backup_dir"
            restore_phase_state "coder" "$backup_dir"

            log_success "Two-phase state restored successfully"
            log "Run './scripts/utils/state-manager.sh show --env=$ENVIRONMENT --two-phase' to verify"
        elif [[ -n "$PHASE" ]]; then
            restore_phase_state "$PHASE" "$backup_dir"
            log "Run 'cd environments/$ENVIRONMENT/$PHASE && terraform plan' to verify the restored state"
        fi
    fi
}

# Inspect state for a specific phase
inspect_phase_state() {
    local phase="$1"
    local phase_dir="${ENV_DIR}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    cd "$phase_dir"

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend for $phase phase..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    local state_data
    if ! state_data=$(terraform show -json 2>/dev/null); then
        log_error "Failed to read state for $phase phase"
        return 1
    fi

    case "$OUTPUT_FORMAT" in
        json)
            echo "$state_data" | jq --arg phase "$phase" '. + {"phase": $phase}'
            ;;
        *)
            echo
            echo "${phase^} Phase State Inspection"
            echo "$(printf '=%.0s' {1..35})"

            # Basic info
            echo "Phase: ${phase^}"
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

# Inspect state in detail
action_inspect() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Inspecting two-phase state for environment: $ENVIRONMENT"

            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                echo '{"phases": ['
                inspect_phase_state "infra"
                echo ','
                inspect_phase_state "coder"
                echo ']}'
            else
                echo -e "\n${BLUE}Two-Phase State Inspection${NC}"
                echo "================================"
                echo "Environment: $ENVIRONMENT"
                echo ""
                inspect_phase_state "infra"
                inspect_phase_state "coder"
            fi
        elif [[ -n "$PHASE" ]]; then
            log "Inspecting $PHASE phase state for environment: $ENVIRONMENT"
            inspect_phase_state "$PHASE"
        fi
    fi
}

# Check for configuration drift in a specific phase
check_phase_drift() {
    local phase="$1"
    local phase_dir="${ENV_DIR}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    cd "$phase_dir"

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend for $phase phase..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    log "Checking for configuration drift in $phase phase..."

    local plan_output
    local plan_exit_code

    if plan_output=$(terraform plan -detailed-exitcode 2>&1); then
        plan_exit_code=$?
    else
        plan_exit_code=$?
    fi

    case $plan_exit_code in
        0)
            log_success "No drift detected in $phase phase - infrastructure matches configuration"
            return 0
            ;;
        1)
            log_error "Error running terraform plan for $phase phase"
            echo "$plan_output"
            return 1
            ;;
        2)
            log_warning "Configuration drift detected in $phase phase"
            case "$OUTPUT_FORMAT" in
                json)
                    echo '{"phase": "'$phase'", "drift_detected": true, "plan_output": "'"$(echo "$plan_output" | sed 's/"/\\"/g' | tr '\n' ' ')"'"}'
                    ;;
                *)
                    echo
                    echo "${phase^} Phase Drift Details:"
                    echo "$(printf '=%.0s' {1..30})"
                    echo "$plan_output"
                    echo
                    log_warning "Run 'cd environments/$ENVIRONMENT/$phase && terraform apply' to fix drift"
                    ;;
            esac
            return 2
            ;;
    esac
}

# Check for configuration drift
action_drift() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Checking for configuration drift in two-phase environment: $ENVIRONMENT"

            local infra_drift=0
            local coder_drift=0

            if [[ "$OUTPUT_FORMAT" == "json" ]]; then
                echo '{"phases": ['
                check_phase_drift "infra"
                infra_drift=$?
                echo ','
                check_phase_drift "coder"
                coder_drift=$?
                echo ']}'
            else
                echo -e "\n${BLUE}Two-Phase Drift Check${NC}"
                echo "========================"
                echo "Environment: $ENVIRONMENT"
                echo ""
                check_phase_drift "infra"
                infra_drift=$?
                check_phase_drift "coder"
                coder_drift=$?

                echo
                if [[ $infra_drift -eq 0 ]] && [[ $coder_drift -eq 0 ]]; then
                    log_success "No drift detected in any phase"
                elif [[ $infra_drift -eq 2 ]] || [[ $coder_drift -eq 2 ]]; then
                    log_warning "Configuration drift detected in one or more phases"
                    log "Use 'terraform apply' in the appropriate phase directories to fix drift"
                else
                    log_error "Errors detected during drift check"
                    return 1
                fi
            fi
        elif [[ -n "$PHASE" ]]; then
            check_phase_drift "$PHASE"
        fi
    fi
}

# Clean up old state versions
action_cleanup() {
    local structure=$(detect_environment_structure)

    log_warning "State cleanup functionality requires Scaleway CLI integration"
    log "This feature will clean up old state versions in Object Storage"
    log "Manual cleanup can be done through Scaleway console or CLI"

    # For now, just show information about state versions
    if [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Current two-phase state info:"
        elif [[ -n "$PHASE" ]]; then
            log "Current $PHASE phase state info:"
        fi
    else
        log "Current state info:"
    fi

    action_show
}

# Manage workspaces for a specific phase
manage_phase_workspaces() {
    local phase="$1"
    local phase_dir="${ENV_DIR}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    cd "$phase_dir"

    # Initialize backend if needed
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform/terraform.tfstate" ]]; then
        if [[ "$VERBOSE" == true ]]; then
            log "Initializing Terraform backend for $phase phase..."
            terraform init
        else
            terraform init > /dev/null 2>&1
        fi
    fi

    case "${WORKSPACE_ACTION:-list}" in
        list)
            echo
            echo "${phase^} Phase Available Workspaces:"
            echo "$(printf '=%.0s' {1..40})"
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
            log_success "Created workspace in $phase phase: $WORKSPACE"
            ;;
        select)
            if [[ -z "$WORKSPACE" ]]; then
                log_error "Workspace name required. Use --workspace=<name>"
                return 1
            fi
            terraform workspace select "$WORKSPACE"
            log_success "Switched to workspace in $phase phase: $WORKSPACE"
            ;;
        delete)
            if [[ -z "$WORKSPACE" ]]; then
                log_error "Workspace name required. Use --workspace=<name>"
                return 1
            fi
            terraform workspace delete "$WORKSPACE"
            log_success "Deleted workspace in $phase phase: $WORKSPACE"
            ;;
    esac
}

# Manage workspaces
action_workspaces() {
    local structure=$(detect_environment_structure)

    if [[ "$structure" == "legacy" ]]; then
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
    elif [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            log "Managing workspaces for two-phase environment: $ENVIRONMENT"

            echo -e "\n${BLUE}Two-Phase Workspace Management${NC}"
            echo "==============================="
            echo "Environment: $ENVIRONMENT"

            manage_phase_workspaces "infra"
            manage_phase_workspaces "coder"
        elif [[ -n "$PHASE" ]]; then
            log "Managing workspaces for $PHASE phase in environment: $ENVIRONMENT"
            manage_phase_workspaces "$PHASE"
        fi
    fi
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
            --phase=*)
                PHASE="${1#*=}"
                shift
                ;;
            --two-phase)
                TWO_PHASE=true
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