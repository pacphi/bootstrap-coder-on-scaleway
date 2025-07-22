#!/bin/bash

# Coder on Scaleway - User Provisioning Script
# Automated user management and provisioning for teams

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
TEAM=""
TEMPLATE=""
DEFAULT_RESOURCES=""
OAUTH_GROUP=""
ACTION="add"
USER_EMAIL=""
USER_LIST=""
BATCH_MODE=false
DRY_RUN=false
LOG_FILE=""
START_TIME=$(date +%s)

# Default resource allocations by team
declare -A TEAM_DEFAULTS=(
    ["frontend"]="cpu=2,memory=4Gi,storage=20Gi"
    ["backend"]="cpu=4,memory=8Gi,storage=30Gi"
    ["fullstack"]="cpu=4,memory=8Gi,storage=30Gi"
    ["devops"]="cpu=2,memory=4Gi,storage=50Gi"
    ["data"]="cpu=4,memory=16Gi,storage=100Gi"
    ["mobile"]="cpu=2,memory=4Gi,storage=20Gi"
)

# Team template mappings
declare -A TEAM_TEMPLATES=(
    ["frontend"]="react-typescript"
    ["backend"]="java-spring"
    ["fullstack"]="python-django-crewai"
    ["devops"]="terraform-ansible"
    ["data"]="jupyter-python"
    ["mobile"]="react-native"
)

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║          User Provisioning            ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated user provisioning and team management for Coder environments.
Handles RBAC setup, resource quotas, template assignments, and OAuth integration.

Options:
    --env=ENV                   Environment (dev|staging|prod) [required]
    --action=ACTION            Action (add|remove|update|list) [default: add]
    --team=TEAM                Team name (frontend|backend|fullstack|devops|data|mobile)
    --template=TEMPLATE        Default workspace template for team
    --default-resources=RES    Default resources (cpu=X,memory=XGi,storage=XGi)
    --oauth-group=GROUP        OAuth group mapping (e.g., team@company.com)
    --user-email=EMAIL         Single user email for individual operations
    --user-list=FILE           File containing list of user emails
    --batch                    Run in batch mode (no prompts)
    --dry-run                  Show what would be done without executing
    --help                     Show this help message

Actions:
    add     Add users/team with RBAC and resource quotas
    remove  Remove users/team and cleanup resources
    update  Update team configuration or user assignments
    list    List current teams and user assignments

Team Examples:
    # Add frontend team with React template
    $0 --env=prod --action=add --team=frontend --template=react-typescript

    # Add backend team with custom resources
    $0 --env=staging --action=add --team=backend --template=java-spring --default-resources="cpu=8,memory=16Gi,storage=50Gi"

    # Add individual user to existing team
    $0 --env=dev --action=add --team=frontend --user-email=john@company.com

    # Bulk add users from file
    $0 --env=prod --action=add --team=backend --user-list=backend-team.txt

OAuth Integration:
    # Map OAuth group to team
    $0 --env=prod --action=add --team=frontend --oauth-group="frontend-team@company.com"

    # This creates RBAC mappings for OAuth group authentication

Resource Management:
    # Custom resource allocation
    --default-resources="cpu=4,memory=8Gi,storage=30Gi"

    # Team quotas are automatically calculated based on expected team size

Team Configurations:
    frontend    React/Angular development      (2 CPU, 4GB RAM, 20GB storage)
    backend     API/microservices development (4 CPU, 8GB RAM, 30GB storage)
    fullstack   Full-stack with AI tools      (4 CPU, 8GB RAM, 30GB storage)
    devops      Infrastructure & automation   (2 CPU, 4GB RAM, 50GB storage)
    data        Data science & ML workflows   (4 CPU, 16GB RAM, 100GB storage)
    mobile      Cross-platform mobile apps    (2 CPU, 4GB RAM, 20GB storage)

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
    esac

    if [[ -n "${LOG_FILE}" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

setup_logging() {
    local log_dir="${PROJECT_ROOT}/logs/user-provisioning"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-provisioning.log"
    log INFO "Logging to: $LOG_FILE"
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

    # Check kubeconfig
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        exit 1
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info > /dev/null 2>&1; then
        log ERROR "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

validate_team() {
    if [[ -z "$TEAM" ]]; then
        log ERROR "Team is required for most operations"
        return 1
    fi

    # Set defaults if not provided
    if [[ -z "$DEFAULT_RESOURCES" ]] && [[ -n "${TEAM_DEFAULTS[$TEAM]}" ]]; then
        DEFAULT_RESOURCES="${TEAM_DEFAULTS[$TEAM]}"
        log INFO "Using default resources for $TEAM: $DEFAULT_RESOURCES"
    fi

    if [[ -z "$TEMPLATE" ]] && [[ -n "${TEAM_TEMPLATES[$TEAM]}" ]]; then
        TEMPLATE="${TEAM_TEMPLATES[$TEAM]}"
        log INFO "Using default template for $TEAM: $TEMPLATE"
    fi

    log INFO "Team configuration: $TEAM"
    log INFO "Template: ${TEMPLATE:-none}"
    log INFO "Default resources: ${DEFAULT_RESOURCES:-none}"
}

parse_resources() {
    local resources="$1"

    # Parse resource string like "cpu=2,memory=4Gi,storage=20Gi"
    local cpu=$(echo "$resources" | grep -o 'cpu=[^,]*' | cut -d= -f2 || echo "1")
    local memory=$(echo "$resources" | grep -o 'memory=[^,]*' | cut -d= -f2 || echo "2Gi")
    local storage=$(echo "$resources" | grep -o 'storage=[^,]*' | cut -d= -f2 || echo "10Gi")

    echo "CPU=$cpu MEMORY=$memory STORAGE=$storage"
}

create_team_namespace() {
    local team="$1"
    local namespace="team-$team"

    log STEP "Creating namespace for team: $team"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create namespace: $namespace"
        return 0
    fi

    # Create namespace
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

    # Label namespace
    kubectl label namespace "$namespace" team="$team" coder.com/team="$team" --overwrite

    log INFO "✅ Namespace created: $namespace"
}

create_team_rbac() {
    local team="$1"
    local namespace="team-$team"

    log STEP "Creating RBAC for team: $team"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create RBAC for team: $team"
        return 0
    fi

    # Create Role
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $namespace
  name: ${team}-developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["pods/log", "pods/exec"]
  verbs: ["get", "list", "create"]
EOF

    # Create Coder namespace access (limited)
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: coder
  name: ${team}-coder-user
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
  resourceNames: []  # Limited to own workspaces via admission controller
- apiGroups: [""]
  resources: ["pods/log", "pods/exec"]
  verbs: ["get", "create"]
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch"]
EOF

    # Create RoleBinding for OAuth group
    if [[ -n "$OAUTH_GROUP" ]]; then
        cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${team}-team-binding
  namespace: $namespace
subjects:
- kind: Group
  name: $OAUTH_GROUP
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${team}-developer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${team}-coder-binding
  namespace: coder
subjects:
- kind: Group
  name: $OAUTH_GROUP
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${team}-coder-user
  apiGroup: rbac.authorization.k8s.io
EOF
    fi

    log INFO "✅ RBAC created for team: $team"
}

create_resource_quota() {
    local team="$1"
    local resources="$2"
    local namespace="team-$team"

    log STEP "Creating resource quota for team: $team"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create resource quota for team: $team"
        return 0
    fi

    # Parse resources
    local resource_vars
    resource_vars=$(parse_resources "$resources")
    eval "$resource_vars"

    # Calculate team quotas (assuming 10 users per team max)
    local team_cpu=$((CPU * 10))
    local team_memory_num=$(echo "$MEMORY" | sed 's/Gi//')
    local team_memory=$((team_memory_num * 10))
    local team_storage_num=$(echo "$STORAGE" | sed 's/Gi//')
    local team_storage=$((team_storage_num * 10))

    # Create ResourceQuota
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${team}-quota
  namespace: $namespace
spec:
  hard:
    requests.cpu: "${team_cpu}"
    requests.memory: "${team_memory}Gi"
    requests.storage: "${team_storage}Gi"
    persistentvolumeclaims: "50"
    pods: "100"
    services: "20"
    secrets: "50"
    configmaps: "50"
EOF

    # Create default LimitRange for individual workspaces
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: ${team}-limits
  namespace: $namespace
spec:
  limits:
  - type: Container
    default:
      cpu: "${CPU}"
      memory: "$MEMORY"
    defaultRequest:
      cpu: "$(echo "scale=2; $CPU * 0.1" | bc)"
      memory: "$(echo "scale=0; ${team_memory_num} * 0.1" | bc | cut -d. -f1)Mi"
    max:
      cpu: "$((CPU * 2))"
      memory: "$((team_memory_num * 2))Gi"
  - type: PersistentVolumeClaim
    max:
      storage: "${STORAGE}"
EOF

    log INFO "✅ Resource quota created for team: $team"
    log INFO "   CPU limit: ${team_cpu} cores"
    log INFO "   Memory limit: ${team_memory}Gi"
    log INFO "   Storage limit: ${team_storage}Gi"
}

create_coder_template_rbac() {
    local team="$1"
    local template="$2"

    log STEP "Configuring template access for team: $team"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would configure template access for team: $team"
        return 0
    fi

    # Create ConfigMap for team template configuration
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${team}-template-config
  namespace: coder
  labels:
    team: $team
    coder.com/team: $team
data:
  default-template: "$template"
  allowed-templates: "$template,claude-flow-base"  # Always allow AI-enhanced template
  resource-defaults: "$DEFAULT_RESOURCES"
  team-namespace: "team-$team"
EOF

    log INFO "✅ Template configuration created for team: $team"
}

add_user_to_team() {
    local team="$1"
    local user_email="$2"

    log STEP "Adding user to team: $user_email -> $team"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would add user $user_email to team $team"
        return 0
    fi

    # Create or update user ConfigMap
    local user_config="user-$(echo "$user_email" | sed 's/@/-at-/; s/\./-/g')"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: $user_config
  namespace: coder
  labels:
    user-email: "$user_email"
    team: "$team"
    coder.com/user: "true"
data:
  email: "$user_email"
  team: "$team"
  default-template: "${TEMPLATE:-}"
  resource-defaults: "${DEFAULT_RESOURCES:-}"
  joined-date: "$(date -Iseconds)"
EOF

    # Add user to team RoleBinding (if using individual user management)
    if [[ -z "$OAUTH_GROUP" ]]; then
        # Create individual user RoleBinding
        cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${user_config}-binding
  namespace: team-$team
subjects:
- kind: User
  name: $user_email
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${team}-developer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${user_config}-coder-binding
  namespace: coder
subjects:
- kind: User
  name: $user_email
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${team}-coder-user
  apiGroup: rbac.authorization.k8s.io
EOF
    fi

    log INFO "✅ User added to team: $user_email -> $team"
}

remove_user_from_team() {
    local team="$1"
    local user_email="$2"

    log STEP "Removing user from team: $user_email -> $team"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would remove user $user_email from team $team"
        return 0
    fi

    local user_config="user-$(echo "$user_email" | sed 's/@/-at-/; s/\./-/g')"

    # Remove user ConfigMap
    kubectl delete configmap "$user_config" -n coder --ignore-not-found=true

    # Remove user RoleBindings
    kubectl delete rolebinding "${user_config}-binding" -n "team-$team" --ignore-not-found=true
    kubectl delete rolebinding "${user_config}-coder-binding" -n coder --ignore-not-found=true

    log INFO "✅ User removed from team: $user_email -> $team"
}

remove_team() {
    local team="$1"
    local namespace="team-$team"

    log STEP "Removing team: $team"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would remove team: $team"
        return 0
    fi

    # Warn about data loss
    if [[ "$BATCH_MODE" == "false" ]]; then
        echo
        log WARN "This will DELETE all resources for team: $team"
        log WARN "Including namespaces, RBAC, quotas, and user configurations"
        echo
        read -p "Are you sure you want to remove team $team? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Team removal cancelled"
            return 0
        fi
    fi

    # Remove team namespace (this cascades most resources)
    kubectl delete namespace "$namespace" --ignore-not-found=true

    # Remove team-specific resources in coder namespace
    kubectl delete configmap "${team}-template-config" -n coder --ignore-not-found=true
    kubectl delete role "${team}-coder-user" -n coder --ignore-not-found=true
    kubectl delete rolebinding "${team}-coder-binding" -n coder --ignore-not-found=true

    # Remove user ConfigMaps for this team
    kubectl delete configmap -l team="$team" -n coder --ignore-not-found=true

    log INFO "✅ Team removed: $team"
}

list_teams_and_users() {
    log STEP "Listing teams and users for environment: $ENVIRONMENT"

    # List team namespaces
    local team_namespaces=$(kubectl get namespaces -l coder.com/team --no-headers -o custom-columns=":metadata.name" 2>/dev/null || echo "")

    if [[ -z "$team_namespaces" ]]; then
        log INFO "No teams found in environment: $ENVIRONMENT"
        return 0
    fi

    echo
    echo -e "${WHITE}📋 Teams and Users:${NC}"
    echo

    while IFS= read -r namespace; do
        if [[ -n "$namespace" ]]; then
            local team=$(echo "$namespace" | sed 's/team-//')
            echo -e "${CYAN}Team: $team${NC}"

            # Get team configuration
            local template_config=$(kubectl get configmap "${team}-template-config" -n coder -o jsonpath='{.data.default-template}' 2>/dev/null || echo "none")
            local resource_defaults=$(kubectl get configmap "${team}-template-config" -n coder -o jsonpath='{.data.resource-defaults}' 2>/dev/null || echo "none")

            echo "  Template: $template_config"
            echo "  Resources: $resource_defaults"

            # List team users
            local users=$(kubectl get configmap -n coder -l team="$team" --no-headers -o jsonpath='{.items[*].data.email}' 2>/dev/null || echo "")

            if [[ -n "$users" ]]; then
                echo "  Users:"
                for user in $users; do
                    echo "    - $user"
                done
            else
                echo "  Users: none"
            fi

            # Show resource usage if available
            local quota=$(kubectl get resourcequota "${team}-quota" -n "$namespace" -o jsonpath='{.status.used}' 2>/dev/null || echo "")

            if [[ -n "$quota" ]]; then
                local used_cpu=$(echo "$quota" | jq -r '."requests.cpu" // "0"')
                local used_memory=$(echo "$quota" | jq -r '."requests.memory" // "0"')
                local used_pods=$(echo "$quota" | jq -r '.pods // "0"')

                echo "  Resource Usage:"
                echo "    CPU: $used_cpu"
                echo "    Memory: $used_memory"
                echo "    Pods: $used_pods"
            fi

            echo
        fi
    done <<< "$team_namespaces"
}

process_user_list() {
    local user_file="$1"
    local team="$2"
    local action="$3"

    if [[ ! -f "$user_file" ]]; then
        log ERROR "User list file not found: $user_file"
        return 1
    fi

    log STEP "Processing user list: $user_file"

    local total_users=0
    local processed_users=0

    while IFS= read -r user_email; do
        # Skip empty lines and comments
        if [[ -z "$user_email" ]] || [[ "$user_email" =~ ^# ]]; then
            continue
        fi

        ((total_users++))

        # Validate email format (basic check)
        if [[ ! "$user_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log WARN "Invalid email format, skipping: $user_email"
            continue
        fi

        # Process user
        case "$action" in
            "add")
                if add_user_to_team "$team" "$user_email"; then
                    ((processed_users++))
                fi
                ;;
            "remove")
                if remove_user_from_team "$team" "$user_email"; then
                    ((processed_users++))
                fi
                ;;
        esac
    done < "$user_file"

    log INFO "✅ Processed $processed_users/$total_users users from file"
}

print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${GREEN}🎉 User provisioning completed! 🎉${NC}"
    echo
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Action:${NC} $ACTION"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"

    if [[ "$ACTION" == "add" ]] && [[ -n "$TEAM" ]]; then
        echo
        echo -e "${YELLOW}📋 Team Configuration:${NC}"
        echo "   • Team: $TEAM"
        echo "   • Template: ${TEMPLATE:-default}"
        echo "   • Resources: ${DEFAULT_RESOURCES:-default}"
        echo "   • OAuth Group: ${OAUTH_GROUP:-none}"
        echo "   • Namespace: team-$TEAM"
    fi

    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo "   • Verify team access in Coder web interface"
    echo "   • Test workspace creation with team template"
    echo "   • Configure OAuth provider group mappings"
    echo "   • Monitor resource usage and adjust quotas if needed"
    echo "   • Update team documentation and onboarding"

    echo
    echo -e "${CYAN}📁 Resources Created:${NC}"
    if [[ -n "$TEAM" ]]; then
        echo "   • Namespace: team-$TEAM"
        echo "   • RBAC: Roles and RoleBindings for $TEAM"
        echo "   • Resource Quota: CPU, Memory, Storage limits"
        echo "   • Template Config: Default template and resource settings"
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
            --action=*)
                ACTION="${1#*=}"
                shift
                ;;
            --team=*)
                TEAM="${1#*=}"
                shift
                ;;
            --template=*)
                TEMPLATE="${1#*=}"
                shift
                ;;
            --default-resources=*)
                DEFAULT_RESOURCES="${1#*=}"
                shift
                ;;
            --oauth-group=*)
                OAUTH_GROUP="${1#*=}"
                shift
                ;;
            --user-email=*)
                USER_EMAIL="${1#*=}"
                shift
                ;;
            --user-list=*)
                USER_LIST="${1#*=}"
                shift
                ;;
            --batch)
                BATCH_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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

    # Validate action
    case "$ACTION" in
        add|remove|update|list)
            ;;
        *)
            log ERROR "Invalid action: $ACTION"
            log ERROR "Must be one of: add, remove, update, list"
            exit 1
            ;;
    esac

    print_banner
    setup_logging
    validate_environment

    log INFO "Starting user provisioning for environment: $ENVIRONMENT"
    log INFO "Action: $ACTION"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🧪 Running in DRY RUN mode"
    fi

    # Execute action
    case "$ACTION" in
        "add")
            if [[ -z "$TEAM" ]]; then
                log ERROR "Team is required for add action"
                exit 1
            fi

            validate_team

            # Create team infrastructure
            create_team_namespace "$TEAM"
            create_team_rbac "$TEAM"
            create_resource_quota "$TEAM" "$DEFAULT_RESOURCES"

            if [[ -n "$TEMPLATE" ]]; then
                create_coder_template_rbac "$TEAM" "$TEMPLATE"
            fi

            # Add users
            if [[ -n "$USER_EMAIL" ]]; then
                add_user_to_team "$TEAM" "$USER_EMAIL"
            elif [[ -n "$USER_LIST" ]]; then
                process_user_list "$USER_LIST" "$TEAM" "add"
            fi
            ;;

        "remove")
            if [[ -z "$TEAM" ]] && [[ -z "$USER_EMAIL" ]]; then
                log ERROR "Either team or user-email is required for remove action"
                exit 1
            fi

            if [[ -n "$USER_EMAIL" ]] && [[ -n "$TEAM" ]]; then
                # Remove individual user from team
                remove_user_from_team "$TEAM" "$USER_EMAIL"
            elif [[ -n "$USER_LIST" ]] && [[ -n "$TEAM" ]]; then
                # Remove users from file
                process_user_list "$USER_LIST" "$TEAM" "remove"
            elif [[ -n "$TEAM" ]]; then
                # Remove entire team
                remove_team "$TEAM"
            fi
            ;;

        "update")
            log ERROR "Update action not yet implemented"
            exit 1
            ;;

        "list")
            list_teams_and_users
            exit 0
            ;;
    esac

    if [[ "$DRY_RUN" == "false" ]]; then
        print_summary
    else
        echo
        log INFO "🧪 Dry run completed - no changes were made"
    fi
}

# Check for required dependencies
command -v kubectl >/dev/null 2>&1 || { log ERROR "kubectl is required but not installed. Aborting."; exit 1; }

# Run main function with all arguments
main "$@"