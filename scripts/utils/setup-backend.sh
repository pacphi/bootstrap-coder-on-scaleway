#!/usr/bin/env bash

# Terraform Backend Setup Script for Scaleway Object Storage
# Creates and configures remote state storage infrastructure

set -euo pipefail

# Script constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly TEMP_DIR="${PROJECT_ROOT}/.tmp/backend-setup"

# Default values
ENVIRONMENT=""
DRY_RUN=false
FORCE=false
VERBOSE=false
REGION="fr-par"
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
Usage: $0 --env=<environment> [options]

Setup Terraform backend infrastructure using Scaleway Object Storage with two-phase support.

Required Arguments:
  --env=<env>           Environment to setup (dev, staging, prod, all)

Two-Phase Options:
  --phase=<phase>       Specific phase to setup (infra, coder)
  --two-phase           Setup both phases (infra and coder)

Options:
  --region=<region>     Scaleway region (default: fr-par)
  --dry-run            Show what would be created without making changes
  --force              Skip interactive confirmation prompts
  --verbose, -v        Enable verbose output
  --help, -h           Show this help message

Examples:
  # Legacy single-phase setup
  $0 --env=dev
  $0 --env=all --region=nl-ams

  # Two-phase setup (both phases)
  $0 --env=dev --two-phase
  $0 --env=prod --two-phase --dry-run

  # Phase-specific setup
  $0 --env=dev --phase=infra
  $0 --env=staging --phase=coder

Environment Variables:
  SCW_ACCESS_KEY       Scaleway access key (required)
  SCW_SECRET_KEY       Scaleway secret key (required)
  SCW_DEFAULT_PROJECT_ID   Scaleway project ID (required)
  SCW_DEFAULT_REGION   Default Scaleway region

Two-Phase Architecture:
  This script automatically detects environment structure:
  - Legacy: Single main.tf in environments/<env>/
  - Two-Phase: Separate infra/ and coder/ directories

  For two-phase environments:
  - infra/: Infrastructure backend (terraform-state-coder-<env>, key: infra/terraform.tfstate)
  - coder/: Application backend (terraform-state-coder-<env>, key: coder/terraform.tfstate)

Prerequisites:
  - Terraform >= 1.12.0
  - Valid Scaleway credentials
EOF
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

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
        log_error "Missing Scaleway credentials. Please set:"
        log_error "  SCW_ACCESS_KEY"
        log_error "  SCW_SECRET_KEY"
        log_error "  SCW_DEFAULT_PROJECT_ID"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Detect environment structure
detect_environment_structure() {
    local env="$1"
    local env_dir="${PROJECT_ROOT}/environments/${env}"
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

# Generate bucket name for environment
get_bucket_name() {
    local env="$1"
    echo "terraform-state-coder-${env}"
}

# Create temporary Terraform configuration for backend setup
create_backend_config() {
    local env="$1"
    local backend_dir="${TEMP_DIR}/${env}"
    mkdir -p "$backend_dir"

    # Copy the shared backend-setup configuration
    cp -r "${PROJECT_ROOT}/backend-setup"/* "$backend_dir/"

    # Create terraform.tfvars for environment-specific values
    cat > "${backend_dir}/terraform.tfvars" << EOF
environment = "$env"
region      = "$REGION"
project_id  = "${SCW_DEFAULT_PROJECT_ID}"
managed_by  = "backend-setup-script"
EOF

    echo "$backend_dir"
}

# Create phase-specific backend configuration
create_phase_backend_config() {
    local env="$1"
    local phase="$2"
    local backend_dir="$3"
    local env_dir="${PROJECT_ROOT}/environments/${env}"
    local phase_dir="${env_dir}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log_error "Phase directory not found: $phase_dir"
        return 1
    fi

    # Get the backend configuration from Terraform outputs
    cd "$backend_dir"
    local bucket_name
    bucket_name=$(terraform output -raw bucket_name 2>/dev/null)
    local s3_endpoint
    s3_endpoint=$(terraform output -raw s3_endpoint 2>/dev/null)

    if [[ -z "$bucket_name" ]]; then
        log_error "Failed to get bucket name from Terraform output"
        return 1
    fi

    # Generate phase-specific state key
    local state_key="${env}/${phase}/terraform.tfstate"

    # Create backend.tf with phase-specific configuration
    cat > "${phase_dir}/backend.tf" << EOF
terraform {
  backend "s3" {
    bucket = "${bucket_name}"
    key    = "${state_key}"
    region = "${REGION}"

    # S3-compatibility flags for Scaleway Object Storage
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    # Use Scaleway S3-compatible endpoint
    endpoints = {
      s3 = "${s3_endpoint}"
    }
  }
}
EOF

    log_success "$phase phase backend configuration created: ${phase_dir}/backend.tf"
    log "State key: $state_key"
}

# Create backend configuration for environment
create_environment_backend() {
    local env="$1"
    local backend_dir="$2"
    local env_dir="${PROJECT_ROOT}/environments/${env}"
    local structure=$(detect_environment_structure "$env")

    if [[ ! -d "$env_dir" ]]; then
        log_error "Environment directory not found: $env_dir"
        return 1
    fi

    if [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            # Create backend configs for both phases
            create_phase_backend_config "$env" "infra" "$backend_dir"
            create_phase_backend_config "$env" "coder" "$backend_dir"
        elif [[ -n "$PHASE" ]]; then
            # Create backend config for specific phase
            create_phase_backend_config "$env" "$PHASE" "$backend_dir"
        fi
    elif [[ "$structure" == "legacy" ]]; then
        # Get the backend configuration from Terraform outputs
        cd "$backend_dir"
        local bucket_name
        bucket_name=$(terraform output -raw bucket_name 2>/dev/null)
        local s3_endpoint
        s3_endpoint=$(terraform output -raw s3_endpoint 2>/dev/null)

        if [[ -z "$bucket_name" ]]; then
            log_error "Failed to get bucket name from Terraform output"
            return 1
        fi

        # Generate legacy state key (maintaining backward compatibility)
        local state_key="${env}/terraform.tfstate"

        # Create backend.tf with legacy configuration
        cat > "${env_dir}/backend.tf" << EOF
terraform {
  backend "s3" {
    bucket = "${bucket_name}"
    key    = "${state_key}"
    region = "${REGION}"

    # S3-compatibility flags for Scaleway Object Storage
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    # Use Scaleway S3-compatible endpoint
    endpoints = {
      s3 = "${s3_endpoint}"
    }
  }
}
EOF

        log_success "Backend configuration created: ${env_dir}/backend.tf"
        log "State key: $state_key"
    fi
}

# Setup backend infrastructure for a single environment
setup_environment() {
    local env="$1"
    local structure=$(detect_environment_structure "$env")

    log "Setting up backend infrastructure for environment: $env (structure: $structure)"

    # Validate structure and phase options
    if [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == false && -z "$PHASE" ]]; then
            log_error "Two-phase environment detected but no phase specified"
            log_error "Use --phase=[infra|coder] or --two-phase flag"
            return 1
        fi
    elif [[ "$structure" == "legacy" ]]; then
        if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
            log_error "Legacy single-phase environment detected, but two-phase options specified"
            log_error "Remove --phase or --two-phase flags for legacy environments"
            return 1
        fi
    fi

    local backend_dir
    backend_dir=$(create_backend_config "$env")

    cd "$backend_dir"

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would create the following resources:"
        log "  - S3 bucket: $(get_bucket_name "$env")"
        log "  - Bucket versioning: enabled"
        log "  - Lifecycle policy: 90 day retention (default)"

        if [[ "$structure" == "two-phase" ]]; then
            if [[ "$TWO_PHASE" == true ]]; then
                log "  - Infrastructure backend config: environments/$env/infra/providers.tf"
                log "  - Coder backend config: environments/$env/coder/providers.tf"
            elif [[ -n "$PHASE" ]]; then
                log "  - $PHASE phase backend config: environments/$env/$PHASE/providers.tf"
            fi
        else
            log "  - Backend configuration: environments/$env/backend.tf"
        fi
        return 0
    fi

    # Initialize Terraform
    log "Initializing Terraform for backend setup..."
    if [[ "$VERBOSE" == true ]]; then
        terraform init
    else
        terraform init > /dev/null 2>&1
    fi

    # Plan the infrastructure
    log "Planning backend infrastructure..."
    local plan_file="${backend_dir}/backend.tfplan"
    if [[ "$VERBOSE" == true ]]; then
        terraform plan -out="$plan_file"
    else
        terraform plan -out="$plan_file" > /dev/null 2>&1
    fi

    # Apply the infrastructure
    log "Creating backend infrastructure..."
    if [[ "$VERBOSE" == true ]]; then
        terraform apply "$plan_file"
    else
        terraform apply "$plan_file" > /dev/null 2>&1
    fi

    # Get outputs
    local bucket_name
    bucket_name=$(terraform output -raw bucket_name)
    local s3_endpoint
    s3_endpoint=$(terraform output -raw s3_endpoint)

    log_success "Backend infrastructure created successfully"
    log "  Bucket: $bucket_name"
    log "  Endpoint: $s3_endpoint"

    # Create environment backend configuration
    create_environment_backend "$env" "$backend_dir"

    log_success "Environment $env backend setup completed"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --region=*)
                REGION="${1#*=}"
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

    # Validate region
    if [[ ! "$REGION" =~ ^(fr-par|nl-ams|pl-waw)$ ]]; then
        log_error "Invalid region: $REGION. Must be one of: fr-par, nl-ams, pl-waw"
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
confirm_setup() {
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    local environments
    if [[ "$ENVIRONMENT" == "all" ]]; then
        environments="dev, staging, prod"
    else
        environments="$ENVIRONMENT"
    fi

    echo
    echo "========================================"
    echo "  Terraform Backend Setup Summary"
    echo "========================================"
    echo "Environment(s): $environments"
    echo "Region: $REGION"
    echo "Bucket naming: terraform-state-coder-{env}"
    echo "Versioning: Enabled"

    if [[ "$TWO_PHASE" == true ]]; then
        echo "Architecture: Two-Phase (infra + coder)"
        echo "State keys: infra/terraform.tfstate, coder/terraform.tfstate"
    elif [[ -n "$PHASE" ]]; then
        echo "Architecture: Two-Phase ($PHASE only)"
        echo "State key: $PHASE/terraform.tfstate"
    else
        echo "Architecture: Legacy (single-phase)"
        echo "State key: terraform.tfstate"
    fi

    echo "========================================"
    echo
    echo "This will create:"
    echo "  • Scaleway Object Storage buckets"
    echo "  • Bucket lifecycle policies"
    echo "  • Backend configuration files"
    if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
        echo "  • Two-phase backend configurations"
    fi
    echo
    read -p "Proceed with backend setup? [y/N]: " -r

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Setup cancelled by user"
        exit 0
    fi
}

# Cleanup temporary files
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up temporary files"
    fi
}

# Main execution function
main() {
    # Setup cleanup trap
    trap cleanup EXIT

    log "Starting Terraform backend setup script"

    # Parse command line arguments
    parse_args "$@"

    # Run setup steps
    check_prerequisites
    confirm_setup

    # Create temp directory
    mkdir -p "$TEMP_DIR"

    # Setup environments
    if [[ "$ENVIRONMENT" == "all" ]]; then
        for env in dev staging prod; do
            setup_environment "$env"
        done
    else
        # Validate single environment
        if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
            log_error "Invalid environment: $ENVIRONMENT. Must be one of: dev, staging, prod, all"
            exit 1
        fi
        setup_environment "$ENVIRONMENT"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry run completed successfully"
        log "Use the same command without --dry-run to create the actual infrastructure"
    else
        log_success "Backend setup completed successfully!"
        log
        log "Next steps:"
        if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
            log "  1. Review the created providers.tf files in environments/*/infra/ and environments/*/coder/"
            log "  2. Migrate existing state using: ./scripts/utils/migrate-state.sh --env=<env> --two-phase"
            log "  3. Use state-manager.sh for ongoing two-phase state management"
        else
            log "  1. Review the created backend.tf files in environments/"
            log "  2. Migrate existing state using: ./scripts/utils/migrate-state.sh --env=<env>"
        fi
        log "  3. Update GitHub Actions workflows with remote state support"
        log "  4. Configure team access to the remote state buckets"
        log
        log "Created buckets:"
        if [[ "$ENVIRONMENT" == "all" ]]; then
            for env in dev staging prod; do
                log "  - $(get_bucket_name "$env") (for $env environment)"
            done
        else
            log "  - $(get_bucket_name "$ENVIRONMENT") (for $ENVIRONMENT environment)"
        fi

        if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
            log
            log "Two-Phase Backend Configuration:"
            log "  - Each environment uses a single bucket with phase-specific state keys"
            log "  - Infrastructure phase: <bucket>/infra/terraform.tfstate"
            log "  - Coder phase: <bucket>/coder/terraform.tfstate"
            log "  - Use --phase=<phase> or --two-phase with migration and state management tools"
        fi
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi