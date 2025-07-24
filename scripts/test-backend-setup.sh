#!/usr/bin/env bash

# Test script for backend setup configuration
# This script validates that the backend setup works correctly

set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    echo -e "${GREEN}[TEST]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v terraform &> /dev/null; then
        error "Terraform not found"
        return 1
    fi

    if [[ -z "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
        warning "SCW_DEFAULT_PROJECT_ID not set - using valid UUID format"
        export SCW_DEFAULT_PROJECT_ID="00000000-0000-0000-0000-000000000000"
    fi

    log "Prerequisites OK"
}

# Test backend-setup configuration
test_backend_setup() {
    log "Testing backend-setup configuration"

    # Test in-place instead of copying to avoid module path issues
    cd backend-setup

    # Test initialization
    log "Testing terraform init..."
    if terraform init -backend=false; then
        log "✅ Terraform init successful"
    else
        error "❌ Terraform init failed"
        return 1
    fi

    # Test validation
    log "Testing terraform validate..."
    if terraform validate; then
        log "✅ Terraform validate successful"
    else
        error "❌ Terraform validate failed"
        return 1
    fi

    # Test plan with variables
    log "Testing terraform plan..."
    cat > test.tfvars <<EOF
environment = "dev"
region      = "fr-par"
project_id  = "${SCW_DEFAULT_PROJECT_ID}"
managed_by  = "test-script"
EOF

    if terraform plan -var-file=test.tfvars -out=/dev/null; then
        log "✅ Terraform plan successful"
    else
        error "❌ Terraform plan failed"
        return 1
    fi

    # Return to original directory
    cd - > /dev/null

    log "✅ All backend-setup tests passed"
}

# Test setup-backend.sh integration
test_setup_script() {
    log "Testing setup-backend.sh integration..."

    if [[ ! -f "scripts/utils/setup-backend.sh" ]]; then
        error "setup-backend.sh not found"
        return 1
    fi

    # Test dry-run
    log "Testing dry-run mode..."
    if ./scripts/utils/setup-backend.sh --env=dev --dry-run; then
        log "✅ Dry-run test passed"
    else
        error "❌ Dry-run test failed"
        return 1
    fi
}

# Main
main() {
    log "Starting backend setup tests..."

    check_prerequisites || exit 1
    test_backend_setup || exit 1
    test_setup_script || exit 1

    log "✅ All tests completed successfully!"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi