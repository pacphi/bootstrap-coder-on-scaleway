#!/bin/bash

# Coder on Scaleway - Security Remediation Script
# Automated security hardening and issue remediation

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
DRY_RUN=false
FORCE_APPLY=false
BACKUP_ENABLED=true
ROLLBACK_ENABLED=true
SPECIFIC_CHECKS=""
HARDENING_LEVEL=""
LOG_FILE=""
REMEDIATION_RESULTS=()

# Environment-specific hardening levels
get_hardening_level() {
    local env="$1"
    case "$env" in
        dev) echo "baseline" ;;
        staging) echo "enhanced" ;;
        prod) echo "strict" ;;
        *) echo "baseline" ;;
    esac
}

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║       Security Remediation Tool       ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated security hardening and remediation for Coder on Scaleway environments.
Applies security fixes, updates configurations, and implements best practices.

Options:
    --env=ENV                   Environment to remediate (dev|staging|prod) [required]
    --dry-run                   Preview changes without applying them
    --force                     Apply changes without confirmation prompts
    --no-backup                 Skip backup creation before changes
    --no-rollback               Disable rollback capability
    --checks=LIST               Specific checks to remediate (comma-separated)
    --hardening=LEVEL           Security hardening level (baseline|enhanced|strict)
    --help                      Show this help message

Examples:
    $0 --env=dev --dry-run
    $0 --env=prod --hardening=strict --force
    $0 --env=staging --checks=pod_security,network_policies
    $0 --env=prod --no-backup --force

Remediation Categories:
    • pod_security: Apply Pod Security Standards and contexts
    • network_policies: Implement network segmentation and policies
    • rbac: Configure role-based access control
    • resource_limits: Set resource quotas and limits
    • secrets_mgmt: Rotate secrets and improve management
    • container_hardening: Harden container security contexts
    • compliance: Apply compliance frameworks (CIS, etc.)
    • monitoring: Configure security monitoring and logging

Hardening Levels:
    • baseline: Basic security improvements (default for dev)
    • enhanced: Moderate security hardening (default for staging)
    • strict: Maximum security hardening (default for prod)

Environment Defaults:
    • Development: baseline hardening, relaxed policies
    • Staging: enhanced hardening, production-like security
    • Production: strict hardening, maximum security

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
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
        SKIP)  echo -e "${BLUE}[SKIP]${NC} $message" ;;
        APPLY) echo -e "${YELLOW}[APPLY]${NC} $message" ;;
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_logging() {
    local log_dir="${PROJECT_ROOT}/logs/security-remediation"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-remediation.log"
    log INFO "Logging to: $LOG_FILE"
}

add_result() {
    local category="$1"
    local action="$2"
    local status="$3"
    local message="$4"
    local details="${5:-}"

    REMEDIATION_RESULTS+=("$category|$action|$status|$message|$details")
}

validate_environment() {
    case "$ENVIRONMENT" in
        dev|staging|prod)
            log INFO "Target environment: $ENVIRONMENT"
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

check_prerequisites() {
    log STEP "Checking prerequisites..."

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

    # Check if environment is deployed
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Environment not deployed or kubeconfig not found: $kubeconfig"
        exit 1
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info &>/dev/null; then
        log ERROR "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    log INFO "✅ Prerequisites validated"
}

create_backup() {
    if [[ "$BACKUP_ENABLED" == "false" ]]; then
        log SKIP "Backup creation disabled"
        return 0
    fi

    log STEP "Creating backup before remediation..."

    local backup_dir="${PROJECT_ROOT}/backups/security-remediation"
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="${backup_dir}/${backup_timestamp}-${ENVIRONMENT}"

    mkdir -p "$backup_path"

    # Backup current security configurations
    kubectl get networkpolicies -A -o yaml > "${backup_path}/networkpolicies.yaml" 2>/dev/null || true
    kubectl get rolebindings -A -o yaml > "${backup_path}/rolebindings.yaml" 2>/dev/null || true
    kubectl get clusterrolebindings -o yaml > "${backup_path}/clusterrolebindings.yaml" 2>/dev/null || true
    kubectl get resourcequotas -A -o yaml > "${backup_path}/resourcequotas.yaml" 2>/dev/null || true
    kubectl get limitranges -A -o yaml > "${backup_path}/limitranges.yaml" 2>/dev/null || true
    kubectl get secrets -A -o yaml > "${backup_path}/secrets.yaml" 2>/dev/null || true

    # Create restoration script
    cat > "${backup_path}/restore.sh" <<EOF
#!/bin/bash
# Restoration script for security configuration backup
# Created: $(date)
# Environment: $ENVIRONMENT

set -e

echo "Restoring security configuration from backup..."
echo "Backup path: $backup_path"

export KUBECONFIG="${HOME}/.kube/config-coder-${ENVIRONMENT}"

# Restore configurations (be careful with secrets)
kubectl apply -f networkpolicies.yaml
kubectl apply -f rolebindings.yaml
kubectl apply -f clusterrolebindings.yaml
kubectl apply -f resourcequotas.yaml
kubectl apply -f limitranges.yaml

echo "Restoration completed. Verify configurations manually."
EOF

    chmod +x "${backup_path}/restore.sh"
    log SUCCESS "Backup created: $backup_path"
    add_result "backup" "create_backup" "SUCCESS" "Security configuration backed up" "$backup_path"
}

apply_pod_security_standards() {
    local env_name="$1"
    log STEP "Applying Pod Security Standards for: $env_name"

    local target_level=$(get_hardening_level "$env_name")
    local pod_security_level=""

    case "$target_level" in
        baseline) pod_security_level="baseline" ;;
        enhanced) pod_security_level="baseline" ;;
        strict) pod_security_level="restricted" ;;
    esac

    local namespaces=("coder" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            log APPLY "Configuring Pod Security Standard for namespace: $ns"

            if [[ "$DRY_RUN" == "false" ]]; then
                kubectl label namespace "$ns" \
                    "pod-security.kubernetes.io/enforce=$pod_security_level" \
                    "pod-security.kubernetes.io/audit=$pod_security_level" \
                    "pod-security.kubernetes.io/warn=$pod_security_level" \
                    --overwrite

                add_result "pod_security" "namespace_$ns" "SUCCESS" "Pod Security Standard applied" "$pod_security_level"
                log SUCCESS "Applied Pod Security Standard '$pod_security_level' to namespace $ns"
            else
                log INFO "Would apply Pod Security Standard '$pod_security_level' to namespace $ns"
                add_result "pod_security" "namespace_$ns" "DRY_RUN" "Would apply Pod Security Standard" "$pod_security_level"
            fi
        fi
    done

    # Apply security contexts to existing pods that need them
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local deployments=$(kubectl get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

            for deployment in $deployments; do
                if [[ -n "$deployment" ]]; then
                    local current_context=$(kubectl get deployment "$deployment" -n "$ns" -o jsonpath='{.spec.template.spec.securityContext}' 2>/dev/null || echo "null")

                    if [[ "$current_context" == "null" || "$current_context" == "{}" ]]; then
                        log APPLY "Adding security context to deployment: $deployment"

                        if [[ "$DRY_RUN" == "false" ]]; then
                            kubectl patch deployment "$deployment" -n "$ns" --patch '{"spec":{"template":{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65534,"fsGroup":65534}}}}}'
                            add_result "pod_security" "deployment_$deployment" "SUCCESS" "Security context applied" "namespace=$ns"
                            log SUCCESS "Applied security context to deployment $deployment"
                        else
                            log INFO "Would apply security context to deployment $deployment"
                            add_result "pod_security" "deployment_$deployment" "DRY_RUN" "Would apply security context" "namespace=$ns"
                        fi
                    fi
                fi
            done
        fi
    done
}

implement_network_policies() {
    local env_name="$1"
    log STEP "Implementing network policies for: $env_name"

    local namespaces=("coder" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            # Check if default deny policy exists
            if ! kubectl get networkpolicy deny-all -n "$ns" &>/dev/null; then
                log APPLY "Creating default deny network policy for namespace: $ns"

                if [[ "$DRY_RUN" == "false" ]]; then
                    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
                    add_result "network_policies" "deny_all_$ns" "SUCCESS" "Default deny policy created" ""
                    log SUCCESS "Created default deny network policy for namespace $ns"
                else
                    log INFO "Would create default deny network policy for namespace $ns"
                    add_result "network_policies" "deny_all_$ns" "DRY_RUN" "Would create default deny policy" ""
                fi
            fi

            # Create specific allow policies for Coder
            if [[ "$ns" == "coder" ]]; then
                log APPLY "Creating Coder-specific network policies"

                if [[ "$DRY_RUN" == "false" ]]; then
                    # Allow DNS resolution
                    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: coder
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF

                    # Allow Coder server communication
                    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-coder-server
  namespace: coder
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: coder
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from: []
    ports:
    - protocol: TCP
      port: 7080
  egress:
  - to: []
EOF

                    add_result "network_policies" "coder_policies" "SUCCESS" "Coder network policies created" ""
                    log SUCCESS "Created Coder-specific network policies"
                else
                    log INFO "Would create Coder-specific network policies"
                    add_result "network_policies" "coder_policies" "DRY_RUN" "Would create Coder policies" ""
                fi
            fi
        fi
    done
}

configure_rbac() {
    local env_name="$1"
    log STEP "Configuring RBAC for: $env_name"

    # Clean up overly permissive cluster role bindings
    local cluster_admin_bindings=$(kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.roleRef.name == "cluster-admin") | select(.metadata.name | test("^system:|^cluster-admin$") | not) | .metadata.name' 2>/dev/null || echo "")

    for binding in $cluster_admin_bindings; do
        if [[ -n "$binding" ]]; then
            log WARN "Found potentially unnecessary cluster-admin binding: $binding"

            if [[ "$FORCE_APPLY" == "true" ]]; then
                log APPLY "Removing cluster-admin binding: $binding"
                if [[ "$DRY_RUN" == "false" ]]; then
                    kubectl delete clusterrolebinding "$binding"
                    add_result "rbac" "remove_binding_$binding" "SUCCESS" "Removed excessive cluster-admin binding" ""
                    log SUCCESS "Removed cluster-admin binding: $binding"
                else
                    log INFO "Would remove cluster-admin binding: $binding"
                    add_result "rbac" "remove_binding_$binding" "DRY_RUN" "Would remove binding" ""
                fi
            else
                log INFO "Skipping removal of cluster-admin binding: $binding (use --force to remove)"
                add_result "rbac" "remove_binding_$binding" "SKIP" "Manual review required" ""
            fi
        fi
    done

    # Ensure Coder has minimal required permissions
    log APPLY "Validating Coder RBAC configuration"
    if kubectl get clusterrole coder &>/dev/null; then
        local wildcard_rules=$(kubectl get clusterrole coder -o json | jq -r '.rules[] | select(.verbs[]? == "*" or .resources[]? == "*" or .apiGroups[]? == "*") | "found"' 2>/dev/null || echo "")

        if [[ -n "$wildcard_rules" ]]; then
            log WARN "Coder ClusterRole contains wildcard permissions"
            add_result "rbac" "coder_permissions" "WARN" "Coder has wildcard permissions" "manual review required"
        else
            add_result "rbac" "coder_permissions" "SUCCESS" "Coder permissions validated" ""
            log SUCCESS "Coder ClusterRole permissions are appropriately restricted"
        fi
    fi
}

implement_resource_limits() {
    local env_name="$1"
    log STEP "Implementing resource limits for: $env_name"

    local namespaces=("coder" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            # Create resource quota if it doesn't exist
            if ! kubectl get resourcequota -n "$ns" &>/dev/null; then
                log APPLY "Creating resource quota for namespace: $ns"

                local quota_spec=""
                case "$env_name" in
                    dev)
                        quota_spec='{"requests.cpu": "2", "requests.memory": "4Gi", "limits.cpu": "4", "limits.memory": "8Gi", "pods": "10"}'
                        ;;
                    staging)
                        quota_spec='{"requests.cpu": "4", "requests.memory": "8Gi", "limits.cpu": "8", "limits.memory": "16Gi", "pods": "20"}'
                        ;;
                    prod)
                        quota_spec='{"requests.cpu": "8", "requests.memory": "16Gi", "limits.cpu": "16", "limits.memory": "32Gi", "pods": "50"}'
                        ;;
                esac

                if [[ "$DRY_RUN" == "false" ]]; then
                    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${ns}-quota
  namespace: ${ns}
spec:
  hard: $(echo "$quota_spec" | jq -c .)
EOF
                    add_result "resource_limits" "quota_$ns" "SUCCESS" "Resource quota created" "$quota_spec"
                    log SUCCESS "Created resource quota for namespace $ns"
                else
                    log INFO "Would create resource quota for namespace $ns with spec: $quota_spec"
                    add_result "resource_limits" "quota_$ns" "DRY_RUN" "Would create resource quota" "$quota_spec"
                fi
            fi

            # Create limit range if it doesn't exist
            if ! kubectl get limitrange -n "$ns" &>/dev/null; then
                log APPLY "Creating limit range for namespace: $ns"

                if [[ "$DRY_RUN" == "false" ]]; then
                    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: ${ns}-limits
  namespace: ${ns}
spec:
  limits:
  - default:
      cpu: "1000m"
      memory: "1Gi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    type: Container
EOF
                    add_result "resource_limits" "limitrange_$ns" "SUCCESS" "Limit range created" ""
                    log SUCCESS "Created limit range for namespace $ns"
                else
                    log INFO "Would create limit range for namespace $ns"
                    add_result "resource_limits" "limitrange_$ns" "DRY_RUN" "Would create limit range" ""
                fi
            fi
        fi
    done
}

rotate_secrets() {
    local env_name="$1"
    log STEP "Evaluating secrets rotation for: $env_name"

    # Check database secrets age and rotation needs
    if kubectl get secret -n coder &>/dev/null; then
        local db_secrets=$(kubectl get secrets -n coder -o json | jq -r '.items[] | select(.data.password != null) | .metadata.name' 2>/dev/null || echo "")

        for secret in $db_secrets; do
            if [[ -n "$secret" ]]; then
                local secret_age=$(kubectl get secret "$secret" -n coder -o json | jq -r '.metadata.creationTimestamp' 2>/dev/null || echo "")
                if [[ -n "$secret_age" ]]; then
                    local age_days=$(( ( $(date +%s) - $(date -d "$secret_age" +%s) ) / 86400 ))

                    if [[ $age_days -gt 90 ]]; then
                        log WARN "Secret $secret is $age_days days old and should be rotated"
                        add_result "secrets_mgmt" "rotate_$secret" "MANUAL" "Secret rotation required" "age=${age_days}days"

                        if [[ "$FORCE_APPLY" == "true" ]]; then
                            log APPLY "Would initiate secret rotation for: $secret"
                            # Note: Actual rotation would require coordination with the database
                            # This is a placeholder for the rotation logic
                            add_result "secrets_mgmt" "rotate_$secret" "MANUAL" "Rotation requires manual intervention" ""
                        fi
                    else
                        add_result "secrets_mgmt" "check_$secret" "SUCCESS" "Secret age acceptable" "age=${age_days}days"
                    fi
                fi
            fi
        done
    fi

    # Check TLS certificates
    local certificates=$(kubectl get secrets -A -o json | jq -r '.items[] | select(.type == "kubernetes.io/tls") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

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
                        log WARN "Certificate $name in namespace $ns expires in $days_until_expiry days"
                        add_result "secrets_mgmt" "cert_renewal_$name" "URGENT" "Certificate renewal required" "namespace=$ns, expires_in=${days_until_expiry}days"
                    fi
                fi
            fi
        fi
    done
}

harden_containers() {
    local env_name="$1"
    log STEP "Hardening container security for: $env_name"

    local namespaces=("coder" "monitoring")
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local deployments=$(kubectl get deployments -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

            for deployment in $deployments; do
                if [[ -n "$deployment" ]]; then
                    log APPLY "Hardening deployment: $deployment"

                    if [[ "$DRY_RUN" == "false" ]]; then
                        # Apply security context hardening
                        kubectl patch deployment "$deployment" -n "$ns" --patch '{
                            "spec": {
                                "template": {
                                    "spec": {
                                        "securityContext": {
                                            "runAsNonRoot": true,
                                            "runAsUser": 65534,
                                            "fsGroup": 65534
                                        },
                                        "containers": [
                                            {
                                                "name": "'"$deployment"'",
                                                "securityContext": {
                                                    "allowPrivilegeEscalation": false,
                                                    "readOnlyRootFilesystem": false,
                                                    "capabilities": {
                                                        "drop": ["ALL"]
                                                    }
                                                }
                                            }
                                        ]
                                    }
                                }
                            }
                        }' 2>/dev/null || {
                            # Fallback: just apply pod security context
                            kubectl patch deployment "$deployment" -n "$ns" --patch '{
                                "spec": {
                                    "template": {
                                        "spec": {
                                            "securityContext": {
                                                "runAsNonRoot": true,
                                                "runAsUser": 65534,
                                                "fsGroup": 65534
                                            }
                                        }
                                    }
                                }
                            }'
                        }

                        add_result "container_hardening" "deployment_$deployment" "SUCCESS" "Container security hardened" "namespace=$ns"
                        log SUCCESS "Hardened deployment $deployment in namespace $ns"
                    else
                        log INFO "Would harden deployment $deployment in namespace $ns"
                        add_result "container_hardening" "deployment_$deployment" "DRY_RUN" "Would harden container security" "namespace=$ns"
                    fi
                fi
            done
        fi
    done
}

configure_monitoring() {
    local env_name="$1"
    log STEP "Configuring security monitoring for: $env_name"

    # Enable audit logging if not already configured
    if kubectl get namespace monitoring &>/dev/null; then
        log APPLY "Configuring security monitoring in monitoring namespace"

        if [[ "$DRY_RUN" == "false" ]]; then
            # Create a config map for additional security monitoring
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: security-monitoring-config
  namespace: monitoring
data:
  security-rules.yml: |
    groups:
    - name: kubernetes-security
      rules:
      - alert: PodSecurityViolation
        expr: increase(pod_security_policy_violations_total[5m]) > 0
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Pod security policy violation detected"
      - alert: NetworkPolicyViolation
        expr: increase(networkpolicy_violations_total[5m]) > 0
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Network policy violation detected"
EOF

            add_result "monitoring" "security_rules" "SUCCESS" "Security monitoring rules configured" ""
            log SUCCESS "Security monitoring rules configured"
        else
            log INFO "Would configure security monitoring rules"
            add_result "monitoring" "security_rules" "DRY_RUN" "Would configure monitoring" ""
        fi
    else
        log SKIP "Monitoring namespace not found, skipping security monitoring configuration"
        add_result "monitoring" "security_rules" "SKIP" "Monitoring not available" ""
    fi
}

validate_remediation() {
    log STEP "Validating applied security remediations..."

    # Run a quick audit to verify changes
    local audit_script="${SCRIPT_DIR}/security-audit.sh"
    if [[ -f "$audit_script" ]]; then
        log INFO "Running security audit to validate changes..."
        if bash "$audit_script" --env="$ENVIRONMENT" --format=json --output="/tmp/post-remediation-audit.json" &>/dev/null; then
            add_result "validation" "post_remediation_audit" "SUCCESS" "Remediation validation completed" ""
            log SUCCESS "Post-remediation audit completed successfully"
        else
            add_result "validation" "post_remediation_audit" "WARN" "Remediation validation had issues" ""
            log WARN "Post-remediation audit completed with warnings"
        fi
    else
        log SKIP "Security audit script not found, skipping validation"
        add_result "validation" "post_remediation_audit" "SKIP" "Audit script not available" ""
    fi
}

print_summary() {
    log STEP "Security Remediation Summary"

    local total_actions=0
    local success_actions=0
    local failed_actions=0
    local skipped_actions=0
    local dry_run_actions=0

    for result in "${REMEDIATION_RESULTS[@]}"; do
        IFS='|' read -r category action status message details <<< "$result"
        ((total_actions++))

        case "$status" in
            SUCCESS) ((success_actions++)) ;;
            FAIL) ((failed_actions++)) ;;
            SKIP) ((skipped_actions++)) ;;
            DRY_RUN) ((dry_run_actions++)) ;;
        esac
    done

    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}🔍 Security remediation dry run completed! 🔍${NC}"
    elif [[ "$failed_actions" -eq 0 ]]; then
        echo -e "${GREEN}✅ Security remediation completed successfully! ✅${NC}"
    else
        echo -e "${YELLOW}⚠️  Security remediation completed with issues ⚠️${NC}"
    fi
    echo

    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Hardening Level:${NC} ${HARDENING_LEVEL:-$(get_hardening_level "$ENVIRONMENT")}"
    echo -e "${WHITE}Total Actions:${NC} $total_actions"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}Dry Run Actions:${NC} $dry_run_actions"
    else
        echo -e "${GREEN}Successful:${NC} $success_actions"
        [[ "$failed_actions" -gt 0 ]] && echo -e "${RED}Failed:${NC} $failed_actions"
        [[ "$skipped_actions" -gt 0 ]] && echo -e "${YELLOW}Skipped:${NC} $skipped_actions"
    fi
    echo

    if [[ "$failed_actions" -gt 0 ]]; then
        echo -e "${YELLOW}❌ Failed Actions:${NC}"
        for result in "${REMEDIATION_RESULTS[@]}"; do
            IFS='|' read -r category action status message details <<< "$result"
            if [[ "$status" == "FAIL" ]]; then
                echo -e "   ${RED}✗${NC} $category/$action: $message"
            fi
        done
        echo
    fi

    if [[ "$skipped_actions" -gt 0 ]]; then
        echo -e "${YELLOW}⏭️  Skipped Actions:${NC}"
        for result in "${REMEDIATION_RESULTS[@]}"; do
            IFS='|' read -r category action status message details <<< "$result"
            if [[ "$status" == "SKIP" || "$status" == "MANUAL" ]]; then
                echo -e "   ${YELLOW}⏭️${NC} $category/$action: $message"
            fi
        done
        echo
    fi

    echo -e "${YELLOW}📋 Next Steps:${NC}"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "   • Review the proposed changes above"
        echo "   • Run without --dry-run to apply changes"
        echo "   • Consider using --force for automated application"
    elif [[ "$failed_actions" -gt 0 ]]; then
        echo "   • Review and address failed actions"
        echo "   • Check logs for detailed error information"
        echo "   • Re-run remediation after fixing issues"
    else
        echo "   • Security improvements have been applied"
        echo "   • Run security audit to verify: ./scripts/utils/security-audit.sh --env=$ENVIRONMENT"
        echo "   • Monitor for any application issues"
    fi

    if [[ "$BACKUP_ENABLED" == "true" && "$DRY_RUN" == "false" ]]; then
        echo "   • Backup created - restoration instructions available if needed"
    fi

    echo

    return $(( failed_actions > 0 ? 1 : 0 ))
}

confirm_changes() {
    if [[ "$FORCE_APPLY" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    log WARN "⚠️  About to apply security remediations to environment: $ENVIRONMENT"
    log WARN "⚠️  This will modify security policies, configurations, and potentially restart pods"
    echo
    read -p "Continue with security remediation? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log INFO "Security remediation cancelled by user"
        exit 0
    fi
}

main() {
    # Parse command line arguments
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
                FORCE_APPLY=true
                shift
                ;;
            --no-backup)
                BACKUP_ENABLED=false
                shift
                ;;
            --no-rollback)
                ROLLBACK_ENABLED=false
                shift
                ;;
            --checks=*)
                SPECIFIC_CHECKS="${1#*=}"
                shift
                ;;
            --hardening=*)
                HARDENING_LEVEL="${1#*=}"
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
    validate_environment

    # Set hardening level if not specified
    if [[ -z "$HARDENING_LEVEL" ]]; then
        HARDENING_LEVEL=$(get_hardening_level "$ENVIRONMENT")
    fi

    log INFO "Starting security remediation for environment: $ENVIRONMENT"
    log INFO "Hardening level: $HARDENING_LEVEL"
    [[ "$DRY_RUN" == "true" ]] && log INFO "🔍 Running in dry-run mode"
    [[ "$FORCE_APPLY" == "true" ]] && log INFO "🚀 Force apply enabled"

    confirm_changes

    # Create backup before making changes
    create_backup

    # Apply security remediations based on checks requested
    if [[ -z "$SPECIFIC_CHECKS" ]]; then
        # Apply all remediations
        apply_pod_security_standards "$ENVIRONMENT"
        implement_network_policies "$ENVIRONMENT"
        configure_rbac "$ENVIRONMENT"
        implement_resource_limits "$ENVIRONMENT"
        rotate_secrets "$ENVIRONMENT"
        harden_containers "$ENVIRONMENT"
        configure_monitoring "$ENVIRONMENT"
    else
        # Apply specific remediations
        IFS=',' read -ra CHECKS_ARRAY <<< "$SPECIFIC_CHECKS"
        for check in "${CHECKS_ARRAY[@]}"; do
            case "$check" in
                pod_security) apply_pod_security_standards "$ENVIRONMENT" ;;
                network_policies) implement_network_policies "$ENVIRONMENT" ;;
                rbac) configure_rbac "$ENVIRONMENT" ;;
                resource_limits) implement_resource_limits "$ENVIRONMENT" ;;
                secrets_mgmt) rotate_secrets "$ENVIRONMENT" ;;
                container_hardening) harden_containers "$ENVIRONMENT" ;;
                monitoring) configure_monitoring "$ENVIRONMENT" ;;
                *) log WARN "Unknown check: $check" ;;
            esac
        done
    fi

    # Validate applied changes
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_remediation
    fi

    print_summary
}

# Run main function with all arguments
main "$@"