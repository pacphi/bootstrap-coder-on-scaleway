#!/bin/bash

# Coder on Scaleway - Validation Script
# Comprehensive health checking and validation for environments

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
QUICK_CHECK=false
DETAILED=false
COMPONENTS="all"
OUTPUT_FILE=""
POST_RESTORE_CHECKS=false
COMPREHENSIVE=false
SECURITY_AUDIT=false
TIMEOUT=300
LOG_FILE=""
VALIDATION_RESULTS=()

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║       Environment Validation          ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate the health and functionality of Coder environments including
infrastructure, Kubernetes resources, applications, and connectivity.

Options:
    --env=ENV                   Environment to validate (dev|staging|prod|all) [required]
    --quick                     Quick connectivity check only
    --detailed                  Detailed validation with metrics
    --comprehensive             Full validation including performance tests
    --security                  Include security audit checks
    --components=LIST           Specific components to check (comma-separated)
                               Options: infrastructure,cluster,coder,database,monitoring,network,security
    --post-restore-checks       Additional checks after backup restore
    --timeout=SECONDS           Timeout for checks (default: 300)
    --output=FILE               Save detailed results to JSON file
    --help                      Show this help message

Examples:
    $0 --env=dev --quick
    $0 --env=prod --detailed --output=health-report.json
    $0 --env=staging --components=coder,database
    $0 --env=all --comprehensive --security

Component Checks:
    • Infrastructure: Terraform state, Scaleway resources
    • Cluster: Kubernetes nodes, system pods, storage
    • Coder: Application health, API endpoints, templates
    • Database: Connectivity, performance, backups
    • Monitoring: Prometheus/Grafana status, metrics
    • Network: DNS resolution, certificates, ingress
    • Security: Pod Security Standards, RBAC, network policies, compliance

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
        PASS)  echo -e "${GREEN}[PASS]${NC}  $message" ;;
        FAIL)  echo -e "${RED}[FAIL]${NC}  $message" ;;
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_logging() {
    if [[ -n "$OUTPUT_FILE" ]]; then
        local log_dir=$(dirname "$OUTPUT_FILE")
        mkdir -p "$log_dir" 2>/dev/null || true
        LOG_FILE="${OUTPUT_FILE%.json}.log"
        log INFO "Logging to: $LOG_FILE"
    fi
}

add_result() {
    local component="$1"
    local check="$2"
    local status="$3"
    local message="$4"
    local details="${5:-}"

    VALIDATION_RESULTS+=("$component|$check|$status|$message|$details")
}

validate_environment() {
    if [[ "$ENVIRONMENT" == "all" ]]; then
        return 0
    fi

    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Target environment: $ENVIRONMENT"
            ;;
        *)
            log ERROR "Invalid environment: $ENVIRONMENT"
            log ERROR "Must be one of: dev, staging, prod, all"
            exit 1
            ;;
    esac

    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    if [[ ! -d "$env_dir" ]]; then
        log ERROR "Environment directory not found: $env_dir"
        exit 1
    fi
}

check_infrastructure() {
    local env_name="$1"

    log STEP "Validating infrastructure for environment: $env_name"

    local env_dir="${PROJECT_ROOT}/environments/${env_name}"

    # Check Terraform state
    if [[ -f "${env_dir}/terraform.tfstate" ]]; then
        log PASS "Terraform state file exists"
        add_result "infrastructure" "terraform_state" "pass" "State file exists" "${env_dir}/terraform.tfstate"

        # Validate state is not empty
        local resource_count=$(jq -r '.resources | length' "${env_dir}/terraform.tfstate" 2>/dev/null || echo "0")
        if [[ "$resource_count" -gt 0 ]]; then
            log PASS "Terraform state contains $resource_count resources"
            add_result "infrastructure" "terraform_resources" "pass" "$resource_count resources in state" "$resource_count"
        else
            log FAIL "Terraform state is empty or invalid"
            add_result "infrastructure" "terraform_resources" "fail" "State is empty or invalid" "$resource_count"
        fi
    else
        log FAIL "Terraform state file not found"
        add_result "infrastructure" "terraform_state" "fail" "State file not found" ""
        return 1
    fi

    # Check Terraform configuration
    cd "$env_dir"
    if terraform validate &>/dev/null; then
        log PASS "Terraform configuration is valid"
        add_result "infrastructure" "terraform_config" "pass" "Configuration is valid" ""
    else
        log FAIL "Terraform configuration validation failed"
        add_result "infrastructure" "terraform_config" "fail" "Configuration validation failed" ""
    fi

    # Check if we can refresh state (tests Scaleway connectivity)
    if timeout "$TIMEOUT" terraform refresh -input=false &>/dev/null; then
        log PASS "Terraform can connect to Scaleway"
        add_result "infrastructure" "scaleway_connectivity" "pass" "Scaleway API accessible" ""
    else
        log FAIL "Cannot connect to Scaleway or refresh failed"
        add_result "infrastructure" "scaleway_connectivity" "fail" "Scaleway API connectivity issue" ""
    fi

    cd - &>/dev/null

    log INFO "✅ Infrastructure validation completed for: $env_name"
}

check_cluster() {
    local env_name="$1"

    log STEP "Validating Kubernetes cluster for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log FAIL "Kubeconfig not found: $kubeconfig"
        add_result "cluster" "kubeconfig" "fail" "Kubeconfig file not found" "$kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Test cluster connectivity
    if timeout "$TIMEOUT" kubectl cluster-info &>/dev/null; then
        log PASS "Kubernetes cluster is accessible"
        add_result "cluster" "connectivity" "pass" "Cluster API accessible" ""
    else
        log FAIL "Cannot connect to Kubernetes cluster"
        add_result "cluster" "connectivity" "fail" "Cluster API not accessible" ""
        return 1
    fi

    # Check nodes
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready " | wc -l || echo "0")

    if [[ "$ready_nodes" -gt 0 ]]; then
        log PASS "Cluster has $ready_nodes/$node_count nodes ready"
        add_result "cluster" "nodes" "pass" "$ready_nodes/$node_count nodes ready" "$ready_nodes:$node_count"
    else
        log FAIL "No ready nodes found"
        add_result "cluster" "nodes" "fail" "No ready nodes" "$ready_nodes:$node_count"
    fi

    # Check system pods
    local system_pods_running=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep " Running " | wc -l || echo "0")
    local total_system_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "$system_pods_running" -eq "$total_system_pods" && "$system_pods_running" -gt 0 ]]; then
        log PASS "All $system_pods_running system pods are running"
        add_result "cluster" "system_pods" "pass" "All system pods running" "$system_pods_running:$total_system_pods"
    else
        log WARN "$system_pods_running/$total_system_pods system pods running"
        add_result "cluster" "system_pods" "warn" "Some system pods not running" "$system_pods_running:$total_system_pods"
    fi

    # Check storage classes
    local storage_classes=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$storage_classes" -gt 0 ]]; then
        log PASS "$storage_classes storage classes available"
        add_result "cluster" "storage" "pass" "$storage_classes storage classes available" "$storage_classes"
    else
        log WARN "No storage classes found"
        add_result "cluster" "storage" "warn" "No storage classes found" "$storage_classes"
    fi

    # Performance check if detailed validation requested
    if [[ "$DETAILED" == "true" || "$COMPREHENSIVE" == "true" ]]; then
        log INFO "Running cluster performance checks..."

        # Check node resource utilization
        if kubectl top nodes &>/dev/null; then
            log PASS "Node metrics available"
            add_result "cluster" "metrics" "pass" "Node metrics accessible" ""
        else
            log WARN "Node metrics not available"
            add_result "cluster" "metrics" "warn" "Node metrics not accessible" ""
        fi
    fi

    log INFO "✅ Cluster validation completed for: $env_name"
}

check_coder() {
    local env_name="$1"

    log STEP "Validating Coder application for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log FAIL "Kubeconfig not found for Coder validation"
        add_result "coder" "kubeconfig" "fail" "Kubeconfig not found" ""
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Check if Coder namespace exists
    if kubectl get namespace coder &>/dev/null; then
        log PASS "Coder namespace exists"
        add_result "coder" "namespace" "pass" "Coder namespace exists" ""
    else
        log FAIL "Coder namespace not found"
        add_result "coder" "namespace" "fail" "Coder namespace not found" ""
        return 1
    fi

    # Check Coder pods
    local coder_pods_running=$(kubectl get pods -n coder --no-headers 2>/dev/null | grep " Running " | wc -l || echo "0")
    local total_coder_pods=$(kubectl get pods -n coder --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "$coder_pods_running" -gt 0 ]]; then
        log PASS "$coder_pods_running/$total_coder_pods Coder pods running"
        add_result "coder" "pods" "pass" "$coder_pods_running/$total_coder_pods pods running" "$coder_pods_running:$total_coder_pods"
    else
        log FAIL "No Coder pods running"
        add_result "coder" "pods" "fail" "No Coder pods running" "$coder_pods_running:$total_coder_pods"
        return 1
    fi

    # Check Coder service
    if kubectl get service -n coder &>/dev/null; then
        local coder_service=$(kubectl get service -n coder --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
        if [[ -n "$coder_service" ]]; then
            log PASS "Coder service '$coder_service' exists"
            add_result "coder" "service" "pass" "Coder service exists" "$coder_service"
        else
            log FAIL "No Coder service found"
            add_result "coder" "service" "fail" "No Coder service found" ""
        fi
    fi

    # Check Coder URL accessibility
    local env_dir="${PROJECT_ROOT}/environments/${env_name}"
    if [[ -f "${env_dir}/terraform.tfstate" ]]; then
        cd "$env_dir"
        local coder_url=$(terraform output -raw access_url 2>/dev/null || terraform output -raw coder_url 2>/dev/null || echo "")
        cd - &>/dev/null

        if [[ -n "$coder_url" ]]; then
            if timeout 30 curl -ksf "$coder_url" &>/dev/null; then
                log PASS "Coder web interface is accessible"
                add_result "coder" "web_access" "pass" "Web interface accessible" "$coder_url"
            else
                log FAIL "Coder web interface not accessible"
                add_result "coder" "web_access" "fail" "Web interface not accessible" "$coder_url"
            fi
        else
            log WARN "Could not determine Coder URL from Terraform outputs"
            add_result "coder" "web_access" "warn" "Could not determine Coder URL" ""
        fi
    fi

    # Check if Coder CLI can connect (if available)
    if command -v coder &>/dev/null; then
        local env_dir="${PROJECT_ROOT}/environments/${env_name}"
        cd "$env_dir" 2>/dev/null || true
        local coder_url=$(terraform output -raw access_url 2>/dev/null || terraform output -raw coder_url 2>/dev/null || echo "")

        if [[ -n "$coder_url" ]]; then
            export CODER_URL="$coder_url"
            if timeout 30 coder version &>/dev/null; then
                log PASS "Coder CLI can connect to server"
                add_result "coder" "cli_connectivity" "pass" "CLI can connect to server" ""

                # Check templates if comprehensive validation
                if [[ "$COMPREHENSIVE" == "true" ]]; then
                    local template_count=$(coder templates list 2>/dev/null | tail -n +2 | wc -l || echo "0")
                    if [[ "$template_count" -gt 0 ]]; then
                        log PASS "$template_count workspace templates available"
                        add_result "coder" "templates" "pass" "$template_count templates available" "$template_count"
                    else
                        log WARN "No workspace templates found"
                        add_result "coder" "templates" "warn" "No templates found" "$template_count"
                    fi
                fi
            else
                log WARN "Coder CLI cannot connect to server"
                add_result "coder" "cli_connectivity" "warn" "CLI cannot connect" ""
            fi
        fi
        cd - &>/dev/null || true
    fi

    log INFO "✅ Coder validation completed for: $env_name"
}

check_database() {
    local env_name="$1"

    log STEP "Validating database for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping database validation"
        add_result "database" "kubeconfig" "warn" "Kubeconfig not found" ""
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    # Check for database secrets
    local db_secret=""
    if kubectl get secret coder-db-secret -n coder &>/dev/null; then
        db_secret="coder-db-secret"
    elif kubectl get secret coder-database -n coder &>/dev/null; then
        db_secret="coder-database"
    else
        log WARN "No database secret found"
        add_result "database" "secret" "warn" "No database secret found" ""
        return 0
    fi

    log PASS "Database secret '$db_secret' exists"
    add_result "database" "secret" "pass" "Database secret exists" "$db_secret"

    # Extract database connection details
    local db_host=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.host}' 2>/dev/null | base64 -d || echo "")
    local db_user=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "postgres")
    local db_name=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.database}' 2>/dev/null | base64 -d || echo "coder")
    local db_pass=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

    if [[ -n "$db_host" && -n "$db_pass" ]]; then
        log PASS "Database credentials available"
        add_result "database" "credentials" "pass" "Database credentials available" "$db_host:$db_user:$db_name"

        # Test database connectivity
        if kubectl run db-test-$(date +%s) \
            --image=postgres:15 \
            --rm -i \
            --restart=Never \
            --env="PGPASSWORD=$db_pass" \
            --command -- psql \
            -h "$db_host" \
            -U "$db_user" \
            -d "$db_name" \
            -c "SELECT 1;" &>/dev/null; then
            log PASS "Database is accessible and responsive"
            add_result "database" "connectivity" "pass" "Database accessible" ""
        else
            log FAIL "Cannot connect to database"
            add_result "database" "connectivity" "fail" "Database not accessible" ""
        fi

        # Performance check if detailed validation
        if [[ "$DETAILED" == "true" || "$COMPREHENSIVE" == "true" ]]; then
            log INFO "Running database performance checks..."

            local query_result=$(kubectl run db-perf-$(date +%s) \
                --image=postgres:15 \
                --rm -i \
                --restart=Never \
                --env="PGPASSWORD=$db_pass" \
                --command -- psql \
                -h "$db_host" \
                -U "$db_user" \
                -d "$db_name" \
                -t -c "SELECT COUNT(*) FROM information_schema.tables;" 2>/dev/null | tr -d '[:space:]' || echo "0")

            if [[ "$query_result" -gt 0 ]]; then
                log PASS "Database contains $query_result tables"
                add_result "database" "performance" "pass" "Database responsive with $query_result tables" "$query_result"
            else
                log WARN "Database query returned unexpected result: $query_result"
                add_result "database" "performance" "warn" "Unexpected query result" "$query_result"
            fi
        fi
    else
        log FAIL "Incomplete database credentials"
        add_result "database" "credentials" "fail" "Incomplete database credentials" ""
    fi

    log INFO "✅ Database validation completed for: $env_name"
}

check_monitoring() {
    local env_name="$1"

    log STEP "Validating monitoring stack for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found, skipping monitoring validation"
        add_result "monitoring" "kubeconfig" "warn" "Kubeconfig not found" ""
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    # Check if monitoring namespace exists
    if kubectl get namespace monitoring &>/dev/null; then
        log PASS "Monitoring namespace exists"
        add_result "monitoring" "namespace" "pass" "Monitoring namespace exists" ""
    else
        log INFO "Monitoring namespace not found (monitoring may not be enabled)"
        add_result "monitoring" "namespace" "info" "Monitoring not enabled" ""
        return 0
    fi

    # Check Prometheus
    if kubectl get pods -n monitoring -l app=prometheus &>/dev/null; then
        local prometheus_pods=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | grep " Running " | wc -l || echo "0")
        if [[ "$prometheus_pods" -gt 0 ]]; then
            log PASS "Prometheus is running ($prometheus_pods pods)"
            add_result "monitoring" "prometheus" "pass" "Prometheus running" "$prometheus_pods"
        else
            log FAIL "Prometheus pods not running"
            add_result "monitoring" "prometheus" "fail" "Prometheus not running" ""
        fi
    else
        log WARN "Prometheus not found in monitoring namespace"
        add_result "monitoring" "prometheus" "warn" "Prometheus not found" ""
    fi

    # Check Grafana
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana &>/dev/null; then
        local grafana_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep " Running " | wc -l || echo "0")
        if [[ "$grafana_pods" -gt 0 ]]; then
            log PASS "Grafana is running ($grafana_pods pods)"
            add_result "monitoring" "grafana" "pass" "Grafana running" "$grafana_pods"
        else
            log FAIL "Grafana pods not running"
            add_result "monitoring" "grafana" "fail" "Grafana not running" ""
        fi
    else
        log WARN "Grafana not found in monitoring namespace"
        add_result "monitoring" "grafana" "warn" "Grafana not found" ""
    fi

    # Test monitoring endpoints if comprehensive
    if [[ "$COMPREHENSIVE" == "true" ]]; then
        log INFO "Testing monitoring endpoints..."

        # Port-forward to test Prometheus
        if kubectl port-forward -n monitoring svc/prometheus-server 9090:80 --address='127.0.0.1' &>/dev/null &
        then
            local pf_pid=$!
            sleep 3
            if timeout 10 curl -sf http://127.0.0.1:9090/-/healthy &>/dev/null; then
                log PASS "Prometheus endpoint is healthy"
                add_result "monitoring" "prometheus_endpoint" "pass" "Prometheus endpoint healthy" ""
            else
                log WARN "Prometheus endpoint health check failed"
                add_result "monitoring" "prometheus_endpoint" "warn" "Prometheus endpoint unhealthy" ""
            fi
            kill $pf_pid 2>/dev/null || true
        fi
    fi

    log INFO "✅ Monitoring validation completed for: $env_name"
}

check_network() {
    local env_name="$1"

    log STEP "Validating network and connectivity for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log FAIL "Kubeconfig not found for network validation"
        add_result "network" "kubeconfig" "fail" "Kubeconfig not found" ""
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Get ingress information
    local ingresses=$(kubectl get ingress -n coder --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$ingresses" -gt 0 ]]; then
        log PASS "$ingresses ingress(es) configured"
        add_result "network" "ingress" "pass" "$ingresses ingresses configured" "$ingresses"

        # Check specific ingress hosts
        kubectl get ingress -n coder -o jsonpath='{.items[*].spec.rules[*].host}' 2>/dev/null | tr ' ' '\n' | while read -r host; do
            if [[ -n "$host" ]]; then
                if timeout 10 nslookup "$host" &>/dev/null; then
                    log PASS "DNS resolution successful for: $host"
                    add_result "network" "dns_$host" "pass" "DNS resolution successful" "$host"
                else
                    log WARN "DNS resolution failed for: $host"
                    add_result "network" "dns_$host" "warn" "DNS resolution failed" "$host"
                fi
            fi
        done
    else
        log WARN "No ingresses found"
        add_result "network" "ingress" "warn" "No ingresses found" ""
    fi

    # Check services
    local services=$(kubectl get services -n coder --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$services" -gt 0 ]]; then
        log PASS "$services service(s) configured"
        add_result "network" "services" "pass" "$services services configured" "$services"
    else
        log WARN "No services found in coder namespace"
        add_result "network" "services" "warn" "No services found" ""
    fi

    # Check certificates if available
    if kubectl get certificates -n coder &>/dev/null; then
        local ready_certs=$(kubectl get certificates -n coder --no-headers 2>/dev/null | grep -c " True " || echo "0")
        local total_certs=$(kubectl get certificates -n coder --no-headers 2>/dev/null | wc -l || echo "0")

        if [[ "$ready_certs" -eq "$total_certs" && "$ready_certs" -gt 0 ]]; then
            log PASS "All $ready_certs certificates are ready"
            add_result "network" "certificates" "pass" "All certificates ready" "$ready_certs:$total_certs"
        else
            log WARN "$ready_certs/$total_certs certificates ready"
            add_result "network" "certificates" "warn" "Some certificates not ready" "$ready_certs:$total_certs"
        fi
    fi

    log INFO "✅ Network validation completed for: $env_name"
}

check_security() {
    local env_name="$1"

    # Security audit runs when explicitly called as a component

    log STEP "Running security audit for environment: $env_name"

    local security_audit_script="${PROJECT_ROOT}/scripts/utils/security-audit.sh"
    if [[ ! -f "$security_audit_script" ]]; then
        log WARN "Security audit script not found: $security_audit_script"
        add_result "security" "audit_script" "warn" "Security audit script not found" ""
        return 0
    fi

    # Run security audit and capture results
    local audit_output_file="/tmp/security-audit-${env_name}-$(date +%s).json"
    local audit_mode=""

    if [[ "$COMPREHENSIVE" == "true" ]]; then
        audit_mode="--comprehensive"
    elif [[ "$DETAILED" == "true" ]]; then
        audit_mode="--detailed"
    fi

    if bash "$security_audit_script" --env="$env_name" $audit_mode --format=json --output="$audit_output_file" &>/dev/null; then
        log PASS "Security audit completed successfully"
        add_result "security" "audit_execution" "pass" "Security audit completed" "$audit_output_file"

        # Parse security audit results and include summary
        if [[ -f "$audit_output_file" ]]; then
            local failed_checks=$(jq -r '.security_audit_report.summary.failed // 0' "$audit_output_file" 2>/dev/null || echo "0")
            local passed_checks=$(jq -r '.security_audit_report.summary.passed // 0' "$audit_output_file" 2>/dev/null || echo "0")
            local success_rate=$(jq -r '.security_audit_report.summary.success_rate // 0' "$audit_output_file" 2>/dev/null || echo "0")
            local risk_score=$(jq -r '.security_audit_report.summary.risk_score // 0' "$audit_output_file" 2>/dev/null || echo "0")

            if [[ "$failed_checks" -eq 0 ]]; then
                add_result "security" "audit_results" "pass" "Security audit: $success_rate% success rate" "passed=$passed_checks, risk_score=$risk_score"
                log PASS "Security audit results: $success_rate% success rate, risk score: $risk_score"
            elif [[ "$failed_checks" -le 2 ]]; then
                add_result "security" "audit_results" "warn" "Security audit: $success_rate% success rate, $failed_checks issues" "passed=$passed_checks, failed=$failed_checks, risk_score=$risk_score"
                log WARN "Security audit results: $success_rate% success rate, $failed_checks issues found, risk score: $risk_score"
            else
                add_result "security" "audit_results" "fail" "Security audit: $success_rate% success rate, $failed_checks issues" "passed=$passed_checks, failed=$failed_checks, risk_score=$risk_score"
                log FAIL "Security audit results: $success_rate% success rate, $failed_checks issues found, risk score: $risk_score"
            fi

            # Clean up temp file
            rm -f "$audit_output_file"
        fi
    else
        log FAIL "Security audit failed to complete"
        add_result "security" "audit_execution" "fail" "Security audit execution failed" ""
    fi

    log INFO "✅ Security audit completed for: $env_name"
}

run_quick_checks() {
    local env_name="$1"

    log STEP "Running quick checks for environment: $env_name"

    # Just test basic connectivity
    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ -f "$kubeconfig" ]]; then
        export KUBECONFIG="$kubeconfig"
        if timeout 30 kubectl cluster-info &>/dev/null; then
            log PASS "Cluster connectivity: OK"
            add_result "quick" "cluster_connectivity" "pass" "Cluster accessible" ""
        else
            log FAIL "Cluster connectivity: FAILED"
            add_result "quick" "cluster_connectivity" "fail" "Cluster not accessible" ""
            return 1
        fi

        # Quick pod check
        local running_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep " Running " | wc -l || echo "0")
        if [[ "$running_pods" -gt 0 ]]; then
            log PASS "Running pods: $running_pods"
            add_result "quick" "running_pods" "pass" "$running_pods pods running" "$running_pods"
        else
            log WARN "No running pods found"
            add_result "quick" "running_pods" "warn" "No running pods" "$running_pods"
        fi
    else
        log FAIL "Kubeconfig not found: $kubeconfig"
        add_result "quick" "kubeconfig" "fail" "Kubeconfig not found" ""
        return 1
    fi

    log INFO "✅ Quick checks completed for: $env_name"
}

generate_report() {
    if [[ -z "$OUTPUT_FILE" ]]; then
        return 0
    fi

    log STEP "Generating validation report..."

    local total_checks=0
    local passed_checks=0
    local failed_checks=0
    local warn_checks=0

    cat > "$OUTPUT_FILE" <<EOF
{
  "validation_report": {
    "environment": "$ENVIRONMENT",
    "timestamp": "$(date -Iseconds)",
    "validator_version": "1.0.0",
    "validation_type": "$([ "$QUICK_CHECK" == "true" ] && echo "quick" || ([ "$COMPREHENSIVE" == "true" ] && echo "comprehensive" || echo "standard"))",
    "components_checked": "$COMPONENTS",
    "results": [
EOF

    local first=true
    if [[ ${#VALIDATION_RESULTS[@]} -gt 0 ]]; then
        for result in "${VALIDATION_RESULTS[@]}"; do
            IFS='|' read -r component check status message details <<< "$result"

            [[ "$first" == "true" ]] && first=false || echo "," >> "$OUTPUT_FILE"

        cat >> "$OUTPUT_FILE" <<EOF
      {
        "component": "$component",
        "check": "$check",
        "status": "$status",
        "message": "$message",
        "details": "$details",
        "timestamp": "$(date -Iseconds)"
      }
EOF

        ((total_checks++))
        case "$status" in
            pass) ((passed_checks++)) ;;
            fail) ((failed_checks++)) ;;
            warn) ((warn_checks++)) ;;
        esac
        done
    fi

    cat >> "$OUTPUT_FILE" <<EOF
    ],
    "summary": {
      "total_checks": $total_checks,
      "passed": $passed_checks,
      "failed": $failed_checks,
      "warnings": $warn_checks,
      "success_rate": $(( total_checks > 0 ? (passed_checks * 100) / total_checks : 0 ))
    }
  }
}
EOF

    log PASS "Validation report saved to: $OUTPUT_FILE"
}

print_summary() {
    log STEP "Validation Summary"

    local total_checks=0
    local passed_checks=0
    local failed_checks=0
    local warn_checks=0

    if [[ ${#VALIDATION_RESULTS[@]} -gt 0 ]]; then
        for result in "${VALIDATION_RESULTS[@]}"; do
            IFS='|' read -r component check status message details <<< "$result"
            ((total_checks++))
            case "$status" in
                pass) ((passed_checks++)) ;;
                fail) ((failed_checks++)) ;;
                warn) ((warn_checks++)) ;;
            esac
        done
    fi

    local success_rate=0
    if [[ $total_checks -gt 0 ]]; then
        success_rate=$(( (passed_checks * 100) / total_checks ))
    fi

    echo
    if [[ "$failed_checks" -eq 0 ]]; then
        echo -e "${GREEN}✅ Environment validation completed successfully! ✅${NC}"
    else
        echo -e "${YELLOW}⚠️  Environment validation completed with issues ⚠️${NC}"
    fi
    echo

    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Total Checks:${NC} $total_checks"
    echo -e "${GREEN}Passed:${NC} $passed_checks"
    if [[ "$failed_checks" -gt 0 ]]; then
        echo -e "${RED}Failed:${NC} $failed_checks"
    fi
    if [[ "$warn_checks" -gt 0 ]]; then
        echo -e "${YELLOW}Warnings:${NC} $warn_checks"
    fi
    echo -e "${WHITE}Success Rate:${NC} $success_rate%"

    if [[ "$failed_checks" -gt 0 ]]; then
        echo
        echo -e "${YELLOW}❌ Failed Checks:${NC}"
        if [[ ${#VALIDATION_RESULTS[@]} -gt 0 ]]; then
            for result in "${VALIDATION_RESULTS[@]}"; do
                IFS='|' read -r component check status message details <<< "$result"
                if [[ "$status" == "fail" ]]; then
                    echo -e "   ${RED}✗${NC} $component/$check: $message"
                fi
            done
        fi
    fi

    if [[ "$warn_checks" -gt 0 && "$failed_checks" -eq 0 ]]; then
        echo
        echo -e "${YELLOW}⚠️  Warnings:${NC}"
        if [[ ${#VALIDATION_RESULTS[@]} -gt 0 ]]; then
            for result in "${VALIDATION_RESULTS[@]}"; do
                IFS='|' read -r component check status message details <<< "$result"
                if [[ "$status" == "warn" ]]; then
                    echo -e "   ${YELLOW}!${NC} $component/$check: $message"
                fi
            done
        fi
    fi

    echo
    echo -e "${YELLOW}📋 Next Steps:${NC}"
    if [[ "$failed_checks" -gt 0 ]]; then
        echo "   • Address failed checks before proceeding"
        echo "   • Check logs for detailed error information"
        echo "   • Run validation again after fixes"
    else
        echo "   • Environment appears healthy"
        echo "   • Monitor ongoing health with regular validations"
        echo "   • Consider enabling more comprehensive checks"
    fi

    [[ -n "$OUTPUT_FILE" ]] && echo "   • Review detailed report: $OUTPUT_FILE"

    echo

    return $(( failed_checks > 0 ? 1 : 0 ))
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --quick)
                QUICK_CHECK=true
                shift
                ;;
            --detailed)
                DETAILED=true
                shift
                ;;
            --comprehensive)
                COMPREHENSIVE=true
                DETAILED=true
                shift
                ;;
            --security)
                SECURITY_AUDIT=true
                shift
                ;;
            --components=*)
                COMPONENTS="${1#*=}"
                shift
                ;;
            --post-restore-checks)
                POST_RESTORE_CHECKS=true
                DETAILED=true
                shift
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
                shift
                ;;
            --output=*)
                OUTPUT_FILE="${1#*=}"
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

    if [[ -z "$ENVIRONMENT" ]]; then
        log ERROR "Environment is required. Use --env=ENV"
        print_usage
        exit 1
    fi

    print_banner
    setup_logging

    log INFO "Starting validation for environment: $ENVIRONMENT"
    [[ "$QUICK_CHECK" == "true" ]] && log INFO "🚀 Running in quick check mode"
    [[ "$DETAILED" == "true" ]] && log INFO "🔍 Running detailed validation"
    [[ "$COMPREHENSIVE" == "true" ]] && log INFO "🎯 Running comprehensive validation"

    validate_environment

    # Process environments
    if [[ "$ENVIRONMENT" == "all" ]]; then
        for env in dev staging prod; do
            if [[ -d "${PROJECT_ROOT}/environments/$env" ]]; then
                log INFO "Validating environment: $env"

                if [[ "$QUICK_CHECK" == "true" ]]; then
                    run_quick_checks "$env"
                else
                    # Parse components to check
                    IFS=',' read -ra COMPONENTS_ARRAY <<< "$COMPONENTS"
                    for component in "${COMPONENTS_ARRAY[@]}"; do
                        case "$component" in
                            infrastructure|all) check_infrastructure "$env" ;;
                            cluster|all) check_cluster "$env" ;;
                            coder|all) check_coder "$env" ;;
                            database|all) check_database "$env" ;;
                            monitoring|all) check_monitoring "$env" ;;
                            network|all) check_network "$env" ;;
                            security|all) check_security "$env" ;;
                        esac
                    done

                    # If components=all, run all checks
                    if [[ "$COMPONENTS" == "all" ]]; then
                        check_infrastructure "$env"
                        check_cluster "$env"
                        check_coder "$env"
                        check_database "$env"
                        check_monitoring "$env"
                        check_network "$env"
                        if [[ "$SECURITY_AUDIT" == "true" ]]; then
                            check_security "$env"
                        fi
                    fi
                fi
            else
                log WARN "Environment directory not found: $env"
            fi
        done
    else
        if [[ "$QUICK_CHECK" == "true" ]]; then
            run_quick_checks "$ENVIRONMENT"
        else
            # Parse components to check
            IFS=',' read -ra COMPONENTS_ARRAY <<< "$COMPONENTS"
            for component in "${COMPONENTS_ARRAY[@]}"; do
                case "$component" in
                    infrastructure|all) check_infrastructure "$ENVIRONMENT" ;;
                    cluster|all) check_cluster "$ENVIRONMENT" ;;
                    coder|all) check_coder "$ENVIRONMENT" ;;
                    database|all) check_database "$ENVIRONMENT" ;;
                    monitoring|all) check_monitoring "$ENVIRONMENT" ;;
                    network|all) check_network "$ENVIRONMENT" ;;
                    security|all) check_security "$ENVIRONMENT" ;;
                esac
            done

            # If components=all, run all checks
            if [[ "$COMPONENTS" == "all" ]]; then
                check_infrastructure "$ENVIRONMENT"
                check_cluster "$ENVIRONMENT"
                check_coder "$ENVIRONMENT"
                check_database "$ENVIRONMENT"
                check_monitoring "$ENVIRONMENT"
                check_network "$ENVIRONMENT"
                if [[ "$SECURITY_AUDIT" == "true" ]]; then
                    check_security "$ENVIRONMENT"
                fi
            fi
        fi
    fi

    generate_report
    print_summary
}

# Run main function with all arguments
main "$@"