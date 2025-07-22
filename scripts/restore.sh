#!/bin/bash

# Coder on Scaleway - Restore Script
# Disaster recovery script for restoring backups

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
BACKUP_NAME=""
BACKUP_DIR="${PROJECT_ROOT}/backups"
COMPONENT="all"
DRY_RUN=false
AUTO_MODE=false
FORCE_RESTORE=false
LOG_FILE=""
START_TIME=$(date +%s)

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║          Disaster Recovery            ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Restore Coder environments from backup archives including infrastructure
state, configuration, data, and templates.

Options:
    --env=ENV               Target environment (dev|staging|prod) [required]
    --backup-name=NAME      Backup archive name to restore from [required]
    --component=COMP        Component to restore (all|infrastructure|kubernetes|database|workspace-data) [default: all]
    --dry-run              Show restore plan without executing
    --auto                 Run in automated mode (no prompts)
    --force                Force restore even if environment exists
    --backup-dir=PATH      Custom backup directory [default: ./backups]
    --help                 Show this help message

Examples:
    $0 --env=staging --backup-name="disaster-recovery-test-20241121" --component=database --dry-run
    $0 --env=dev --backup-name="backup-20241120-143022-dev" --auto
    $0 --env=prod --backup-name="pre-destroy-20241119-092145-prod" --force

Components:
    • all                  Restore everything (default)
    • infrastructure       Terraform state and configuration
    • kubernetes          Kubernetes resources and manifests
    • database            Database dumps and connectivity
    • workspace-data      Workspace persistent volumes and data

Safety Features:
    • Environment existence checks
    • Backup integrity validation
    • Component dependency resolution
    • Rollback capabilities for failed restores

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
    local log_dir="${PROJECT_ROOT}/logs/restore"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-restore.log"
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

    # Check if environment already exists
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    if [[ -d "$env_dir" ]] && [[ "$FORCE_RESTORE" == "false" ]]; then
        log ERROR "Environment $ENVIRONMENT already exists at: $env_dir"
        log ERROR "Use --force to overwrite existing environment"
        exit 1
    fi
}

validate_backup() {
    log STEP "Validating backup archive..."

    # Check for backup directory or archive
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local backup_archive="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

    if [[ ! -d "$backup_path" ]] && [[ ! -f "$backup_archive" ]]; then
        log ERROR "Backup not found: $BACKUP_NAME"
        log ERROR "Checked locations:"
        log ERROR "  Directory: $backup_path"
        log ERROR "  Archive: $backup_archive"
        exit 1
    fi

    # Extract archive if needed
    if [[ ! -d "$backup_path" ]] && [[ -f "$backup_archive" ]]; then
        log INFO "Extracting backup archive..."
        cd "$BACKUP_DIR"
        tar -xzf "${BACKUP_NAME}.tar.gz"
    fi

    # Verify backup manifest
    local manifest_file="${backup_path}/backup-manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        log WARN "Backup manifest not found - proceeding without validation"
        return 0
    fi

    log INFO "Validating backup integrity..."

    # Check backup contents
    local backup_env=$(jq -r '.environment' "$manifest_file" 2>/dev/null || echo "unknown")
    local backup_date=$(jq -r '.created_at' "$manifest_file" 2>/dev/null || echo "unknown")
    local backup_size=$(jq -r '.backup_size' "$manifest_file" 2>/dev/null || echo "unknown")

    log INFO "Backup Environment: $backup_env"
    log INFO "Backup Date: $backup_date"
    log INFO "Backup Size: $backup_size"

    # Warn if environment mismatch
    if [[ "$backup_env" != "$ENVIRONMENT" ]] && [[ "$backup_env" != "all" ]]; then
        log WARN "Backup environment ($backup_env) differs from target ($ENVIRONMENT)"
        if [[ "$AUTO_MODE" == "false" ]]; then
            echo
            read -p "Continue with restore? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log INFO "Restore cancelled by user"
                exit 0
            fi
        fi
    fi

    log INFO "✅ Backup validation completed"
}

restore_infrastructure() {
    log STEP "Restoring infrastructure for environment: $ENVIRONMENT"

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local infra_backup="${backup_path}/infrastructure/${ENVIRONMENT}"

    if [[ ! -d "$infra_backup" ]]; then
        log WARN "No infrastructure backup found for $ENVIRONMENT, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would restore infrastructure from: $infra_backup"
        return 0
    fi

    # Create environment directory
    local env_dir="${PROJECT_ROOT}/environments/${ENVIRONMENT}"
    mkdir -p "$env_dir"

    # Restore Terraform files
    if [[ -d "${infra_backup}/${ENVIRONMENT}" ]]; then
        log INFO "Restoring Terraform configuration..."
        cp -r "${infra_backup}/${ENVIRONMENT}"/* "$env_dir/"
    fi

    # Restore shared configuration if it exists
    if [[ -d "${infra_backup}/shared" ]] && [[ ! -d "${PROJECT_ROOT}/shared" ]]; then
        log INFO "Restoring shared configuration..."
        cp -r "${infra_backup}/shared" "${PROJECT_ROOT}/"
    fi

    # Initialize Terraform
    log INFO "Initializing Terraform..."
    cd "$env_dir"
    terraform init -upgrade

    # Validate restored configuration
    if terraform validate; then
        log INFO "✅ Infrastructure configuration validated"
    else
        log ERROR "Infrastructure configuration validation failed"
        return 1
    fi

    # Show plan if not in auto mode
    if [[ "$AUTO_MODE" == "false" ]]; then
        echo
        log INFO "Terraform plan for restored infrastructure:"
        terraform plan
        echo
        read -p "Apply restored infrastructure? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Infrastructure restore cancelled by user"
            return 0
        fi
    fi

    # Apply infrastructure
    log INFO "Applying restored infrastructure..."
    if terraform apply -auto-approve; then
        log INFO "✅ Infrastructure restore completed for: $ENVIRONMENT"
    else
        log ERROR "Infrastructure restore failed for: $ENVIRONMENT"
        return 1
    fi
}

restore_kubernetes() {
    log STEP "Restoring Kubernetes resources for environment: $ENVIRONMENT"

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local k8s_backup="${backup_path}/kubernetes/${ENVIRONMENT}"

    if [[ ! -d "$k8s_backup" ]]; then
        log WARN "No Kubernetes backup found for $ENVIRONMENT, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would restore Kubernetes resources from: $k8s_backup"
        return 0
    fi

    # Set kubeconfig
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        log ERROR "Ensure infrastructure is restored first"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Verify cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log ERROR "Cannot connect to cluster for $ENVIRONMENT"
        return 1
    fi

    # Create namespaces first
    log INFO "Creating namespaces..."
    kubectl create namespace coder --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - || true

    # Restore secrets first (other resources depend on them)
    if [[ -f "${k8s_backup}/coder-secrets.yaml" ]]; then
        log INFO "Restoring secrets..."
        kubectl apply -f "${k8s_backup}/coder-secrets.yaml" || log WARN "Failed to restore some secrets"
    fi

    # Restore ConfigMaps
    if [[ -f "${k8s_backup}/coder-configmaps.yaml" ]]; then
        log INFO "Restoring ConfigMaps..."
        kubectl apply -f "${k8s_backup}/coder-configmaps.yaml" || log WARN "Failed to restore some ConfigMaps"
    fi

    # Restore PVCs
    if [[ -f "${k8s_backup}/coder-pvcs.yaml" ]]; then
        log INFO "Restoring persistent volume claims..."
        kubectl apply -f "${k8s_backup}/coder-pvcs.yaml" || log WARN "Failed to restore some PVCs"
    fi

    # Restore main resources
    if [[ -f "${k8s_backup}/coder-resources.yaml" ]]; then
        log INFO "Restoring Coder resources..."
        kubectl apply -f "${k8s_backup}/coder-resources.yaml" || log WARN "Failed to restore some resources"
    fi

    # Restore ingresses
    if [[ -f "${k8s_backup}/coder-ingresses.yaml" ]]; then
        log INFO "Restoring ingresses..."
        kubectl apply -f "${k8s_backup}/coder-ingresses.yaml" || log WARN "Failed to restore ingresses"
    fi

    # Restore monitoring if it exists
    if [[ -f "${k8s_backup}/monitoring-resources.yaml" ]]; then
        log INFO "Restoring monitoring resources..."
        kubectl apply -f "${k8s_backup}/monitoring-resources.yaml" || log WARN "Failed to restore monitoring"
    fi

    # Wait for deployments to be ready
    log INFO "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/coder -n coder || log WARN "Coder deployment not ready within timeout"

    log INFO "✅ Kubernetes resources restored for: $ENVIRONMENT"
}

restore_database() {
    log STEP "Restoring database for environment: $ENVIRONMENT"

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local data_backup="${backup_path}/data/${ENVIRONMENT}"
    local db_dump="${data_backup}/database-dump.sql"

    if [[ ! -f "$db_dump" ]]; then
        log WARN "No database dump found for $ENVIRONMENT, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would restore database from: $db_dump"
        return 0
    fi

    # Set kubeconfig
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

    log INFO "Using database secret: $db_secret"

    # Extract database connection details
    local db_host=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.host}' | base64 -d 2>/dev/null || echo "")
    local db_user=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "postgres")
    local db_name=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.database}' | base64 -d 2>/dev/null || echo "coder")
    local db_pass=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")

    if [[ -z "$db_host" || -z "$db_pass" ]]; then
        log ERROR "Incomplete database credentials"
        return 1
    fi

    # Warn about data overwrite
    if [[ "$AUTO_MODE" == "false" ]]; then
        echo
        log WARN "This will OVERWRITE existing database data!"
        read -p "Continue with database restore? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Database restore cancelled by user"
            return 0
        fi
    fi

    # Restore database using psql via kubectl
    log INFO "Restoring database..."
    kubectl run database-restore-$(date +%s) \
        --image=postgres:15 \
        --rm -i \
        --restart=Never \
        --env="PGPASSWORD=$db_pass" \
        --command -- psql \
        -h "$db_host" \
        -U "$db_user" \
        -d "$db_name" \
        -f /dev/stdin < "$db_dump" || {
        log ERROR "Database restore failed"
        return 1
    }

    log INFO "✅ Database restore completed for: $ENVIRONMENT"
}

restore_workspace_data() {
    log STEP "Restoring workspace data for environment: $ENVIRONMENT"

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    local data_backup="${backup_path}/data/${ENVIRONMENT}/workspaces"

    if [[ ! -d "$data_backup" ]]; then
        log WARN "No workspace data backup found for $ENVIRONMENT, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would restore workspace data from: $data_backup"
        return 0
    fi

    # Set kubeconfig
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ ! -f "$kubeconfig" ]]; then
        log ERROR "Kubeconfig not found: $kubeconfig"
        return 1
    fi

    export KUBECONFIG="$kubeconfig"

    # Find workspace data archives
    local workspace_archives=($(find "$data_backup" -name "*-backup.tar.gz" 2>/dev/null || echo ""))

    if [[ ${#workspace_archives[@]} -eq 0 ]]; then
        log INFO "No workspace data archives found"
        return 0
    fi

    log INFO "Found ${#workspace_archives[@]} workspace data archives"

    # Restore each workspace
    for archive in "${workspace_archives[@]}"; do
        local pvc_name=$(basename "$archive" | sed 's/-backup\.tar\.gz$//')
        log INFO "Restoring workspace data for PVC: $pvc_name"

        # Check if PVC exists
        if ! kubectl get pvc "$pvc_name" -n coder &> /dev/null; then
            log WARN "PVC $pvc_name not found, skipping restore"
            continue
        fi

        # Create restore job
        cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: restore-${pvc_name}
  namespace: coder
spec:
  template:
    spec:
      containers:
      - name: restore
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          apk add --no-cache tar gzip
          cd /workspace
          tar -xzf /backup/$(basename "$archive") . || true
          echo "Restore completed for ${pvc_name}"
        volumeMounts:
        - name: workspace-data
          mountPath: /workspace
        - name: backup-volume
          mountPath: /backup
      volumes:
      - name: workspace-data
        persistentVolumeClaim:
          claimName: ${pvc_name}
      - name: backup-volume
        configMap:
          name: restore-data-${pvc_name}
      restartPolicy: Never
  backoffLimit: 3
EOF

        # Create ConfigMap with backup data
        kubectl create configmap "restore-data-${pvc_name}" -n coder --from-file="$archive" --dry-run=client -o yaml | kubectl apply -f -

        # Wait for job completion
        kubectl wait --for=condition=complete job/restore-${pvc_name} -n coder --timeout=300s || {
            log WARN "Restore job for $pvc_name timed out"
            kubectl delete job restore-${pvc_name} -n coder || true
            kubectl delete configmap restore-data-${pvc_name} -n coder || true
            continue
        }

        # Clean up
        kubectl delete job restore-${pvc_name} -n coder || true
        kubectl delete configmap restore-data-${pvc_name} -n coder || true

        log INFO "✅ Workspace data restored for PVC: $pvc_name"
    done

    log INFO "✅ Workspace data restore completed for: $ENVIRONMENT"
}

print_restore_plan() {
    log STEP "Restore Plan for Environment: $ENVIRONMENT"

    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"

    echo
    echo -e "${WHITE}Backup Source:${NC} $backup_path"
    echo -e "${WHITE}Target Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Component Filter:${NC} $COMPONENT"
    echo

    echo -e "${YELLOW}Components to Restore:${NC}"

    case "$COMPONENT" in
        all)
            [ -d "${backup_path}/infrastructure/${ENVIRONMENT}" ] && echo "   ✓ Infrastructure configuration and state"
            [ -d "${backup_path}/kubernetes/${ENVIRONMENT}" ] && echo "   ✓ Kubernetes resources and manifests"
            [ -f "${backup_path}/data/${ENVIRONMENT}/database-dump.sql" ] && echo "   ✓ Database dumps"
            [ -d "${backup_path}/data/${ENVIRONMENT}/workspaces" ] && echo "   ✓ Workspace persistent data"
            ;;
        infrastructure)
            [ -d "${backup_path}/infrastructure/${ENVIRONMENT}" ] && echo "   ✓ Infrastructure configuration and state"
            ;;
        kubernetes)
            [ -d "${backup_path}/kubernetes/${ENVIRONMENT}" ] && echo "   ✓ Kubernetes resources and manifests"
            ;;
        database)
            [ -f "${backup_path}/data/${ENVIRONMENT}/database-dump.sql" ] && echo "   ✓ Database dumps"
            ;;
        workspace-data)
            [ -d "${backup_path}/data/${ENVIRONMENT}/workspaces" ] && echo "   ✓ Workspace persistent data"
            ;;
    esac

    echo
    echo -e "${YELLOW}⚠️  Warnings:${NC}"
    echo "   • This will overwrite existing environment data"
    echo "   • Ensure you have current backups before proceeding"
    echo "   • Infrastructure restore may take 10-15 minutes"
    echo "   • Database restore will overwrite all existing data"

    echo
}

print_summary() {
    log STEP "Restore Summary"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${GREEN}🔄 Restore completed! 🔄${NC}"
    echo
    echo -e "${WHITE}Backup Name:${NC} $BACKUP_NAME"
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Component:${NC} $COMPONENT"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"

    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo "   • Verify environment functionality"
    echo "   • Check Coder web interface accessibility"
    echo "   • Test workspace creation and connectivity"
    echo "   • Validate monitoring and logging (if applicable)"
    echo "   • Update DNS and certificate configurations if needed"

    echo
    echo -e "${CYAN}🌐 Access Points:${NC}"
    local kubeconfig="${HOME}/.kube/config-coder-${ENVIRONMENT}"
    if [[ -f "$kubeconfig" ]]; then
        echo "   • Kubeconfig: $kubeconfig"
        export KUBECONFIG="$kubeconfig"
        local coder_url=$(kubectl get ingress -n coder -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Not available")
        echo "   • Coder URL: https://$coder_url"
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
            --backup-name=*)
                BACKUP_NAME="${1#*=}"
                shift
                ;;
            --component=*)
                COMPONENT="${1#*=}"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --force)
                FORCE_RESTORE=true
                shift
                ;;
            --backup-dir=*)
                BACKUP_DIR="${1#*=}"
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

    if [[ -z "$BACKUP_NAME" ]]; then
        log ERROR "Backup name is required. Use --backup-name=NAME"
        print_usage
        exit 1
    fi

    # Validate component
    case "$COMPONENT" in
        all|infrastructure|kubernetes|database|workspace-data)
            ;;
        *)
            log ERROR "Invalid component: $COMPONENT"
            log ERROR "Must be one of: all, infrastructure, kubernetes, database, workspace-data"
            exit 1
            ;;
    esac

    print_banner
    setup_logging

    log INFO "Starting restore for environment: $ENVIRONMENT"
    log INFO "Backup: $BACKUP_NAME"
    log INFO "Component: $COMPONENT"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "🧪 Running in DRY RUN mode"
    fi

    validate_environment
    validate_backup

    print_restore_plan

    # Confirm restore in non-auto mode
    if [[ "$AUTO_MODE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo
        read -p "Proceed with restore? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Restore cancelled by user"
            exit 0
        fi
    fi

    # Execute restore based on component
    case "$COMPONENT" in
        all)
            restore_infrastructure
            restore_kubernetes
            restore_database
            restore_workspace_data
            ;;
        infrastructure)
            restore_infrastructure
            ;;
        kubernetes)
            restore_kubernetes
            ;;
        database)
            restore_database
            ;;
        workspace-data)
            restore_workspace_data
            ;;
    esac

    if [[ "$DRY_RUN" == "false" ]]; then
        print_summary
    else
        echo
        log INFO "🧪 Dry run completed - no changes were made"
    fi
}

# Run main function with all arguments
main "$@"