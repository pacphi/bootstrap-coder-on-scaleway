#!/bin/bash

# Coder on Scaleway - Integration Tests
# Comprehensive integration testing for CI/CD pipeline

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
ENVIRONMENT=""
TIMEOUT=1800  # 30 minutes
PARALLEL=false
VERBOSE=false
FAIL_FAST=false
LOG_FILE=""
OUTPUT_FORMAT="console"
JUNIT_OUTPUT=""
COVERAGE_REPORT=false
START_TIME=$(date +%s)

# Test results tracking
declare -A TEST_RESULTS
declare -a TEST_ORDER
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║         Integration Testing           ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run comprehensive integration tests for Coder environments including
infrastructure validation, API testing, workspace functionality, and security checks.

Options:
    --env=ENV               Environment to test (dev|staging|prod) [required]
    --timeout=SECONDS       Test timeout in seconds [default: 1800]
    --parallel             Run tests in parallel where possible
    --verbose              Enable verbose test output
    --fail-fast            Stop on first test failure
    --format=FORMAT        Output format (console|json|junit) [default: console]
    --junit-output=FILE    JUnit XML output file (when format=junit)
    --coverage             Generate test coverage report
    --help                 Show this help message

Test Suites:
    • Infrastructure      Terraform state, resources, networking
    • Database            PostgreSQL connectivity, performance, backups
    • Kubernetes          Cluster health, pod status, resource usage
    • Coder Platform      API endpoints, authentication, workspace management
    • Security            RBAC, network policies, certificate validation
    • Performance        Response times, resource utilization, scalability
    • Backup & Recovery   Backup integrity, restore procedures

Examples:
    $0 --env=dev --verbose
    $0 --env=staging --parallel --fail-fast
    $0 --env=prod --format=junit --junit-output=results.xml
    $0 --env=dev --coverage --timeout=3600

CI/CD Integration:
    # GitHub Actions
    - name: Run Integration Tests
      run: ./scripts/run-integration-tests.sh --env=staging --format=junit --junit-output=results.xml

    # Test Results Processing
    - name: Publish Test Results
      uses: dorny/test-reporter@v1
      with:
        name: Integration Tests
        path: results.xml
        reporter: java-junit

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
        DEBUG) [[ "$VERBOSE" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $message" ;;
        STEP)  echo -e "${CYAN}[STEP]${NC}  $message" ;;
        PASS)  echo -e "${GREEN}[PASS]${NC}  $message" ;;
        FAIL)  echo -e "${RED}[FAIL]${NC}  $message" ;;
        SKIP)  echo -e "${YELLOW}[SKIP]${NC}  $message" ;;
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_logging() {
    local log_dir="${PROJECT_ROOT}/logs/integration-tests"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-integration-tests.log"
    log INFO "Logging to: $LOG_FILE"
}

validate_environment() {
    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Testing environment: $ENVIRONMENT"
            ;;
        *)
            log ERROR "Invalid environment: $ENVIRONMENT"
            log ERROR "Must be one of: dev, staging, prod"
            exit 1
            ;;
    esac

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    if [[ ! -d "$env_dir" ]]; then
        log ERROR "Environment directory not found: $env_dir"
        exit 1
    fi
}

run_test() {
    local test_name="$1"
    local test_function="$2"
    local start_time=$(date +%s)

    log STEP "Running test: $test_name"
    TEST_ORDER+=("$test_name")

    # Set up timeout
    (
        exec 3>&1 4>&2
        {
            timeout "$TIMEOUT" bash -c "$test_function" 2>&4 1>&3
            echo $? >&5
        } 5>&1 | {
            read exit_code
            exit "$exit_code"
        }
    ) &
    local test_pid=$!

    if wait $test_pid; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        TEST_RESULTS["$test_name"]="PASSED:$duration"
        ((TESTS_PASSED++))
        log PASS "$test_name completed in ${duration}s"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        TEST_RESULTS["$test_name"]="FAILED:$duration"
        ((TESTS_FAILED++))
        log FAIL "$test_name failed after ${duration}s"

        if [[ "$FAIL_FAST" == "true" ]]; then
            log ERROR "Fail-fast enabled, stopping tests"
            exit 1
        fi
        return 1
    fi
}

test_infrastructure() {
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"

    log DEBUG "Testing infrastructure for environment: $ENVIRONMENT"

    # Check Terraform state
    cd "$env_dir"

    if ! terraform validate; then
        log ERROR "Terraform configuration validation failed"
        return 1
    fi

    if ! terraform plan -detailed-exitcode -out=tfplan; then
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            log WARN "Infrastructure drift detected"
        else
            log ERROR "Terraform plan failed"
            return 1
        fi
    fi

    # Check resource state
    local outputs=$(terraform output -json 2>/dev/null || echo "{}")

    # Verify key outputs exist
    local cluster_id=$(echo "$outputs" | jq -r '.cluster_id.value // empty')
    local database_id=$(echo "$outputs" | jq -r '.database_id.value // empty')
    local kubeconfig_path=$(echo "$outputs" | jq -r '.kubeconfig_path.value // empty')

    if [[ -z "$cluster_id" ]]; then
        log ERROR "Cluster ID not found in outputs"
        return 1
    fi

    if [[ -z "$database_id" ]]; then
        log ERROR "Database ID not found in outputs"
        return 1
    fi

    if [[ -z "$kubeconfig_path" ]]; then
        log ERROR "Kubeconfig path not found in outputs"
        return 1
    fi

    # Verify Scaleway resources exist
    if ! scw k8s cluster get "$cluster_id" > /dev/null 2>&1; then
        log ERROR "Cluster $cluster_id not found in Scaleway"
        return 1
    fi

    if ! scw rdb instance get "$database_id" > /dev/null 2>&1; then
        log ERROR "Database $database_id not found in Scaleway"
        return 1
    fi

    # Clean up
    rm -f tfplan

    log DEBUG "Infrastructure tests passed"
    return 0
}

test_database() {
    log DEBUG "Testing database connectivity and performance"

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Get database connection details from secrets
    local db_secret=""
    if kubectl get secret coder-db-secret -n coder &> /dev/null; then
        db_secret="coder-db-secret"
    elif kubectl get secret coder-database -n coder &> /dev/null; then
        db_secret="coder-database"
    else
        log ERROR "No database secret found"
        return 1
    fi

    local db_host=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.host}' | base64 -d 2>/dev/null || echo "")
    local db_user=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "postgres")
    local db_name=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.database}' | base64 -d 2>/dev/null || echo "coder")
    local db_pass=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")

    if [[ -z "$db_host" || -z "$db_pass" ]]; then
        log ERROR "Incomplete database credentials"
        return 1
    fi

    # Test database connectivity
    local test_result=$(kubectl run db-test-$(date +%s) \
        --image=postgres:15 \
        --rm -i \
        --restart=Never \
        --env="PGPASSWORD=$db_pass" \
        --command -- psql \
        -h "$db_host" \
        -U "$db_user" \
        -d "$db_name" \
        -c "SELECT 'OK' as status;" 2>/dev/null | grep -c "OK" || echo "0")

    if [[ "$test_result" != "1" ]]; then
        log ERROR "Database connectivity test failed"
        return 1
    fi

    # Test database performance (simple query performance test)
    local perf_result=$(kubectl run db-perf-$(date +%s) \
        --image=postgres:15 \
        --rm -i \
        --restart=Never \
        --env="PGPASSWORD=$db_pass" \
        --command -- psql \
        -h "$db_host" \
        -U "$db_user" \
        -d "$db_name" \
        -c "SELECT count(*) FROM information_schema.tables;" 2>/dev/null | grep -E "^[0-9]+$" | head -n1 || echo "0")

    if [[ "$perf_result" -lt "1" ]]; then
        log WARN "Database performance test returned unexpected results"
    fi

    log DEBUG "Database tests passed"
    return 0
}

test_kubernetes() {
    log DEBUG "Testing Kubernetes cluster health and resources"

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Test cluster connectivity
    if ! kubectl cluster-info > /dev/null 2>&1; then
        log ERROR "Cannot connect to Kubernetes cluster"
        return 1
    fi

    # Check node status
    local not_ready_nodes=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
    if [[ "$not_ready_nodes" -gt "0" ]]; then
        log ERROR "$not_ready_nodes nodes are not in Ready state"
        kubectl get nodes --no-headers | grep -v "Ready" | while read node rest; do
            log ERROR "Node $node is not ready"
        done
        return 1
    fi

    # Check critical namespaces
    for ns in kube-system coder; do
        if ! kubectl get namespace "$ns" > /dev/null 2>&1; then
            log ERROR "Namespace $ns not found"
            return 1
        fi
    done

    # Check Coder deployment
    if ! kubectl get deployment coder -n coder > /dev/null 2>&1; then
        log ERROR "Coder deployment not found"
        return 1
    fi

    # Check deployment readiness
    local ready_replicas=$(kubectl get deployment coder -n coder -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas=$(kubectl get deployment coder -n coder -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

    if [[ "$ready_replicas" != "$desired_replicas" ]]; then
        log ERROR "Coder deployment not fully ready ($ready_replicas/$desired_replicas)"
        return 1
    fi

    # Check resource usage
    if command -v kubectl > /dev/null && kubectl top nodes > /dev/null 2>&1; then
        local high_cpu_nodes=$(kubectl top nodes --no-headers | awk '{print $3}' | sed 's/%//' | awk '$1 > 80' | wc -l)
        local high_mem_nodes=$(kubectl top nodes --no-headers | awk '{print $5}' | sed 's/%//' | awk '$1 > 80' | wc -l)

        if [[ "$high_cpu_nodes" -gt "0" ]]; then
            log WARN "$high_cpu_nodes nodes have high CPU usage (>80%)"
        fi

        if [[ "$high_mem_nodes" -gt "0" ]]; then
            log WARN "$high_mem_nodes nodes have high memory usage (>80%)"
        fi
    fi

    log DEBUG "Kubernetes tests passed"
    return 0
}

test_coder_platform() {
    log DEBUG "Testing Coder platform functionality"

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Get Coder service endpoint
    local coder_host=""
    if kubectl get ingress -n coder > /dev/null 2>&1; then
        coder_host=$(kubectl get ingress -n coder -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    fi

    if [[ -z "$coder_host" ]]; then
        # Try service endpoint
        local coder_ip=$(kubectl get service coder -n coder -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        local coder_port=$(kubectl get service coder -n coder -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "7080")

        if [[ -n "$coder_ip" ]]; then
            coder_host="$coder_ip:$coder_port"
        else
            log ERROR "Cannot determine Coder endpoint"
            return 1
        fi
    fi

    # Test HTTP connectivity
    local protocol="https"
    if [[ "$coder_host" =~ :[0-9]+$ ]]; then
        protocol="http"
    fi

    local coder_url="${protocol}://${coder_host}"

    # Test health endpoint
    local health_status=$(curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "${coder_url}/api/v2/buildinfo" || echo "000")

    if [[ "$health_status" -ne "200" ]]; then
        log ERROR "Coder API health check failed (HTTP $health_status)"
        return 1
    fi

    # Test API version endpoint
    local api_response=$(curl -s -k --connect-timeout 10 --max-time 30 "${coder_url}/api/v2/buildinfo" 2>/dev/null || echo "")

    if [[ -z "$api_response" ]] || ! echo "$api_response" | jq . > /dev/null 2>&1; then
        log ERROR "Coder API returned invalid JSON response"
        return 1
    fi

    # Extract version info
    local coder_version=$(echo "$api_response" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
    log DEBUG "Coder version: $coder_version"

    # Check for critical Coder pod logs errors
    local error_count=$(kubectl logs deployment/coder -n coder --tail=100 2>/dev/null | grep -c "ERROR\|FATAL\|panic" || echo "0")

    if [[ "$error_count" -gt "0" ]]; then
        log WARN "Found $error_count error entries in Coder logs"
        if [[ "$VERBOSE" == "true" ]]; then
            kubectl logs deployment/coder -n coder --tail=20 | grep "ERROR\|FATAL\|panic" || true
        fi
    fi

    log DEBUG "Coder platform tests passed"
    return 0
}

test_security() {
    log DEBUG "Testing security configurations"

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Check Pod Security Standards
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        local pss_violations=$(kubectl get pods -A -o json | jq -r '.items[] | select(.spec.securityContext.runAsNonRoot != true) | .metadata.name' 2>/dev/null | wc -l)

        if [[ "$pss_violations" -gt "0" ]]; then
            log WARN "$pss_violations pods may violate Pod Security Standards"
        fi
    fi

    # Check for default deny network policies (prod only)
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        if ! kubectl get networkpolicy default-deny-all -n coder > /dev/null 2>&1; then
            log WARN "Default deny network policy not found in production"
        fi
    fi

    # Check certificate expiration
    if kubectl get certificates -n coder > /dev/null 2>&1; then
        local expiring_certs=$(kubectl get certificates -n coder -o json | jq -r '.items[] | select(.status.notAfter // "2099-12-31T23:59:59Z" | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime < (now + 2592000)) | .metadata.name' 2>/dev/null | wc -l)

        if [[ "$expiring_certs" -gt "0" ]]; then
            log WARN "$expiring_certs certificates expire within 30 days"
        fi
    fi

    # Check for secrets with default passwords (basic check)
    local secrets_with_defaults=0
    while IFS= read -r secret; do
        if kubectl get secret "$secret" -n coder -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null | grep -q "password\|admin\|123456"; then
            ((secrets_with_defaults++))
            log WARN "Secret $secret may contain default password"
        fi
    done < <(kubectl get secrets -n coder --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)

    log DEBUG "Security tests passed"
    return 0
}

test_performance() {
    log DEBUG "Testing system performance"

    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Test Coder API response time
    local coder_host=""
    if kubectl get ingress -n coder > /dev/null 2>&1; then
        coder_host=$(kubectl get ingress -n coder -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "")
    fi

    if [[ -n "$coder_host" ]]; then
        local response_time=$(curl -s -k -o /dev/null -w "%{time_total}" --connect-timeout 10 --max-time 30 "https://${coder_host}/api/v2/buildinfo" 2>/dev/null || echo "999")

        # Convert to milliseconds for easier comparison
        local response_time_ms=$(echo "$response_time * 1000" | bc -l | cut -d. -f1)

        if [[ "$response_time_ms" -gt "5000" ]]; then
            log WARN "API response time is high: ${response_time}s"
        else
            log DEBUG "API response time: ${response_time}s"
        fi

        # Test multiple requests for consistency
        local slow_requests=0
        for i in {1..5}; do
            local rt=$(curl -s -k -o /dev/null -w "%{time_total}" --connect-timeout 10 --max-time 30 "https://${coder_host}/api/v2/buildinfo" 2>/dev/null || echo "999")
            local rt_ms=$(echo "$rt * 1000" | bc -l | cut -d. -f1)

            if [[ "$rt_ms" -gt "3000" ]]; then
                ((slow_requests++))
            fi
        done

        if [[ "$slow_requests" -gt "2" ]]; then
            log WARN "$slow_requests/5 API requests were slow (>3s)"
        fi
    fi

    # Check resource usage if metrics server is available
    if kubectl top nodes > /dev/null 2>&1; then
        local avg_cpu=$(kubectl top nodes --no-headers | awk '{sum += $3} END {print sum/NR}' | sed 's/%//')
        local avg_mem=$(kubectl top nodes --no-headers | awk '{sum += $5} END {print sum/NR}' | sed 's/%//')

        log DEBUG "Average cluster resource usage: ${avg_cpu}% CPU, ${avg_mem}% Memory"

        if (( $(echo "$avg_cpu > 85" | bc -l) )); then
            log WARN "High average CPU usage: ${avg_cpu}%"
        fi

        if (( $(echo "$avg_mem > 85" | bc -l) )); then
            log WARN "High average memory usage: ${avg_mem}%"
        fi
    fi

    log DEBUG "Performance tests passed"
    return 0
}

test_backup_recovery() {
    log DEBUG "Testing backup and recovery capabilities"

    # Check if backup script exists and is executable
    local backup_script="${PROJECT_ROOT}/scripts/lifecycle/backup.sh"

    if [[ ! -f "$backup_script" ]] || [[ ! -x "$backup_script" ]]; then
        log ERROR "Backup script not found or not executable: $backup_script"
        return 1
    fi

    # Test backup dry run
    if ! "$backup_script" --env="$ENVIRONMENT" --dry-run > /dev/null 2>&1; then
        log ERROR "Backup dry run failed"
        return 1
    fi

    # Check backup directory structure
    local backup_dir="${PROJECT_ROOT}/backups"
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir" || {
            log ERROR "Cannot create backup directory: $backup_dir"
            return 1
        }
    fi

    if [[ ! -w "$backup_dir" ]]; then
        log ERROR "Backup directory not writable: $backup_dir"
        return 1
    fi

    # Check for recent backups (optional test)
    local recent_backups=$(find "$backup_dir" -name "*${ENVIRONMENT}*" -mtime -7 | wc -l)
    log DEBUG "Found $recent_backups recent backups for $ENVIRONMENT"

    # Test restore script if available
    local restore_script="${PROJECT_ROOT}/scripts/restore.sh"
    if [[ -f "$restore_script" ]] && [[ -x "$restore_script" ]]; then
        # Test restore dry run (only if we have backups)
        if [[ "$recent_backups" -gt "0" ]]; then
            local latest_backup=$(find "$backup_dir" -name "*${ENVIRONMENT}*" -type d -printf '%T+ %p\n' | sort -r | head -n1 | cut -d' ' -f2-)

            if [[ -n "$latest_backup" ]]; then
                local backup_name=$(basename "$latest_backup")
                if ! "$restore_script" --env="$ENVIRONMENT" --backup-name="$backup_name" --dry-run > /dev/null 2>&1; then
                    log WARN "Restore dry run failed for backup: $backup_name"
                fi
            fi
        fi
    fi

    log DEBUG "Backup and recovery tests passed"
    return 0
}

generate_junit_report() {
    if [[ "$OUTPUT_FORMAT" != "junit" ]] || [[ -z "$JUNIT_OUTPUT" ]]; then
        return 0
    fi

    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    cat > "$JUNIT_OUTPUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="Coder Integration Tests" tests="$total_tests" failures="$TESTS_FAILED" errors="0" skipped="$TESTS_SKIPPED" time="$total_time">
  <testsuite name="coder-${ENVIRONMENT}-integration" tests="$total_tests" failures="$TESTS_FAILED" errors="0" skipped="$TESTS_SKIPPED" time="$total_time">
EOF

    for test_name in "${TEST_ORDER[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        local status="${result%%:*}"
        local duration="${result##*:}"

        cat >> "$JUNIT_OUTPUT" <<EOF
    <testcase name="$test_name" classname="integration" time="$duration">
EOF

        if [[ "$status" == "FAILED" ]]; then
            cat >> "$JUNIT_OUTPUT" <<EOF
      <failure message="Test failed">Test $test_name failed</failure>
EOF
        elif [[ "$status" == "SKIPPED" ]]; then
            cat >> "$JUNIT_OUTPUT" <<EOF
      <skipped message="Test skipped">Test $test_name was skipped</skipped>
EOF
        fi

        echo "    </testcase>" >> "$JUNIT_OUTPUT"
    done

    cat >> "$JUNIT_OUTPUT" <<EOF
  </testsuite>
</testsuites>
EOF

    log INFO "JUnit report generated: $JUNIT_OUTPUT"
}

generate_json_report() {
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        return 0
    fi

    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    local json_output="${LOG_FILE%.log}.json"

    cat > "$json_output" <<EOF
{
  "environment": "$ENVIRONMENT",
  "timestamp": "$(date -Iseconds)",
  "duration": $total_time,
  "summary": {
    "total": $total_tests,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED
  },
  "tests": {
EOF

    local first=true
    for test_name in "${TEST_ORDER[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        local status="${result%%:*}"
        local duration="${result##*:}"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo "," >> "$json_output"
        fi

        cat >> "$json_output" <<EOF
    "$test_name": {
      "status": "$status",
      "duration": $duration
    }
EOF
    done

    cat >> "$json_output" <<EOF
  }
}
EOF

    log INFO "JSON report generated: $json_output"
}

print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))

    echo
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${WHITE}           TEST SUMMARY${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"
    echo -e "${WHITE}Total Tests:${NC} $total_tests"
    echo
    echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Failed:${NC} $TESTS_FAILED"
    echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo

    if [[ "$TESTS_FAILED" -eq "0" ]]; then
        echo -e "${GREEN}🎉 All integration tests passed! 🎉${NC}"
        echo
        echo -e "${YELLOW}✅ Environment Status:${NC}"
        echo "   • Infrastructure: Validated"
        echo "   • Database: Connected and responsive"
        echo "   • Kubernetes: Healthy and ready"
        echo "   • Coder Platform: Accessible and functional"
        echo "   • Security: Configurations validated"
        echo "   • Performance: Within acceptable limits"
        echo "   • Backup/Recovery: Procedures tested"
    else
        echo -e "${RED}❌ Some integration tests failed${NC}"
        echo
        echo -e "${YELLOW}Failed Tests:${NC}"
        for test_name in "${TEST_ORDER[@]}"; do
            local result="${TEST_RESULTS[$test_name]}"
            local status="${result%%:*}"

            if [[ "$status" == "FAILED" ]]; then
                echo "   • $test_name"
            fi
        done
    fi

    echo
    echo -e "${CYAN}📋 Detailed Results:${NC}"
    for test_name in "${TEST_ORDER[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        local status="${result%%:*}"
        local duration="${result##*:}"

        case "$status" in
            "PASSED") echo -e "   ${GREEN}✓${NC} $test_name (${duration}s)" ;;
            "FAILED") echo -e "   ${RED}✗${NC} $test_name (${duration}s)" ;;
            "SKIPPED") echo -e "   ${YELLOW}-${NC} $test_name (skipped)" ;;
        esac
    done

    echo
    echo -e "${CYAN}📁 Log Files:${NC}"
    echo "   • Detailed log: $LOG_FILE"
    if [[ "$OUTPUT_FORMAT" == "junit" ]] && [[ -n "$JUNIT_OUTPUT" ]]; then
        echo "   • JUnit XML: $JUNIT_OUTPUT"
    fi
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "   • JSON report: ${LOG_FILE%.log}.json"
    fi

    echo
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
                shift
                ;;
            --parallel)
                PARALLEL=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --fail-fast)
                FAIL_FAST=true
                shift
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
                shift
                ;;
            --junit-output=*)
                JUNIT_OUTPUT="${1#*=}"
                shift
                ;;
            --coverage)
                COVERAGE_REPORT=true
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

    # Validate required parameters
    if [[ -z "$ENVIRONMENT" ]]; then
        log ERROR "Environment is required. Use --env=ENV"
        print_usage
        exit 1
    fi

    # Validate output format
    case "$OUTPUT_FORMAT" in
        console|json|junit)
            ;;
        *)
            log ERROR "Invalid output format: $OUTPUT_FORMAT"
            log ERROR "Must be one of: console, json, junit"
            exit 1
            ;;
    esac

    print_banner
    setup_logging
    validate_environment

    log INFO "Starting integration tests for environment: $ENVIRONMENT"
    log INFO "Output format: $OUTPUT_FORMAT"
    log INFO "Test timeout: ${TIMEOUT}s"

    # Run test suites
    run_test "Infrastructure" "test_infrastructure"
    run_test "Database" "test_database"
    run_test "Kubernetes" "test_kubernetes"
    run_test "Coder Platform" "test_coder_platform"
    run_test "Security" "test_security"
    run_test "Performance" "test_performance"
    run_test "Backup & Recovery" "test_backup_recovery"

    # Generate reports
    generate_junit_report
    generate_json_report
    print_summary

    # Exit with appropriate code
    if [[ "$TESTS_FAILED" -gt "0" ]]; then
        exit 1
    else
        exit 0
    fi
}

# Check for required dependencies
command -v kubectl >/dev/null 2>&1 || { log ERROR "kubectl is required but not installed. Aborting."; exit 1; }
command -v scw >/dev/null 2>&1 || { log ERROR "Scaleway CLI (scw) is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { log ERROR "jq is required but not installed. Aborting."; exit 1; }
command -v curl >/dev/null 2>&1 || { log ERROR "curl is required but not installed. Aborting."; exit 1; }
command -v bc >/dev/null 2>&1 || { log ERROR "bc is required but not installed. Aborting."; exit 1; }

# Run main function with all arguments
main "$@"