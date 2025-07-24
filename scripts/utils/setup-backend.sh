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

Setup Terraform backend infrastructure using Scaleway Object Storage.

Required Arguments:
  --env=<env>           Environment to setup (dev, staging, prod, all)

Options:
  --region=<region>     Scaleway region (default: fr-par)
  --dry-run            Show what would be created without making changes
  --force              Skip interactive confirmation prompts
  --verbose, -v        Enable verbose output
  --help, -h           Show this help message

Examples:
  # Setup backend for dev environment
  $0 --env=dev

  # Setup all environments with custom region
  $0 --env=all --region=nl-ams

  # Dry run to preview infrastructure
  $0 --env=prod --dry-run

Environment Variables:
  SCW_ACCESS_KEY       Scaleway access key (required)
  SCW_SECRET_KEY       Scaleway secret key (required)
  SCW_DEFAULT_PROJECT_ID   Scaleway project ID (required)
  SCW_DEFAULT_REGION   Default Scaleway region

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

# Create backend configuration for environment
create_environment_backend() {
    local env="$1"
    local backend_dir="$2"
    local env_dir="${PROJECT_ROOT}/environments/${env}"

    if [[ ! -d "$env_dir" ]]; then
        log_error "Environment directory not found: $env_dir"
        return 1
    fi

    # Get the backend configuration content from Terraform output
    cd "$backend_dir"
    local backend_content
    backend_content=$(terraform output -raw backend_tf_content 2>/dev/null)

    if [[ -z "$backend_content" ]]; then
        log_error "Failed to get backend configuration from Terraform output"
        return 1
    fi

    # Write the backend configuration
    echo "$backend_content" > "${env_dir}/backend.tf"

    log_success "Backend configuration created: ${env_dir}/backend.tf"
}

# Setup backend infrastructure for a single environment
setup_environment() {
    local env="$1"

    log "Setting up backend infrastructure for environment: $env"

    local backend_dir
    backend_dir=$(create_backend_config "$env")

    cd "$backend_dir"

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would create the following resources:"
        log "  - S3 bucket: $(get_bucket_name "$env")"
        log "  - Bucket versioning: enabled"
        log "  - Lifecycle policy: 90 day retention (default)"
        log "  - Backend configuration: environments/$env/backend.tf"
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
    echo "========================================"
    echo
    echo "This will create:"
    echo "  • Scaleway Object Storage buckets"
    echo "  • Bucket lifecycle policies"
    echo "  • Backend configuration files"
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
        log "  1. Review the created backend.tf files in environments/"
        log "  2. Migrate existing state using: ./scripts/utils/migrate-state.sh --env=<env>"
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
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi