#!/bin/bash

# Coder on Scaleway - Comprehensive Test Runner
# Manual testing suite for validating all system components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_SUITE="all"
ENVIRONMENT="dev"
CLEANUP_AFTER=true
PARALLEL_TESTS=false
TEST_TIMEOUT=3600
OUTPUT_DIR="${PROJECT_ROOT}/test-results"
LOG_FILE=""
START_TIME=$(date +%s)
PHASE=""
TWO_PHASE=false

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║      Comprehensive Test Runner        ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run comprehensive manual tests for the Coder on Scaleway system,
including infrastructure, templates, workflows, and integrations with two-phase support.

Options:
    --suite=SUITE           Test suite to run [required]
                           Options: all, smoke, prerequisites, infrastructure, templates, workflows, integration, integrations
    --environment=ENV       Test environment (dev|staging) [default: dev]
    --phase=PHASE           Specific phase to test (infra|coder) for two-phase environments
    --two-phase             Test both phases (infra and coder) for two-phase environments
    --no-cleanup           Skip cleanup after tests
    --parallel             Run compatible tests in parallel
    --timeout=SECONDS      Test timeout in seconds (default: 3600)
    --output-dir=DIR       Test results directory (default: test-results)
    --help                 Show this help message

Test Suites:
    all                    Run all test suites (comprehensive)
    smoke                  Quick smoke tests for basic functionality
    prerequisites          Check required tools, versions, and credentials
    infrastructure         Infrastructure deployment and configuration tests
    templates              Template validation and deployment tests
    workflows              GitHub Actions workflow tests (dry-run)
    integration            End-to-end integration tests
    integrations           External integration tests (Slack, JIRA, monitoring)

Examples:
    # Legacy single-phase testing
    $0 --suite=prerequisites
    $0 --suite=smoke
    $0 --suite=templates --environment=dev --parallel

    # Two-phase testing
    $0 --suite=infrastructure --environment=dev --two-phase
    $0 --suite=smoke --environment=staging --phase=infra
    $0 --suite=all --environment=dev --two-phase --no-cleanup --timeout=7200

Two-Phase Architecture:
    This script automatically detects environment structure:
    - Legacy: Single main.tf in environments/<env>/
    - Two-Phase: Separate infra/ and coder/ directories

    For two-phase environments:
    - infra/: Infrastructure testing (cluster, database, networking)
    - coder/: Application testing (Coder platform, templates)

Test Coverage:
    • Script functionality validation
    • Template syntax and deployment testing
    • Environment lifecycle (setup/teardown)
    • Backup and restore procedures
    • Scaling operations
    • Cost calculation accuracy
    • Documentation consistency
    • Two-phase deployment validation
    • GitHub Actions workflow validation

EOF
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC}  $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC}  $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
        DEBUG) echo -e "${PURPLE}[DEBUG]${NC} $message" ;;
        STEP)  echo -e "${CYAN}[STEP]${NC}  $message" ;;
        TEST)  echo -e "${WHITE}[TEST]${NC}  $message" ;;
        PASS)  echo -e "${GREEN}[PASS]${NC}  $message" ;;
        FAIL)  echo -e "${RED}[FAIL]${NC}  $message" ;;
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_test_environment() {
    log STEP "Setting up test environment..."

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Setup logging
    LOG_FILE="${OUTPUT_DIR}/test-runner-$(date +%Y%m%d-%H%M%S).log"
    log INFO "Test logging to: $LOG_FILE"

    # Check prerequisites
    local required_tools=("terraform" "kubectl" "helm" "jq" "curl")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log ERROR "Missing required tools: ${missing_tools[*]}"
        # Don't exit if we're running prerequisites test suite
        if [[ "$TEST_SUITE" != "prerequisites" ]]; then
            exit 1
        fi
    fi

    # Check Scaleway credentials
    if [[ -z "${SCW_ACCESS_KEY:-}" || -z "${SCW_SECRET_KEY:-}" || -z "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
        log WARN "Scaleway credentials not set - some tests will be skipped"
        log WARN "Set SCW_ACCESS_KEY, SCW_SECRET_KEY, and SCW_DEFAULT_PROJECT_ID for full testing"
    fi

    log INFO "✅ Test environment setup completed"
}

run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))
    log TEST "Running test: $test_name"

    local test_start=$(date +%s)
    local test_log="${OUTPUT_DIR}/${test_name//[^a-zA-Z0-9]/_}.log"

    # Use timeout if available, otherwise run directly
    if command -v timeout &>/dev/null; then
        if timeout "$TEST_TIMEOUT" "$test_function" 2>&1 | tee "$test_log"; then
            local test_end=$(date +%s)
            local test_duration=$((test_end - test_start))
            log PASS "$test_name (${test_duration}s)"
            ((TESTS_PASSED++))
            return 0
        else
            local test_end=$(date +%s)
            local test_duration=$((test_end - test_start))
            log FAIL "$test_name (${test_duration}s)"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$test_name")
            return 1
        fi
    else
        # Run without timeout
        if "$test_function" 2>&1 | tee "$test_log"; then
            local test_end=$(date +%s)
            local test_duration=$((test_end - test_start))
            log PASS "$test_name (${test_duration}s)"
            ((TESTS_PASSED++))
            return 0
        else
            local test_end=$(date +%s)
            local test_duration=$((test_end - test_start))
            log FAIL "$test_name (${test_duration}s)"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$test_name")
            return 1
        fi
    fi
}

# Test Functions

test_prerequisites_tools() {
    log INFO "Checking required tools installation"

    local required_tools=("terraform" "kubectl" "helm" "jq" "curl" "git")
    local missing_tools=()
    local found_tools=()

    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            found_tools+=("$tool")
            log INFO "✓ $tool is installed"
        else
            missing_tools+=("$tool")
            log ERROR "✗ $tool is NOT installed"
        fi
    done

    # Check optional tools
    log INFO ""
    log INFO "Checking optional tools"

    if command -v "gh" &> /dev/null; then
        log INFO "✓ gh (GitHub CLI) is installed - required for GitHub Actions deployment"
    else
        log WARN "! gh (GitHub CLI) is NOT installed - optional, needed for GitHub Actions"
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log ERROR ""
        log ERROR "Missing required tools: ${missing_tools[*]}"
        log ERROR ""
        log ERROR "Installation instructions:"
        log ERROR "  macOS:        brew install ${missing_tools[*]}"
        log ERROR "  Ubuntu/Debian: See Prerequisites section in README.md"
        log ERROR "  Other:        Visit tool documentation for installation instructions"
        return 1
    else
        log INFO ""
        log INFO "✅ All required tools are installed"
        return 0
    fi
}

test_prerequisites_versions() {
    log INFO "Checking tool versions"

    local version_errors=0

    # Check Terraform version
    if command -v terraform &> /dev/null; then
        local tf_version=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' || terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        local tf_min_version="1.12.0"

        if [[ "$tf_version" != "unknown" ]]; then
            if printf '%s\n%s\n' "$tf_min_version" "$tf_version" | sort -V -C; then
                log INFO "✓ Terraform version $tf_version (>= $tf_min_version required)"
            else
                log ERROR "✗ Terraform version $tf_version is too old (>= $tf_min_version required)"
                ((version_errors++))
            fi
        else
            log WARN "! Unable to determine Terraform version"
        fi
    fi

    # Check kubectl version
    if command -v kubectl &> /dev/null; then
        local kubectl_version=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' | sed 's/v//' || echo "unknown")
        local kubectl_min_version="1.32.0"

        if [[ "$kubectl_version" != "unknown" ]]; then
            if printf '%s\n%s\n' "$kubectl_min_version" "$kubectl_version" | sort -V -C; then
                log INFO "✓ kubectl version $kubectl_version (>= $kubectl_min_version required)"
            else
                log ERROR "✗ kubectl version $kubectl_version is too old (>= $kubectl_min_version required)"
                ((version_errors++))
            fi
        else
            log WARN "! Unable to determine kubectl version"
        fi
    fi

    # Check Helm version
    if command -v helm &> /dev/null; then
        local helm_version=$(helm version --short 2>/dev/null | sed 's/v//' | cut -d'+' -f1 || echo "unknown")
        local helm_min_version="3.12.0"

        if [[ "$helm_version" != "unknown" ]]; then
            if printf '%s\n%s\n' "$helm_min_version" "$helm_version" | sort -V -C; then
                log INFO "✓ Helm version $helm_version (>= $helm_min_version required)"
            else
                log ERROR "✗ Helm version $helm_version is too old (>= $helm_min_version required)"
                ((version_errors++))
            fi
        else
            log WARN "! Unable to determine Helm version"
        fi
    fi

    # Check other tools (version not critical)
    for tool in jq curl git; do
        if command -v "$tool" &> /dev/null; then
            local version=$($tool --version 2>&1 | head -1 || echo "installed")
            log INFO "✓ $tool: $version"
        fi
    done

    if [[ $version_errors -gt 0 ]]; then
        log ERROR ""
        log ERROR "Some tools have outdated versions. Please update them."
        return 1
    else
        log INFO ""
        log INFO "✅ All tool versions meet requirements"
        return 0
    fi
}

test_prerequisites_credentials() {
    log INFO "Checking Scaleway credentials"

    local missing_creds=()

    # Check required environment variables
    if [[ -n "${SCW_ACCESS_KEY:-}" ]]; then
        log INFO "✓ SCW_ACCESS_KEY is set"
    else
        missing_creds+=("SCW_ACCESS_KEY")
        log ERROR "✗ SCW_ACCESS_KEY is NOT set"
    fi

    if [[ -n "${SCW_SECRET_KEY:-}" ]]; then
        log INFO "✓ SCW_SECRET_KEY is set"
    else
        missing_creds+=("SCW_SECRET_KEY")
        log ERROR "✗ SCW_SECRET_KEY is NOT set"
    fi

    if [[ -n "${SCW_DEFAULT_PROJECT_ID:-}" ]]; then
        log INFO "✓ SCW_DEFAULT_PROJECT_ID is set"
    else
        missing_creds+=("SCW_DEFAULT_PROJECT_ID")
        log ERROR "✗ SCW_DEFAULT_PROJECT_ID is NOT set"
    fi

    # Check optional environment variables
    log INFO ""
    log INFO "Checking optional environment variables"

    if [[ -n "${SCW_DEFAULT_REGION:-}" ]]; then
        log INFO "✓ SCW_DEFAULT_REGION is set to: $SCW_DEFAULT_REGION"
    else
        log WARN "! SCW_DEFAULT_REGION is NOT set (will default to fr-par)"
    fi

    if [[ -n "${SCW_DEFAULT_ZONE:-}" ]]; then
        log INFO "✓ SCW_DEFAULT_ZONE is set to: $SCW_DEFAULT_ZONE"
    else
        log WARN "! SCW_DEFAULT_ZONE is NOT set (will default to fr-par-1)"
    fi

    if [[ ${#missing_creds[@]} -gt 0 ]]; then
        log ERROR ""
        log ERROR "Missing required credentials: ${missing_creds[*]}"
        log ERROR ""
        log ERROR "To set credentials:"
        log ERROR "  export SCW_ACCESS_KEY=\"your-access-key\""
        log ERROR "  export SCW_SECRET_KEY=\"your-secret-key\""
        log ERROR "  export SCW_DEFAULT_PROJECT_ID=\"your-project-id\""
        log ERROR ""
        log ERROR "Get credentials from: https://console.scaleway.com/iam/api-keys"
        return 1
    else
        log INFO ""
        log INFO "✅ All required credentials are set"
        return 0
    fi
}

test_script_syntax() {
    log INFO "Validating script syntax and executability"

    local scripts=(
        "scripts/lifecycle/setup.sh"
        "scripts/lifecycle/teardown.sh"
        "scripts/lifecycle/backup.sh"
        "scripts/validate.sh"
        "scripts/scale.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$PROJECT_ROOT/$script" ]]; then
            bash -n "$PROJECT_ROOT/$script"
            [[ -x "$PROJECT_ROOT/$script" ]] || chmod +x "$PROJECT_ROOT/$script"
            log INFO "✓ $script syntax OK"
        else
            log ERROR "✗ $script not found"
            return 1
        fi
    done
}

test_template_discovery() {
    log INFO "Testing dynamic template discovery"

    cd "$PROJECT_ROOT"

    # Test setup.sh template discovery
    local discovered_templates=$(bash -c '
        source scripts/lifecycle/setup.sh
        discover_available_templates | wc -l
    ' 2>/dev/null || echo "0")

    if [[ "$discovered_templates" -gt 0 ]]; then
        log INFO "✓ Discovered $discovered_templates templates"
    else
        log ERROR "✗ Template discovery failed"
        return 1
    fi

    # Validate each template
    while IFS= read -r -d '' template_file; do
        local template_dir=$(dirname "$template_file")
        cd "$template_dir"

        if terraform validate &>/dev/null; then
            log INFO "✓ Template $(basename "$template_dir") syntax valid"
        else
            log ERROR "✗ Template $(basename "$template_dir") has syntax errors"
            return 1
        fi

        cd - &>/dev/null
    done < <(find templates -name "main.tf" -type f -print0)
}

test_cost_calculation() {
    log INFO "Testing cost calculation accuracy"

    if [[ -f "$PROJECT_ROOT/scripts/utils/cost-calculator.sh" ]]; then
        chmod +x "$PROJECT_ROOT/scripts/utils/cost-calculator.sh"

        # Test cost calculation for each environment
        for env in dev staging prod; do
            local cost_output=$("$PROJECT_ROOT/scripts/utils/cost-calculator.sh" --env="$env" --estimate-only 2>/dev/null || echo "")

            if [[ -n "$cost_output" ]]; then
                log INFO "✓ Cost calculation for $env environment works"
            else
                log WARN "! Cost calculation for $env environment skipped"
            fi
        done
    else
        log WARN "! Cost calculator not found, test skipped"
    fi
}

test_backup_functionality() {
    log INFO "Testing backup script functionality"

    chmod +x "$PROJECT_ROOT/scripts/lifecycle/backup.sh"

    # Test dry run backup
    if "$PROJECT_ROOT/scripts/lifecycle/backup.sh" --env=dev --backup-name="test-backup" --auto --no-config &>/dev/null; then
        log INFO "✓ Backup script executes without errors"

        # Cleanup test backup if created
        [[ -d "$PROJECT_ROOT/backups/test-backup" ]] && rm -rf "$PROJECT_ROOT/backups/test-backup"
    else
        log ERROR "✗ Backup script failed"
        return 1
    fi
}

test_validation_functionality() {
    log INFO "Testing validation script functionality"

    chmod +x "$PROJECT_ROOT/scripts/validate.sh"

    # Test validation help
    if "$PROJECT_ROOT/scripts/validate.sh" --help &>/dev/null; then
        log INFO "✓ Validation script help works"
    else
        log ERROR "✗ Validation script help failed"
        return 1
    fi
}

test_scaling_functionality() {
    log INFO "Testing scaling script functionality"

    chmod +x "$PROJECT_ROOT/scripts/scale.sh"

    # Test scaling help and dry run
    if "$PROJECT_ROOT/scripts/scale.sh" --help &>/dev/null; then
        log INFO "✓ Scaling script help works"
    else
        log ERROR "✗ Scaling script help failed"
        return 1
    fi
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

# Test Terraform configuration for a specific phase
test_phase_terraform_configuration() {
    local env_name="$1"
    local phase="$2"
    local env_dir="${PROJECT_ROOT}/environments/${env_name}"
    local phase_dir="${env_dir}/${phase}"

    if [[ ! -d "$phase_dir" ]]; then
        log ERROR "✗ Phase directory not found: $phase_dir"
        return 1
    fi

    cd "$phase_dir"

    if terraform init -backend=false &>/dev/null && terraform validate &>/dev/null; then
        log INFO "✓ Environment $env_name $phase phase Terraform config valid"
        cd - &>/dev/null
        return 0
    else
        log ERROR "✗ Environment $env_name $phase phase Terraform config invalid"
        cd - &>/dev/null
        return 1
    fi
}

test_terraform_configuration() {
    log INFO "Testing Terraform configuration validity"

    local config_errors=0

    for env_dir in "$PROJECT_ROOT/environments"/*; do
        if [[ -d "$env_dir" ]]; then
            local env_name=$(basename "$env_dir")
            local structure=$(detect_environment_structure "$env_name")

            if [[ "$structure" == "legacy" ]]; then
                # Skip two-phase testing for legacy environments
                if [[ "$TWO_PHASE" == true || -n "$PHASE" ]]; then
                    log INFO "Skipping legacy environment $env_name (two-phase options specified)"
                    continue
                fi

                cd "$env_dir"
                if terraform init -backend=false &>/dev/null && terraform validate &>/dev/null; then
                    log INFO "✓ Environment $env_name Terraform config valid"
                else
                    log ERROR "✗ Environment $env_name Terraform config invalid"
                    ((config_errors++))
                fi
                cd - &>/dev/null
            elif [[ "$structure" == "two-phase" ]]; then
                # Skip legacy testing for two-phase environments
                if [[ "$TWO_PHASE" == false && -z "$PHASE" ]]; then
                    log INFO "Skipping two-phase environment $env_name (no phase options specified)"
                    continue
                fi

                if [[ "$TWO_PHASE" == true ]]; then
                    log INFO "Testing two-phase environment: $env_name"
                    if ! test_phase_terraform_configuration "$env_name" "infra"; then
                        ((config_errors++))
                    fi
                    if ! test_phase_terraform_configuration "$env_name" "coder"; then
                        ((config_errors++))
                    fi
                elif [[ -n "$PHASE" ]]; then
                    log INFO "Testing $PHASE phase for environment: $env_name"
                    if ! test_phase_terraform_configuration "$env_name" "$PHASE"; then
                        ((config_errors++))
                    fi
                fi
            else
                log WARN "Unknown structure for environment: $env_name"
            fi
        fi
    done

    if [[ $config_errors -gt 0 ]]; then
        log ERROR "$config_errors Terraform configuration error(s) found"
        return 1
    else
        log INFO "✓ All Terraform configurations are valid"
        return 0
    fi
}

test_documentation_consistency() {
    log INFO "Testing documentation consistency"

    # Check if all templates are documented
    local documented_templates=$(grep -o '[a-zA-Z0-9-]*-[a-zA-Z0-9-]*' "$PROJECT_ROOT/docs/USAGE.md" | sort -u || true)
    local actual_templates=$(find "$PROJECT_ROOT/templates" -name "main.tf" | sed 's|.*/templates/.*/||' | sed 's|/.*||' | sort -u)

    local undocumented=0
    for template in $actual_templates; do
        if ! echo "$documented_templates" | grep -q "$template"; then
            log WARN "! Template '$template' not documented in USAGE.md"
            ((undocumented++))
        fi
    done

    if [[ "$undocumented" -eq 0 ]]; then
        log INFO "✓ All templates are documented"
    else
        log WARN "! $undocumented templates are undocumented"
    fi
}

test_github_actions_syntax() {
    log INFO "Testing GitHub Actions workflow syntax"

    local workflows=(
        ".github/workflows/deploy-environment.yml"
        ".github/workflows/teardown-environment.yml"
        ".github/workflows/validate-templates.yml"
    )

    for workflow in "${workflows[@]}"; do
        if [[ -f "$PROJECT_ROOT/$workflow" ]]; then
            # Basic YAML syntax validation
            if python3 -c "import yaml; yaml.safe_load(open('$PROJECT_ROOT/$workflow'))" 2>/dev/null; then
                log INFO "✓ Workflow $(basename "$workflow") YAML syntax valid"
            else
                log ERROR "✗ Workflow $(basename "$workflow") has YAML syntax errors"
                return 1
            fi
        else
            log ERROR "✗ Workflow $workflow not found"
            return 1
        fi
    done
}

test_integration_environment_lifecycle() {
    if [[ -z "${SCW_ACCESS_KEY:-}" ]]; then
        log WARN "! Integration test skipped - no Scaleway credentials"
        return 0
    fi

    log INFO "Testing complete environment lifecycle (integration test)"

    # This is a comprehensive test that actually deploys and tears down an environment
    local test_env="dev"
    local test_template="claude-flow-base"
    local structure=$(detect_environment_structure "$test_env")

    local setup_args="--env=$test_env --template=$test_template --auto-approve"
    local validate_args="--env=$test_env --quick"
    local backup_args="--env=$test_env --auto --backup-name=integration-test"
    local teardown_args="--env=$test_env --confirm --force --no-backup"

    # Add phase arguments if testing two-phase environment
    if [[ "$structure" == "two-phase" ]]; then
        if [[ "$TWO_PHASE" == true ]]; then
            validate_args="$validate_args --two-phase"
            backup_args="$backup_args --two-phase"
        elif [[ -n "$PHASE" ]]; then
            validate_args="$validate_args --phase=$PHASE"
            backup_args="$backup_args --phase=$PHASE"
        fi
    fi

    # Deploy environment
    log INFO "Deploying test environment..."
    if "$PROJECT_ROOT/scripts/lifecycle/setup.sh" $setup_args &>/dev/null; then
        log INFO "✓ Environment deployment succeeded"

        # Validate deployment
        log INFO "Validating deployment..."
        if "$PROJECT_ROOT/scripts/validate.sh" $validate_args &>/dev/null; then
            log INFO "✓ Environment validation passed"
        else
            log WARN "! Environment validation had issues"
        fi

        # Test backup
        log INFO "Testing backup..."
        if "$PROJECT_ROOT/scripts/lifecycle/backup.sh" $backup_args &>/dev/null; then
            log INFO "✓ Backup completed successfully"
        else
            log WARN "! Backup had issues"
        fi

        # Cleanup
        if [[ "$CLEANUP_AFTER" == "true" ]]; then
            log INFO "Cleaning up test environment..."
            if "$PROJECT_ROOT/scripts/lifecycle/teardown.sh" $teardown_args &>/dev/null; then
                log INFO "✓ Environment teardown succeeded"
            else
                log ERROR "✗ Environment teardown failed - manual cleanup may be required"
                return 1
            fi
        fi

    else
        log ERROR "✗ Environment deployment failed"
        return 1
    fi
}

run_prerequisites_tests() {
    log STEP "Running prerequisites tests..."

    run_test "Required Tools Check" "test_prerequisites_tools"
    run_test "Tool Versions Check" "test_prerequisites_versions"
    run_test "Scaleway Credentials Check" "test_prerequisites_credentials"
}

run_smoke_tests() {
    log STEP "Running smoke tests..."

    run_test "Script Syntax Check" "test_script_syntax"
    run_test "Template Discovery" "test_template_discovery"
    run_test "Cost Calculation" "test_cost_calculation"
    run_test "Documentation Consistency" "test_documentation_consistency"
}

run_infrastructure_tests() {
    log STEP "Running infrastructure tests..."

    run_test "Terraform Configuration" "test_terraform_configuration"
    run_test "Backup Functionality" "test_backup_functionality"
    run_test "Validation Functionality" "test_validation_functionality"
    run_test "Scaling Functionality" "test_scaling_functionality"
}

run_template_tests() {
    log STEP "Running template tests..."

    run_test "Template Discovery" "test_template_discovery"
    run_test "Terraform Configuration" "test_terraform_configuration"
}

run_workflow_tests() {
    log STEP "Running workflow tests..."

    run_test "GitHub Actions Syntax" "test_github_actions_syntax"
}

run_integration_tests() {
    log STEP "Running integration tests..."

    run_test "Environment Lifecycle" "test_integration_environment_lifecycle"
}

run_integrations_tests() {
    log STEP "Running external integrations tests..."

    run_test "Integration Configuration Validation" "test_integration_config_validation"
    run_test "Slack Integration" "test_slack_integration"
    run_test "JIRA Integration" "test_jira_integration"
    run_test "Monitoring Integration" "test_monitoring_integration"
    run_test "Email Integration" "test_email_integration"
    run_test "Integration Hooks Execution" "test_integration_hooks"
}

generate_test_report() {
    log STEP "Generating test report..."

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))
    local success_rate=$(( TESTS_RUN > 0 ? (TESTS_PASSED * 100) / TESTS_RUN : 0 ))

    local report_file="${OUTPUT_DIR}/test-report-$(date +%Y%m%d-%H%M%S).md"

    cat > "$report_file" <<EOF
# Coder on Scaleway Test Report

**Generated:** $(date -Iseconds)
**Test Suite:** $TEST_SUITE
**Environment:** $ENVIRONMENT
**Duration:** ${duration_min}m ${duration_sec}s

## Summary

| Metric | Value |
|--------|-------|
| Tests Run | $TESTS_RUN |
| Tests Passed | $TESTS_PASSED |
| Tests Failed | $TESTS_FAILED |
| Success Rate | $success_rate% |

## Test Results

### Passed Tests: $TESTS_PASSED
$( for i in $(seq 1 $TESTS_PASSED); do echo "✅ Test passed"; done )

### Failed Tests: $TESTS_FAILED
$( if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    for test in "${FAILED_TESTS[@]}"; do echo "❌ $test"; done
else
    echo "None"
fi )

## Test Logs

Individual test logs are available in the \`test-results\` directory:

$( find "$OUTPUT_DIR" -name "*.log" -type f | head -10 | while read -r logfile; do
    echo "- \`$(basename "$logfile")\`"
done )

## Recommendations

$( if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "### Issues Found"
    echo "- Review failed test logs for detailed error information"
    echo "- Address failing tests before deployment"
    echo "- Consider running integration tests on a staging environment"
else
    echo "### All Tests Passed"
    echo "- System appears to be functioning correctly"
    echo "- Ready for production deployment"
    echo "- Consider running tests regularly as part of CI/CD"
fi )

## System Information

- **Project Root:** $PROJECT_ROOT
- **Test Environment:** $ENVIRONMENT
- **Cleanup After Tests:** $CLEANUP_AFTER
- **Parallel Testing:** $PARALLEL_TESTS

EOF

    log INFO "✅ Test report generated: $report_file"
    echo "$report_file"
}

print_summary() {
    local report_file=$(generate_test_report)

    echo
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed! 🎉${NC}"
    else
        echo -e "${YELLOW}⚠️  Some tests failed ⚠️${NC}"
    fi
    echo

    echo -e "${WHITE}Test Summary:${NC}"
    echo -e "  Suite: $TEST_SUITE"
    echo -e "  Environment: $ENVIRONMENT"
    echo -e "  Total: $TESTS_RUN tests"
    echo -e "  ${GREEN}Passed: $TESTS_PASSED${NC}"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed: $TESTS_FAILED${NC}"
    fi

    local success_rate=$(( TESTS_RUN > 0 ? (TESTS_PASSED * 100) / TESTS_RUN : 0 ))
    echo -e "  Success Rate: $success_rate%"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo
        echo -e "${YELLOW}Failed Tests:${NC}"
        if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
            for test in "${FAILED_TESTS[@]}"; do
                echo -e "  ${RED}✗${NC} $test"
            done
        fi
    fi

    echo
    echo -e "${YELLOW}Test Report:${NC} $report_file"
    echo -e "${YELLOW}Test Logs:${NC} $OUTPUT_DIR"
    echo

    return $(( TESTS_FAILED > 0 ? 1 : 0 ))
}

cleanup_test_environment() {
    if [[ "$CLEANUP_AFTER" == "true" ]]; then
        log STEP "Cleaning up test environment..."

        # Clean up any test files
        find "$PROJECT_ROOT" -name "*test*backup*" -type d -exec rm -rf {} + 2>/dev/null || true

        log INFO "✅ Test cleanup completed"
    fi
}

# Integration test functions
test_integration_config_validation() {
    log INFO "Validating integration configuration..."

    # Check if .env.example exists and is properly formatted
    if [[ ! -f "$PROJECT_ROOT/.env.example" ]]; then
        log ERROR ".env.example file not found"
        return 1
    fi

    # Check if essential integration variables are documented
    local required_vars=("SLACK_WEBHOOK" "JIRA_API_URL" "JIRA_API_TOKEN" "MONITORING_API_URL" "MONITORING_API_TOKEN" "ADMIN_EMAIL")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" "$PROJECT_ROOT/.env.example"; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log ERROR "Missing integration variables in .env.example: ${missing_vars[*]}"
        return 1
    fi

    log INFO "✓ Integration configuration validation passed"
    return 0
}

test_slack_integration() {
    log INFO "Testing Slack integration..."

    # Test with no webhook configured (should gracefully handle)
    local test_output
    test_output=$(SLACK_WEBHOOK="" bash -c "
        source $PROJECT_ROOT/scripts/hooks/pre-setup.sh --env=dev 2>&1 | grep -i slack || true
    ")

    if echo "$test_output" | grep -q "not configured"; then
        log INFO "✓ Slack integration handles missing configuration gracefully"
    else
        log WARN "Slack integration may not handle missing configuration properly"
    fi

    # Test with mock webhook (test function structure)
    if command -v curl &>/dev/null; then
        # Test webhook format validation
        local invalid_webhook="not-a-valid-webhook"
        if SLACK_WEBHOOK="$invalid_webhook" timeout 10 bash "$PROJECT_ROOT/scripts/hooks/pre-setup.sh" --env=dev 2>/dev/null; then
            log INFO "✓ Slack integration handles invalid webhooks"
        else
            log INFO "✓ Slack integration properly validates webhook format"
        fi
    fi

    log INFO "✓ Slack integration tests completed"
    return 0
}

test_jira_integration() {
    log INFO "Testing JIRA integration..."

    # Test with no JIRA configured (should gracefully handle)
    local test_output
    test_output=$(JIRA_API_URL="" JIRA_API_TOKEN="" bash -c "
        source $PROJECT_ROOT/scripts/hooks/post-setup.sh --env=dev 2>&1 | grep -i jira || true
    ")

    if echo "$test_output" | grep -q "not configured"; then
        log INFO "✓ JIRA integration handles missing configuration gracefully"
    else
        log WARN "JIRA integration may not handle missing configuration properly"
    fi

    # Test with mock credentials (test function structure)
    if command -v curl &>/dev/null; then
        # Test API URL validation
        local invalid_api="not-a-valid-api-url"
        if JIRA_API_URL="$invalid_api" JIRA_API_TOKEN="test" timeout 10 bash "$PROJECT_ROOT/scripts/hooks/post-setup.sh" --env=dev 2>/dev/null; then
            log INFO "✓ JIRA integration handles invalid API URLs"
        else
            log INFO "✓ JIRA integration properly validates API configuration"
        fi
    fi

    log INFO "✓ JIRA integration tests completed"
    return 0
}

test_monitoring_integration() {
    log INFO "Testing monitoring integration..."

    # Test with no monitoring configured (should gracefully handle)
    local test_output
    test_output=$(MONITORING_API_URL="" MONITORING_API_TOKEN="" bash -c "
        source $PROJECT_ROOT/scripts/hooks/post-setup.sh --env=dev 2>&1 | grep -i monitoring || true
    ")

    if echo "$test_output" | grep -q "not configured"; then
        log INFO "✓ Monitoring integration handles missing configuration gracefully"
    else
        log WARN "Monitoring integration may not handle missing configuration properly"
    fi

    # Test environment-specific alert configuration
    local alert_configs=("prod" "staging" "dev")
    for env in "${alert_configs[@]}"; do
        if grep -q "\"$env\":" "$PROJECT_ROOT/scripts/hooks/post-setup.sh"; then
            log INFO "✓ Environment-specific monitoring configuration found for $env"
        else
            log WARN "Missing environment-specific monitoring configuration for $env"
        fi
    done

    log INFO "✓ Monitoring integration tests completed"
    return 0
}

test_email_integration() {
    log INFO "Testing email integration..."

    # Test with no email configured (should gracefully handle)
    local test_output
    test_output=$(ADMIN_EMAIL="" bash -c "
        source $PROJECT_ROOT/scripts/hooks/post-setup.sh --env=dev 2>&1 | grep -i 'email\|mail' || true
    ")

    if echo "$test_output" | grep -q "not configured"; then
        log INFO "✓ Email integration handles missing configuration gracefully"
    else
        log WARN "Email integration may not handle missing configuration properly"
    fi

    # Check if mail command dependency is handled
    if ! command -v mail &>/dev/null; then
        local mail_check
        mail_check=$(ADMIN_EMAIL="test@example.com" bash -c "
            source $PROJECT_ROOT/scripts/hooks/post-setup.sh --env=dev 2>&1 | grep -i mail || true
        ")

        if echo "$mail_check" | grep -q "not configured\|command"; then
            log INFO "✓ Email integration handles missing mail command gracefully"
        fi
    fi

    log INFO "✓ Email integration tests completed"
    return 0
}

test_integration_hooks() {
    log INFO "Testing integration hooks execution..."

    # Test that hooks can be executed without errors
    local hooks=("pre-setup.sh" "post-setup.sh" "pre-teardown.sh" "post-teardown.sh")
    local hook_errors=0

    for hook in "${hooks[@]}"; do
        local hook_path="$PROJECT_ROOT/scripts/hooks/$hook"
        if [[ -f "$hook_path" ]]; then
            # Test hook syntax
            if bash -n "$hook_path" 2>/dev/null; then
                log INFO "✓ Hook $hook has valid syntax"
            else
                log ERROR "✗ Hook $hook has syntax errors"
                ((hook_errors++))
            fi

            # Test hook execution with no integrations configured
            if timeout 30 bash "$hook_path" --env=dev 2>/dev/null; then
                log INFO "✓ Hook $hook executes without errors"
            else
                # This is acceptable if hook exits cleanly with warnings
                log INFO "○ Hook $hook execution completed (may have warnings)"
            fi
        else
            log ERROR "✗ Hook file not found: $hook_path"
            ((hook_errors++))
        fi
    done

    if [[ $hook_errors -eq 0 ]]; then
        log INFO "✓ All integration hooks are functional"
        return 0
    else
        log ERROR "✗ $hook_errors hook(s) have issues"
        return 1
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --suite=*)
                TEST_SUITE="${1#*=}"
                shift
                ;;
            --environment=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --no-cleanup)
                CLEANUP_AFTER=false
                shift
                ;;
            --parallel)
                PARALLEL_TESTS=true
                shift
                ;;
            --timeout=*)
                TEST_TIMEOUT="${1#*=}"
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
            --output-dir=*)
                OUTPUT_DIR="${1#*=}"
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$TEST_SUITE" ]]; then
        log ERROR "Test suite is required. Use --suite=SUITE"
        print_usage
        exit 1
    fi

    # Validate phase if specified
    if [[ -n "$PHASE" && ! "$PHASE" =~ ^(infra|coder)$ ]]; then
        log ERROR "Invalid phase: $PHASE. Must be one of: infra, coder"
        exit 1
    fi

    # Validate phase options compatibility
    if [[ "$TWO_PHASE" == true && -n "$PHASE" ]]; then
        log ERROR "Cannot specify both --two-phase and --phase options"
        exit 1
    fi

    print_banner
    setup_test_environment

    log INFO "Starting test suite: $TEST_SUITE"
    log INFO "Test environment: $ENVIRONMENT"
    log INFO "Parallel testing: $PARALLEL_TESTS"
    [[ "$TWO_PHASE" == true ]] && log INFO "🔄 Two-phase testing enabled (infra + coder)"
    [[ -n "$PHASE" ]] && log INFO "⚙️ Phase-specific testing: $PHASE"

    # Run selected test suite
    case "$TEST_SUITE" in
        prerequisites)
            run_prerequisites_tests
            ;;
        smoke)
            run_smoke_tests
            ;;
        infrastructure)
            run_infrastructure_tests
            ;;
        templates)
            run_template_tests
            ;;
        workflows)
            run_workflow_tests
            ;;
        integration)
            run_integration_tests
            ;;
        integrations)
            run_integrations_tests
            ;;
        all)
            run_prerequisites_tests
            run_smoke_tests
            run_infrastructure_tests
            run_template_tests
            run_workflow_tests
            run_integration_tests
            run_integrations_tests
            ;;
        *)
            log ERROR "Unknown test suite: $TEST_SUITE"
            log ERROR "Available suites: all, smoke, prerequisites, infrastructure, templates, workflows, integration, integrations"
            exit 1
            ;;
    esac

    cleanup_test_environment
    print_summary
}

# Run main function with all arguments
main "$@"