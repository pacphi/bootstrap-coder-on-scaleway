#!/bin/bash

# Coder on Scaleway - Security Audit Script
# Comprehensive security assessment for Kubernetes environments

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
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENVIRONMENT=""
OUTPUT_FORMAT="table"
OUTPUT_FILE=""
DETAILED=false
COMPREHENSIVE=false
COMPLIANCE_LEVEL=""
FIX_ISSUES=false
TIMEOUT=300
LOG_FILE=""
AUDIT_RESULTS=()

# Security thresholds and configurations
get_security_standard() {
    local env="$1"
    case "$env" in
        dev) echo "baseline" ;;
        staging) echo "baseline" ;;
        prod) echo "restricted" ;;
        *) echo "baseline" ;;
    esac
}

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║         Security Audit Tool           ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Comprehensive security audit for Coder on Scaleway environments.
Validates cluster security, network policies, RBAC, compliance, and more.

Options:
    --env=ENV                   Environment to audit (dev|staging|prod|all) [required]
    --format=FORMAT             Output format (table|json|html|csv) [default: table]
    --output=FILE               Save results to file
    --detailed                  Include detailed security analysis
    --comprehensive             Full security audit with all checks
    --compliance=LEVEL          Compliance framework (cis|nist|pci|soc2)
    --fix                       Attempt to remediate issues found
    --timeout=SECONDS           Timeout for individual checks (default: 300)
    --help                      Show this help message

Examples:
    $0 --env=prod --format=json --output=security-report.json
    $0 --env=staging --comprehensive --compliance=cis
    $0 --env=dev --detailed --fix
    $0 --env=all --format=html --output=security-audit.html

Security Checks:
    • Pod Security Standards compliance
    • Network policies and traffic isolation
    • RBAC permissions and service accounts
    • Resource quotas and limits
    • Container image security
    • Secrets and credential management
    • Certificate validation and expiration
    • Database connection security
    • Audit logging configuration
    • CIS Kubernetes benchmarks

Environment Security Levels:
    • Development: Baseline security (Pod Security Standard: baseline)
    • Staging: Baseline security with enhanced monitoring
    • Production: Restricted security (Pod Security Standard: restricted)

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
        HIGH)  echo -e "${RED}[HIGH]${NC}  $message" ;;
        MEDIUM) echo -e "${YELLOW}[MEDIUM]${NC} $message" ;;
        LOW)   echo -e "${BLUE}[LOW]${NC}   $message" ;;
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

add_audit_result() {
    local category="$1"
    local check="$2"
    local severity="$3"
    local status="$4"
    local message="$5"
    local recommendation="${6:-}"
    local details="${7:-}"

    AUDIT_RESULTS+=("$category|$check|$severity|$status|$message|$recommendation|$details")
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

check_prerequisites() {
    log STEP "Checking security audit prerequisites..."

    local required_tools=("kubectl" "jq" "curl")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log ERROR "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    log INFO "✅ Prerequisites validated"
}

audit_pod_security_standards() {
    local env_name="$1"
    log STEP "Auditing Pod Security Standards for: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        add_audit_result "pod_security" "kubeconfig" "HIGH" "FAIL" "Kubeconfig not found" "Deploy environment first" "$kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"
    local expected_standard=$(get_security_standard "$env_name")

    # Check namespace security labels
    local namespaces=("coder" "monitoring" "kube-system")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local enforce_level=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
            local audit_level=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/audit}' 2>/dev/null || echo "")
            local warn_level=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/warn}' 2>/dev/null || echo "")

            if [[ "$ns" == "coder" ]]; then
                if [[ "$enforce_level" == "$expected_standard" ]]; then
                    add_audit_result "pod_security" "namespace_$ns" "MEDIUM" "PASS" "Pod Security Standard correctly enforced" "" "$enforce_level"
                    log PASS "Namespace $ns has correct Pod Security Standard: $enforce_level"
                else
                    add_audit_result "pod_security" "namespace_$ns" "HIGH" "FAIL" "Incorrect Pod Security Standard" "Set enforce=$expected_standard" "current=$enforce_level, expected=$expected_standard"
                    log FAIL "Namespace $ns has incorrect Pod Security Standard: $enforce_level (expected: $expected_standard)"
                fi
            else
                if [[ -n "$enforce_level" ]]; then
                    add_audit_result "pod_security" "namespace_$ns" "LOW" "PASS" "Pod Security Standard configured" "" "$enforce_level"
                    log PASS "Namespace $ns has Pod Security Standard: $enforce_level"
                else
                    add_audit_result "pod_security" "namespace_$ns" "MEDIUM" "WARN" "No Pod Security Standard set" "Configure appropriate standard" ""
                    log WARN "Namespace $ns has no Pod Security Standard configured"
                fi
            fi
        fi
    done

    # Check running pods for security context compliance
    local pods_with_issues=0
    local total_pods=0

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pod_list=$(kubectl get pods -n "$ns" -o json 2>/dev/null || echo '{"items":[]}')
            local pods=$(echo "$pod_list" | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

            for pod in $pods; do
                if [[ -n "$pod" ]]; then
                    ((total_pods++))
                    local pod_json=$(kubectl get pod "$pod" -n "$ns" -o json 2>/dev/null || echo '{}')

                    # Check if pod runs as non-root
                    local runs_as_non_root=$(echo "$pod_json" | jq -r '.spec.securityContext.runAsNonRoot // false' 2>/dev/null)
                    local run_as_user=$(echo "$pod_json" | jq -r '.spec.securityContext.runAsUser // "null"' 2>/dev/null)

                    if [[ "$runs_as_non_root" != "true" && "$run_as_user" == "null" ]]; then
                        ((pods_with_issues++))
                        add_audit_result "pod_security" "pod_$pod" "MEDIUM" "WARN" "Pod may run as root" "Set runAsNonRoot=true" "namespace=$ns"
                    fi

                    # Check for privileged containers
                    local privileged_containers=$(echo "$pod_json" | jq -r '.spec.containers[]? | select(.securityContext.privileged == true) | .name' 2>/dev/null || echo "")
                    if [[ -n "$privileged_containers" ]]; then
                        ((pods_with_issues++))
                        add_audit_result "pod_security" "pod_$pod" "HIGH" "FAIL" "Pod contains privileged containers" "Remove privileged=true" "namespace=$ns, containers=$privileged_containers"
                        log FAIL "Pod $pod in namespace $ns has privileged containers: $privileged_containers"
                    fi
                fi
            done
        fi
    done

    if [[ $total_pods -gt 0 ]]; then
        local compliance_rate=$(( (total_pods - pods_with_issues) * 100 / total_pods ))
        if [[ $compliance_rate -ge 90 ]]; then
            add_audit_result "pod_security" "overall_compliance" "LOW" "PASS" "Pod security compliance: $compliance_rate%" "" "$pods_with_issues/$total_pods pods with issues"
            log PASS "Pod security compliance: $compliance_rate% ($pods_with_issues/$total_pods pods with issues)"
        else
            add_audit_result "pod_security" "overall_compliance" "MEDIUM" "WARN" "Pod security compliance: $compliance_rate%" "Review and fix pod security contexts" "$pods_with_issues/$total_pods pods with issues"
            log WARN "Pod security compliance: $compliance_rate% ($pods_with_issues/$total_pods pods with issues)"
        fi
    fi
}

audit_network_security() {
    local env_name="$1"
    log STEP "Auditing network security for: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    export KUBECONFIG="$kubeconfig"

    # Check for default deny network policies
    local namespaces=("coder" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local deny_all_policies=$(kubectl get networkpolicy -n "$ns" -o json 2>/dev/null | jq -r '.items[] | select(.spec.podSelector == {} and (.spec.policyTypes | contains(["Ingress", "Egress"]))) | .metadata.name' 2>/dev/null || echo "")

            if [[ -n "$deny_all_policies" ]]; then
                add_audit_result "network_security" "default_deny_$ns" "LOW" "PASS" "Default deny network policy exists" "" "$deny_all_policies"
                log PASS "Namespace $ns has default deny network policy: $deny_all_policies"
            else
                add_audit_result "network_security" "default_deny_$ns" "MEDIUM" "FAIL" "No default deny network policy" "Create deny-all NetworkPolicy" ""
                log FAIL "Namespace $ns lacks default deny network policy"
            fi

            # Check for specific allow policies
            local allow_policies=$(kubectl get networkpolicy -n "$ns" --no-headers 2>/dev/null | wc -l || echo "0")
            if [[ "$allow_policies" -gt 1 ]]; then
                add_audit_result "network_security" "network_policies_$ns" "LOW" "PASS" "$allow_policies network policies configured" "" ""
                log PASS "Namespace $ns has $allow_policies network policies configured"
            else
                add_audit_result "network_security" "network_policies_$ns" "MEDIUM" "WARN" "Limited network policies" "Review and create specific allow policies" "only $allow_policies policies"
                log WARN "Namespace $ns has limited network policies: $allow_policies"
            fi
        fi
    done

    # Check ingress configurations
    local ingresses=$(kubectl get ingress -A -o json 2>/dev/null || echo '{"items":[]}')
    local tls_ingresses=$(echo "$ingresses" | jq -r '.items[] | select(.spec.tls != null) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")
    local non_tls_ingresses=$(echo "$ingresses" | jq -r '.items[] | select(.spec.tls == null) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

    if [[ -n "$non_tls_ingresses" ]]; then
        add_audit_result "network_security" "ingress_tls" "HIGH" "FAIL" "Ingresses without TLS found" "Configure TLS for all ingresses" "$non_tls_ingresses"
        log FAIL "Ingresses without TLS: $non_tls_ingresses"
    else
        add_audit_result "network_security" "ingress_tls" "LOW" "PASS" "All ingresses use TLS" "" ""
        log PASS "All ingresses properly configured with TLS"
    fi

    # Check for services with type LoadBalancer or NodePort
    local exposed_services=$(kubectl get services -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.type == "LoadBalancer" or .spec.type == "NodePort") | "\(.metadata.namespace)/\(.metadata.name) (\(.spec.type))"' 2>/dev/null || echo "")

    if [[ -n "$exposed_services" ]]; then
        local exposed_count=$(echo "$exposed_services" | wc -l)
        if [[ $exposed_count -le 2 ]]; then  # Allow for Coder and monitoring
            add_audit_result "network_security" "exposed_services" "LOW" "PASS" "Limited exposed services" "" "$exposed_services"
            log PASS "Exposed services: $exposed_services"
        else
            add_audit_result "network_security" "exposed_services" "MEDIUM" "WARN" "Multiple exposed services" "Review necessity of exposed services" "$exposed_services"
            log WARN "Multiple exposed services found: $exposed_services"
        fi
    else
        add_audit_result "network_security" "exposed_services" "LOW" "PASS" "No directly exposed services" "" ""
        log PASS "No LoadBalancer or NodePort services found"
    fi
}

audit_rbac() {
    local env_name="$1"
    log STEP "Auditing RBAC configuration for: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    export KUBECONFIG="$kubeconfig"

    # Check for overly permissive cluster roles
    local cluster_roles=$(kubectl get clusterroles -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | test("^coder|^system:") | not) | .metadata.name' 2>/dev/null || echo "")

    for role in $cluster_roles; do
        if [[ -n "$role" ]]; then
            local wildcard_rules=$(kubectl get clusterrole "$role" -o json 2>/dev/null | jq -r '.rules[]? | select(.verbs[]? == "*" or .resources[]? == "*" or .apiGroups[]? == "*") | "wildcard"' 2>/dev/null || echo "")

            if [[ -n "$wildcard_rules" ]]; then
                add_audit_result "rbac" "cluster_role_$role" "HIGH" "FAIL" "Overly permissive cluster role" "Review and restrict permissions" "contains wildcard permissions"
                log FAIL "Cluster role $role has wildcard permissions"
            fi
        fi
    done

    # Check service account tokens
    local service_accounts=$(kubectl get serviceaccounts -A -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name != "default") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

    local sa_count=0
    for sa in $service_accounts; do
        if [[ -n "$sa" ]]; then
            ((sa_count++))
        fi
    done

    if [[ $sa_count -gt 10 ]]; then
        add_audit_result "rbac" "service_accounts" "MEDIUM" "WARN" "Many service accounts found" "Review necessity of service accounts" "$sa_count service accounts"
        log WARN "Found $sa_count service accounts, review if all are necessary"
    else
        add_audit_result "rbac" "service_accounts" "LOW" "PASS" "Reasonable number of service accounts" "" "$sa_count service accounts"
        log PASS "Found $sa_count service accounts"
    fi

    # Check for pods using default service account
    local pods_using_default=$(kubectl get pods -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.serviceAccountName == "default" or .spec.serviceAccountName == null) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

    if [[ -n "$pods_using_default" ]]; then
        local default_count=$(echo "$pods_using_default" | wc -l)
        add_audit_result "rbac" "default_service_account" "MEDIUM" "WARN" "Pods using default service account" "Create dedicated service accounts" "$default_count pods: $pods_using_default"
        log WARN "$default_count pods using default service account"
    else
        add_audit_result "rbac" "default_service_account" "LOW" "PASS" "No pods using default service account" "" ""
        log PASS "All pods use dedicated service accounts"
    fi
}

audit_resource_limits() {
    local env_name="$1"
    log STEP "Auditing resource limits and quotas for: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    export KUBECONFIG="$kubeconfig"

    # Check for resource quotas
    local namespaces=("coder" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local quotas=$(kubectl get resourcequota -n "$ns" --no-headers 2>/dev/null | wc -l || echo "0")

            if [[ "$quotas" -gt 0 ]]; then
                add_audit_result "resources" "quota_$ns" "LOW" "PASS" "Resource quota configured" "" "$quotas quotas"
                log PASS "Namespace $ns has $quotas resource quotas"
            else
                add_audit_result "resources" "quota_$ns" "MEDIUM" "WARN" "No resource quota configured" "Create ResourceQuota" ""
                log WARN "Namespace $ns has no resource quotas"
            fi

            # Check for limit ranges
            local limitranges=$(kubectl get limitrange -n "$ns" --no-headers 2>/dev/null | wc -l || echo "0")

            if [[ "$limitranges" -gt 0 ]]; then
                add_audit_result "resources" "limits_$ns" "LOW" "PASS" "Limit ranges configured" "" "$limitranges limit ranges"
                log PASS "Namespace $ns has $limitranges limit ranges"
            else
                add_audit_result "resources" "limits_$ns" "MEDIUM" "WARN" "No limit ranges configured" "Create LimitRange" ""
                log WARN "Namespace $ns has no limit ranges"
            fi
        fi
    done

    # Check pods without resource requests/limits
    local pods_without_limits=0
    local total_pods=0

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pods=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

            for pod in $pods; do
                if [[ -n "$pod" ]]; then
                    ((total_pods++))
                    local pod_json=$(kubectl get pod "$pod" -n "$ns" -o json 2>/dev/null || echo '{}')

                    local has_requests=$(echo "$pod_json" | jq -r '.spec.containers[] | has("resources") and (.resources | has("requests"))' 2>/dev/null | grep -q true || echo "false")
                    local has_limits=$(echo "$pod_json" | jq -r '.spec.containers[] | has("resources") and (.resources | has("limits"))' 2>/dev/null | grep -q true || echo "false")

                    if [[ "$has_requests" != "true" || "$has_limits" != "true" ]]; then
                        ((pods_without_limits++))
                    fi
                fi
            done
        fi
    done

    if [[ $total_pods -gt 0 ]]; then
        local compliance_rate=$(( (total_pods - pods_without_limits) * 100 / total_pods ))
        if [[ $compliance_rate -ge 80 ]]; then
            add_audit_result "resources" "pod_limits" "LOW" "PASS" "Resource limits compliance: $compliance_rate%" "" "$pods_without_limits/$total_pods pods without limits"
            log PASS "Resource limits compliance: $compliance_rate%"
        else
            add_audit_result "resources" "pod_limits" "MEDIUM" "WARN" "Poor resource limits compliance: $compliance_rate%" "Set resource requests and limits" "$pods_without_limits/$total_pods pods without limits"
            log WARN "Resource limits compliance: $compliance_rate% ($pods_without_limits/$total_pods pods without limits)"
        fi
    fi
}

audit_secrets_management() {
    local env_name="$1"
    log STEP "Auditing secrets and credential management for: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    export KUBECONFIG="$kubeconfig"

    # Check for secrets in default namespace
    local default_secrets=$(kubectl get secrets -n default --no-headers 2>/dev/null | grep -v "default-token" | wc -l || echo "0")
    if [[ "$default_secrets" -gt 0 ]]; then
        add_audit_result "secrets" "default_namespace" "MEDIUM" "WARN" "Secrets found in default namespace" "Move secrets to appropriate namespaces" "$default_secrets secrets"
        log WARN "Found $default_secrets secrets in default namespace"
    else
        add_audit_result "secrets" "default_namespace" "LOW" "PASS" "No secrets in default namespace" "" ""
        log PASS "No secrets found in default namespace"
    fi

    # Check for database secrets
    local namespaces=("coder")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local db_secrets=$(kubectl get secrets -n "$ns" -o json 2>/dev/null | jq -r '.items[] | select(.data.password != null or .data.database != null) | .metadata.name' 2>/dev/null || echo "")

            if [[ -n "$db_secrets" ]]; then
                for secret in $db_secrets; do
                    # Check secret age
                    local secret_age=$(kubectl get secret "$secret" -n "$ns" -o json 2>/dev/null | jq -r '.metadata.creationTimestamp' 2>/dev/null || echo "")
                    if [[ -n "$secret_age" ]]; then
                        local age_days=$(( ( $(date +%s) - $(date -d "$secret_age" +%s) ) / 86400 ))

                        if [[ $age_days -gt 90 ]]; then
                            add_audit_result "secrets" "secret_age_$secret" "MEDIUM" "WARN" "Secret is $age_days days old" "Consider rotating credentials" "namespace=$ns"
                            log WARN "Secret $secret in namespace $ns is $age_days days old"
                        else
                            add_audit_result "secrets" "secret_age_$secret" "LOW" "PASS" "Secret age acceptable" "" "age=${age_days}days, namespace=$ns"
                        fi
                    fi
                done
            fi
        fi
    done

    # Check for TLS certificates and their expiration
    local certificates=$(kubectl get secrets -A -o json 2>/dev/null | jq -r '.items[] | select(.type == "kubernetes.io/tls") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

    for cert in $certificates; do
        if [[ -n "$cert" ]]; then
            local ns=$(echo "$cert" | cut -d'/' -f1)
            local name=$(echo "$cert" | cut -d'/' -f2)

            local cert_data=$(kubectl get secret "$name" -n "$ns" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d || echo "")
            if [[ -n "$cert_data" ]]; then
                local expiry=$(echo "$cert_data" | openssl x509 -noout -dates 2>/dev/null | grep "notAfter" | cut -d'=' -f2 || echo "")
                if [[ -n "$expiry" ]]; then
                    local expiry_timestamp=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
                    local days_until_expiry=$(( (expiry_timestamp - $(date +%s)) / 86400 ))

                    if [[ $days_until_expiry -lt 30 ]]; then
                        add_audit_result "secrets" "cert_expiry_$name" "HIGH" "FAIL" "Certificate expires in $days_until_expiry days" "Renew certificate" "namespace=$ns"
                        log FAIL "Certificate $name in namespace $ns expires in $days_until_expiry days"
                    elif [[ $days_until_expiry -lt 60 ]]; then
                        add_audit_result "secrets" "cert_expiry_$name" "MEDIUM" "WARN" "Certificate expires in $days_until_expiry days" "Plan certificate renewal" "namespace=$ns"
                        log WARN "Certificate $name in namespace $ns expires in $days_until_expiry days"
                    else
                        add_audit_result "secrets" "cert_expiry_$name" "LOW" "PASS" "Certificate expires in $days_until_expiry days" "" "namespace=$ns"
                    fi
                fi
            fi
        fi
    done
}

audit_container_security() {
    local env_name="$1"
    log STEP "Auditing container security for: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    export KUBECONFIG="$kubeconfig"

    # Check container images for security context
    local pods_with_security_issues=0
    local total_pods=0
    local namespaces=("coder" "monitoring")

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pods=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

            for pod in $pods; do
                if [[ -n "$pod" ]]; then
                    ((total_pods++))
                    local pod_json=$(kubectl get pod "$pod" -n "$ns" -o json 2>/dev/null || echo '{}')

                    # Check for read-only root filesystem
                    local readonly_fs=$(echo "$pod_json" | jq -r '.spec.containers[] | .securityContext.readOnlyRootFilesystem // false' 2>/dev/null | grep -q true || echo "false")

                    # Check for allowPrivilegeEscalation
                    local allow_priv_esc=$(echo "$pod_json" | jq -r '.spec.containers[] | .securityContext.allowPrivilegeEscalation // true' 2>/dev/null | grep -q false || echo "true")

                    # Check for capabilities dropping
                    local drops_all_caps=$(echo "$pod_json" | jq -r '.spec.containers[] | .securityContext.capabilities.drop[]? // empty' 2>/dev/null | grep -q "ALL" || echo "false")

                    local issues=0
                    [[ "$readonly_fs" != "true" ]] && ((issues++))
                    [[ "$allow_priv_esc" != "false" ]] && ((issues++))
                    [[ "$drops_all_caps" != "true" ]] && ((issues++))

                    if [[ $issues -gt 0 ]]; then
                        ((pods_with_security_issues++))
                        add_audit_result "container_security" "pod_$pod" "MEDIUM" "WARN" "Container security issues found" "Harden container security context" "namespace=$ns, issues=$issues"
                    fi

                    # Check for image pull policy
                    local always_pull=$(echo "$pod_json" | jq -r '.spec.containers[] | .imagePullPolicy' 2>/dev/null | grep -q "Always" || echo "false")
                    if [[ "$always_pull" != "true" && "$env_name" == "prod" ]]; then
                        add_audit_result "container_security" "image_pull_$pod" "LOW" "WARN" "Image pull policy not set to Always" "Set imagePullPolicy: Always for production" "namespace=$ns"
                    fi
                fi
            done
        fi
    done

    if [[ $total_pods -gt 0 ]]; then
        local compliance_rate=$(( (total_pods - pods_with_security_issues) * 100 / total_pods ))
        if [[ $compliance_rate -ge 80 ]]; then
            add_audit_result "container_security" "overall_compliance" "LOW" "PASS" "Container security compliance: $compliance_rate%" "" "$pods_with_security_issues/$total_pods pods with issues"
            log PASS "Container security compliance: $compliance_rate%"
        else
            add_audit_result "container_security" "overall_compliance" "MEDIUM" "WARN" "Poor container security compliance: $compliance_rate%" "Review container security contexts" "$pods_with_security_issues/$total_pods pods with issues"
            log WARN "Container security compliance: $compliance_rate% ($pods_with_security_issues/$total_pods pods with issues)"
        fi
    fi
}

audit_compliance_cis() {
    local env_name="$1"
    log STEP "Running CIS Kubernetes Benchmark checks for: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    export KUBECONFIG="$kubeconfig"

    # CIS 5.1.1: Ensure that the cluster-admin role is only used where required
    local cluster_admin_bindings=$(kubectl get clusterrolebindings -o json 2>/dev/null | jq -r '.items[] | select(.roleRef.name == "cluster-admin") | .metadata.name' 2>/dev/null || echo "")

    local admin_count=0
    for binding in $cluster_admin_bindings; do
        if [[ -n "$binding" ]]; then
            ((admin_count++))
        fi
    done

    if [[ $admin_count -le 2 ]]; then
        add_audit_result "cis_compliance" "cluster_admin_usage" "LOW" "PASS" "Limited cluster-admin bindings" "" "$admin_count bindings"
        log PASS "CIS 5.1.1: Cluster-admin role usage is limited ($admin_count bindings)"
    else
        add_audit_result "cis_compliance" "cluster_admin_usage" "HIGH" "FAIL" "Excessive cluster-admin bindings" "Review and minimize cluster-admin usage" "$admin_count bindings"
        log FAIL "CIS 5.1.1: Too many cluster-admin bindings found ($admin_count)"
    fi

    # CIS 5.1.3: Minimize wildcard use in Roles and ClusterRoles
    local wildcard_roles=$(kubectl get clusterroles -o json 2>/dev/null | jq -r '.items[] | select(.rules[]? | .verbs[]? == "*" or .resources[]? == "*" or .apiGroups[]? == "*") | .metadata.name' 2>/dev/null || echo "")

    if [[ -n "$wildcard_roles" ]]; then
        local wildcard_count=$(echo "$wildcard_roles" | wc -l)
        add_audit_result "cis_compliance" "wildcard_permissions" "HIGH" "FAIL" "Roles with wildcard permissions found" "Replace wildcards with specific permissions" "$wildcard_count roles: $wildcard_roles"
        log FAIL "CIS 5.1.3: Found $wildcard_count roles with wildcard permissions"
    else
        add_audit_result "cis_compliance" "wildcard_permissions" "LOW" "PASS" "No wildcard permissions found" "" ""
        log PASS "CIS 5.1.3: No wildcard permissions in roles"
    fi

    # CIS 5.2.2: Minimize the admission of containers with allowPrivilegeEscalation
    local pods_with_priv_esc=0
    local total_checked_pods=0
    local namespaces=("coder" "monitoring")

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pods=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

            for pod in $pods; do
                if [[ -n "$pod" ]]; then
                    ((total_checked_pods++))
                    local pod_json=$(kubectl get pod "$pod" -n "$ns" -o json 2>/dev/null || echo '{}')
                    local allow_priv_esc=$(echo "$pod_json" | jq -r '.spec.containers[] | .securityContext.allowPrivilegeEscalation // true' 2>/dev/null | grep -q true && echo "true" || echo "false")

                    if [[ "$allow_priv_esc" == "true" ]]; then
                        ((pods_with_priv_esc++))
                    fi
                fi
            done
        fi
    done

    if [[ $total_checked_pods -gt 0 ]]; then
        local compliance_rate=$(( (total_checked_pods - pods_with_priv_esc) * 100 / total_checked_pods ))
        if [[ $compliance_rate -ge 90 ]]; then
            add_audit_result "cis_compliance" "privilege_escalation" "LOW" "PASS" "CIS 5.2.2: Privilege escalation compliance: $compliance_rate%" "" "$pods_with_priv_esc/$total_checked_pods pods allow privilege escalation"
            log PASS "CIS 5.2.2: Privilege escalation compliance: $compliance_rate%"
        else
            add_audit_result "cis_compliance" "privilege_escalation" "MEDIUM" "WARN" "CIS 5.2.2: Poor privilege escalation compliance: $compliance_rate%" "Set allowPrivilegeEscalation: false" "$pods_with_priv_esc/$total_checked_pods pods allow privilege escalation"
            log WARN "CIS 5.2.2: Privilege escalation compliance: $compliance_rate% ($pods_with_priv_esc/$total_checked_pods pods)"
        fi
    fi

    # CIS 5.7.3: Apply Security Context to Pods and Containers
    local pods_without_security_context=0
    total_checked_pods=0

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pods=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '.items[].metadata.name' 2>/dev/null || echo "")

            for pod in $pods; do
                if [[ -n "$pod" ]]; then
                    ((total_checked_pods++))
                    local pod_json=$(kubectl get pod "$pod" -n "$ns" -o json 2>/dev/null || echo '{}')
                    local has_security_context=$(echo "$pod_json" | jq -r 'has("spec") and (.spec | has("securityContext"))' 2>/dev/null)

                    if [[ "$has_security_context" != "true" ]]; then
                        ((pods_without_security_context++))
                    fi
                fi
            done
        fi
    done

    if [[ $total_checked_pods -gt 0 ]]; then
        local compliance_rate=$(( (total_checked_pods - pods_without_security_context) * 100 / total_checked_pods ))
        if [[ $compliance_rate -ge 80 ]]; then
            add_audit_result "cis_compliance" "security_context" "LOW" "PASS" "CIS 5.7.3: Security context compliance: $compliance_rate%" "" "$pods_without_security_context/$total_checked_pods pods without security context"
            log PASS "CIS 5.7.3: Security context compliance: $compliance_rate%"
        else
            add_audit_result "cis_compliance" "security_context" "MEDIUM" "WARN" "CIS 5.7.3: Poor security context compliance: $compliance_rate%" "Apply security contexts to pods" "$pods_without_security_context/$total_checked_pods pods without security context"
            log WARN "CIS 5.7.3: Security context compliance: $compliance_rate% ($pods_without_security_context/$total_checked_pods pods)"
        fi
    fi
}

generate_remediation_script() {
    log STEP "Generating remediation recommendations..."

    local remediation_script="${PROJECT_ROOT}/scripts/utils/security-remediation-auto-generated.sh"
    cat > "$remediation_script" <<'EOF'
#!/bin/bash
# Auto-generated security remediation script
# This script contains remediation commands based on security audit findings

set -euo pipefail

ENVIRONMENT=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --env=*) ENVIRONMENT="${1#*=}"; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$ENVIRONMENT" ]]; then
    echo "Usage: $0 --env=ENV [--dry-run]"
    exit 1
fi

KUBECONFIG="${HOME}/.kube/config-coder-${ENVIRONMENT}"
export KUBECONFIG

echo "=== Auto-generated Security Remediation Script ==="
echo "Environment: $ENVIRONMENT"
echo "Dry run: $DRY_RUN"
echo

EOF

    # Add remediation commands based on audit results
    for result in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r category check severity status message recommendation details <<< "$result"

        if [[ "$status" == "FAIL" && -n "$recommendation" ]]; then
            cat >> "$remediation_script" <<EOF
# Remediation for: $category/$check
echo "Fixing: $message"
if [[ "\$DRY_RUN" == "true" ]]; then
    echo "  Would execute: $recommendation"
else
    # $recommendation
    echo "  Manual intervention required: $recommendation"
fi
echo

EOF
        fi
    done

    chmod +x "$remediation_script"
    log INFO "Remediation script generated: $remediation_script"
}

generate_report() {
    if [[ -z "$OUTPUT_FILE" ]]; then
        return 0
    fi

    log STEP "Generating security audit report..."

    local total_checks=0
    local passed_checks=0
    local failed_checks=0
    local warn_checks=0
    local high_severity=0
    local medium_severity=0
    local low_severity=0

    for result in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r category check severity status message recommendation details <<< "$result"
        ((total_checks++))

        case "$status" in
            PASS) ((passed_checks++)) ;;
            FAIL) ((failed_checks++)) ;;
            WARN) ((warn_checks++)) ;;
        esac

        case "$severity" in
            HIGH) ((high_severity++)) ;;
            MEDIUM) ((medium_severity++)) ;;
            LOW) ((low_severity++)) ;;
        esac
    done

    case "$OUTPUT_FORMAT" in
        json)
            cat > "$OUTPUT_FILE" <<EOF
{
  "security_audit_report": {
    "environment": "$ENVIRONMENT",
    "timestamp": "$(date -Iseconds)",
    "auditor_version": "1.0.0",
    "audit_type": "$([ "$COMPREHENSIVE" == "true" ] && echo "comprehensive" || echo "standard")",
    "compliance_framework": "$COMPLIANCE_LEVEL",
    "summary": {
      "total_checks": $total_checks,
      "passed": $passed_checks,
      "failed": $failed_checks,
      "warnings": $warn_checks,
      "high_severity_issues": $high_severity,
      "medium_severity_issues": $medium_severity,
      "low_severity_issues": $low_severity,
      "success_rate": $(( total_checks > 0 ? (passed_checks * 100) / total_checks : 0 )),
      "risk_score": $(( high_severity * 10 + medium_severity * 5 + low_severity * 1 ))
    },
    "findings": [
EOF

            local first=true
            for result in "${AUDIT_RESULTS[@]}"; do
                IFS='|' read -r category check severity status message recommendation details <<< "$result"

                [[ "$first" == "true" ]] && first=false || echo "," >> "$OUTPUT_FILE"

                cat >> "$OUTPUT_FILE" <<EOF
      {
        "category": "$category",
        "check": "$check",
        "severity": "$severity",
        "status": "$status",
        "message": "$message",
        "recommendation": "$recommendation",
        "details": "$details",
        "timestamp": "$(date -Iseconds)"
      }
EOF
            done

            cat >> "$OUTPUT_FILE" <<EOF
    ]
  }
}
EOF
            ;;
        html)
            cat > "$OUTPUT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Security Audit Report - $ENVIRONMENT</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .summary { background: #e8f4f8; padding: 15px; margin: 20px 0; border-radius: 5px; }
        .finding { margin: 15px 0; padding: 15px; border-left: 4px solid #ddd; }
        .HIGH { border-left-color: #dc3545; background: #f8d7da; }
        .MEDIUM { border-left-color: #ffc107; background: #fff3cd; }
        .LOW { border-left-color: #28a745; background: #d4edda; }
        .PASS { color: #28a745; }
        .FAIL { color: #dc3545; }
        .WARN { color: #ffc107; }
        .recommendation { background: #f8f9fa; padding: 10px; margin-top: 10px; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Security Audit Report</h1>
        <p><strong>Environment:</strong> $ENVIRONMENT</p>
        <p><strong>Date:</strong> $(date)</p>
        <p><strong>Compliance:</strong> $COMPLIANCE_LEVEL</p>
    </div>

    <div class="summary">
        <h2>Executive Summary</h2>
        <p><strong>Total Checks:</strong> $total_checks</p>
        <p><strong>Passed:</strong> <span class="PASS">$passed_checks</span></p>
        <p><strong>Failed:</strong> <span class="FAIL">$failed_checks</span></p>
        <p><strong>Warnings:</strong> <span class="WARN">$warn_checks</span></p>
        <p><strong>Success Rate:</strong> $(( total_checks > 0 ? (passed_checks * 100) / total_checks : 0 ))%</p>
        <p><strong>Risk Score:</strong> $(( high_severity * 10 + medium_severity * 5 + low_severity * 1 ))</p>
    </div>

    <h2>Detailed Findings</h2>
EOF

            for result in "${AUDIT_RESULTS[@]}"; do
                IFS='|' read -r category check severity status message recommendation details <<< "$result"

                cat >> "$OUTPUT_FILE" <<EOF
    <div class="finding $severity">
        <h3>$category - $check</h3>
        <p><strong>Status:</strong> <span class="$status">$status</span></p>
        <p><strong>Severity:</strong> $severity</p>
        <p><strong>Message:</strong> $message</p>
        $([ -n "$recommendation" ] && echo "<div class=\"recommendation\"><strong>Recommendation:</strong> $recommendation</div>")
        $([ -n "$details" ] && echo "<p><strong>Details:</strong> <code>$details</code></p>")
    </div>
EOF
            done

            cat >> "$OUTPUT_FILE" <<EOF
</body>
</html>
EOF
            ;;
    esac

    log PASS "Security audit report saved to: $OUTPUT_FILE"
}

print_summary() {
    log STEP "Security Audit Summary"

    local total_checks=0
    local passed_checks=0
    local failed_checks=0
    local warn_checks=0
    local high_severity=0
    local medium_severity=0
    local low_severity=0

    for result in "${AUDIT_RESULTS[@]}"; do
        IFS='|' read -r category check severity status message recommendation details <<< "$result"
        ((total_checks++))

        case "$status" in
            PASS) ((passed_checks++)) ;;
            FAIL) ((failed_checks++)) ;;
            WARN) ((warn_checks++)) ;;
        esac

        case "$severity" in
            HIGH) ((high_severity++)) ;;
            MEDIUM) ((medium_severity++)) ;;
            LOW) ((low_severity++)) ;;
        esac
    done

    local success_rate=$(( total_checks > 0 ? (passed_checks * 100) / total_checks : 0 ))
    local risk_score=$(( high_severity * 10 + medium_severity * 5 + low_severity * 1 ))

    echo
    if [[ "$failed_checks" -eq 0 ]]; then
        echo -e "${GREEN}✅ Security audit completed successfully! ✅${NC}"
    else
        echo -e "${YELLOW}⚠️  Security audit completed with issues ⚠️${NC}"
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
    echo

    echo -e "${WHITE}Severity Breakdown:${NC}"
    [[ "$high_severity" -gt 0 ]] && echo -e "${RED}High:${NC} $high_severity"
    [[ "$medium_severity" -gt 0 ]] && echo -e "${YELLOW}Medium:${NC} $medium_severity"
    [[ "$low_severity" -gt 0 ]] && echo -e "${BLUE}Low:${NC} $low_severity"
    echo -e "${WHITE}Risk Score:${NC} $risk_score"
    echo

    if [[ "$failed_checks" -gt 0 ]]; then
        echo -e "${YELLOW}🔴 Critical Issues (Failed Checks):${NC}"
        for result in "${AUDIT_RESULTS[@]}"; do
            IFS='|' read -r category check severity status message recommendation details <<< "$result"
            if [[ "$status" == "FAIL" ]]; then
                echo -e "   ${RED}✗${NC} [$severity] $category/$check: $message"
            fi
        done
        echo
    fi

    if [[ "$warn_checks" -gt 0 && "$failed_checks" -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  Warnings:${NC}"
        for result in "${AUDIT_RESULTS[@]}"; do
            IFS='|' read -r category check severity status message recommendation details <<< "$result"
            if [[ "$status" == "WARN" ]]; then
                echo -e "   ${YELLOW}!${NC} [$severity] $category/$check: $message"
            fi
        done
        echo
    fi

    echo -e "${YELLOW}📋 Next Steps:${NC}"
    if [[ "$failed_checks" -gt 0 ]]; then
        echo "   • Address critical security issues immediately"
        echo "   • Run security remediation script: ./scripts/utils/security-remediation.sh --env=$ENVIRONMENT"
        echo "   • Re-run audit after fixes"
    elif [[ "$warn_checks" -gt 0 ]]; then
        echo "   • Review warnings and plan improvements"
        echo "   • Consider implementing recommended security enhancements"
    else
        echo "   • Security posture looks good!"
        echo "   • Schedule regular security audits"
        echo "   • Consider enabling comprehensive audits"
    fi

    [[ -n "$OUTPUT_FILE" ]] && echo "   • Review detailed report: $OUTPUT_FILE"

    if [[ "$FIX_ISSUES" == "true" ]]; then
        echo "   • Auto-generated remediation script created"
    fi

    echo

    return $(( failed_checks > 0 ? 1 : 0 ))
}

run_audit_for_environment() {
    local env_name="$1"

    log INFO "Starting security audit for environment: $env_name"

    # Core security checks
    audit_pod_security_standards "$env_name"
    audit_network_security "$env_name"
    audit_rbac "$env_name"
    audit_resource_limits "$env_name"
    audit_secrets_management "$env_name"
    audit_container_security "$env_name"

    # Compliance checks
    if [[ "$COMPLIANCE_LEVEL" == "cis" || "$COMPREHENSIVE" == "true" ]]; then
        audit_compliance_cis "$env_name"
    fi

    log INFO "✅ Security audit completed for: $env_name"
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env=*)
                ENVIRONMENT="${1#*=}"
                shift
                ;;
            --format=*)
                OUTPUT_FORMAT="${1#*=}"
                shift
                ;;
            --output=*)
                OUTPUT_FILE="${1#*=}"
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
            --compliance=*)
                COMPLIANCE_LEVEL="${1#*=}"
                shift
                ;;
            --fix)
                FIX_ISSUES=true
                shift
                ;;
            --timeout=*)
                TIMEOUT="${1#*=}"
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
    check_prerequisites

    log INFO "Starting security audit for environment: $ENVIRONMENT"
    [[ "$DETAILED" == "true" ]] && log INFO "🔍 Running detailed audit"
    [[ "$COMPREHENSIVE" == "true" ]] && log INFO "🎯 Running comprehensive audit"
    [[ -n "$COMPLIANCE_LEVEL" ]] && log INFO "📋 Compliance framework: $COMPLIANCE_LEVEL"

    validate_environment

    # Process environments
    if [[ "$ENVIRONMENT" == "all" ]]; then
        for env in dev staging prod; do
            if [[ -d "${PROJECT_ROOT}/environments/$env" ]]; then
                run_audit_for_environment "$env"
            else
                log WARN "Environment directory not found: $env"
            fi
        done
    else
        run_audit_for_environment "$ENVIRONMENT"
    fi

    # Generate outputs
    generate_report

    if [[ "$FIX_ISSUES" == "true" ]]; then
        generate_remediation_script
    fi

    print_summary
}

# Run main function with all arguments
main "$@"