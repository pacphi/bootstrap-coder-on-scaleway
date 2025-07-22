#!/bin/bash

# Coder on Scaleway - Backup Script
# Create comprehensive backups of environments, data, and configurations

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
BACKUP_NAME=""
INCLUDE_DATA=false
INCLUDE_CONFIG=true
INCLUDE_TEMPLATES=false
BACKUP_DIR="${PROJECT_ROOT}/backups"
AUTO_MODE=false
PRE_DESTROY=false
RETENTION_DAYS=30
LOG_FILE=""
START_TIME=$(date +%s)

print_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════╗
║           Coder on Scaleway           ║
║          Backup & Archive             ║
╚═══════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create comprehensive backups of Coder environments including infrastructure
state, configuration, data, and templates.

Options:
    --env=ENV               Environment to backup (dev|staging|prod|all) [required]
    --backup-name=NAME      Custom backup name (default: timestamp-based)
    --include-data          Include workspace data and databases
    --include-templates     Include workspace templates
    --no-config            Skip configuration backup
    --auto                 Run in automated mode (no prompts)
    --pre-destroy          Pre-destruction backup (includes everything)
    --retention-days=DAYS   Backup retention period (default: 30)
    --backup-dir=PATH       Custom backup directory
    --help                 Show this help message

Examples:
    $0 --env=dev --include-data
    $0 --env=prod --pre-destroy --backup-name="maintenance-$(date +%Y%m%d)"
    $0 --env=all --auto --retention-days=90

Backup Contents:
    • Terraform state and configuration
    • Kubernetes manifests and secrets
    • Database dumps (if --include-data)
    • Workspace persistent volumes (if --include-data)
    • Coder configuration and templates
    • Environment-specific settings

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
    local log_dir="${PROJECT_ROOT}/logs/backup"
    mkdir -p "$log_dir"
    LOG_FILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}-backup.log"
    log INFO "Logging to: $LOG_FILE"
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

prepare_backup_directory() {
    log STEP "Preparing backup directory..."

    # Generate backup name if not provided
    if [[ -z "$BACKUP_NAME" ]]; then
        if [[ "$PRE_DESTROY" == "true" ]]; then
            BACKUP_NAME="pre-destroy-$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}"
        else
            BACKUP_NAME="backup-$(date +%Y%m%d-%H%M%S)-${ENVIRONMENT}"
        fi
    fi

    # Create backup directory structure
    local backup_path="${BACKUP_DIR}/${BACKUP_NAME}"
    mkdir -p "${backup_path}"/{infrastructure,kubernetes,data,config,templates}

    log INFO "✅ Backup directory prepared: $backup_path"
    echo "$backup_path" # Return path for other functions
}

backup_infrastructure() {
    local env_name="$1"
    local backup_path="$2"

    log STEP "Backing up infrastructure for environment: $env_name"

    local env_dir="${PROJECT_ROOT}/environments/${env_name}"
    local infra_backup="${backup_path}/infrastructure/${env_name}"
    mkdir -p "$infra_backup"

    # Backup Terraform files
    if [[ -d "$env_dir" ]]; then
        log INFO "Copying Terraform configuration..."
        cp -r "$env_dir" "$infra_backup/"

        # Backup Terraform state
        if [[ -f "${env_dir}/terraform.tfstate" ]]; then
            log INFO "Backing up Terraform state..."
            cp "${env_dir}/terraform.tfstate" "${infra_backup}/"
        fi

        # Backup state backup files
        if ls "${env_dir}"/terraform.tfstate.backup* &> /dev/null; then
            cp "${env_dir}"/terraform.tfstate.backup* "${infra_backup}/" 2>/dev/null || true
        fi
    fi

    # Backup shared configuration
    if [[ -d "${PROJECT_ROOT}/shared" ]]; then
        log INFO "Backing up shared configuration..."
        cp -r "${PROJECT_ROOT}/shared" "${infra_backup}/"
    fi

    # Export Terraform outputs
    local outputs_file="${infra_backup}/terraform-outputs.json"
    if [[ -f "${env_dir}/terraform.tfstate" ]]; then
        cd "$env_dir"
        terraform output -json > "$outputs_file" 2>/dev/null || echo "{}" > "$outputs_file"
        cd - &> /dev/null
    fi

    log INFO "✅ Infrastructure backup completed for: $env_name"
}

backup_kubernetes() {
    local env_name="$1"
    local backup_path="$2"

    log STEP "Backing up Kubernetes resources for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found for $env_name, skipping Kubernetes backup"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info &> /dev/null; then
        log WARN "Cannot connect to cluster for $env_name, skipping Kubernetes backup"
        return 0
    fi

    local k8s_backup="${backup_path}/kubernetes/${env_name}"
    mkdir -p "$k8s_backup"

    # Backup all resources in coder namespace
    if kubectl get namespace coder &> /dev/null; then
        log INFO "Backing up Coder namespace resources..."

        # Export all resources
        kubectl get all -n coder -o yaml > "${k8s_backup}/coder-resources.yaml" 2>/dev/null || true
        kubectl get configmaps -n coder -o yaml > "${k8s_backup}/coder-configmaps.yaml" 2>/dev/null || true
        kubectl get secrets -n coder -o yaml > "${k8s_backup}/coder-secrets.yaml" 2>/dev/null || true
        kubectl get pvc -n coder -o yaml > "${k8s_backup}/coder-pvcs.yaml" 2>/dev/null || true
        kubectl get ingresses -n coder -o yaml > "${k8s_backup}/coder-ingresses.yaml" 2>/dev/null || true
    fi

    # Backup monitoring resources if they exist
    if kubectl get namespace monitoring &> /dev/null; then
        log INFO "Backing up monitoring namespace resources..."
        kubectl get all -n monitoring -o yaml > "${k8s_backup}/monitoring-resources.yaml" 2>/dev/null || true
    fi

    # Backup cluster-wide resources
    log INFO "Backing up cluster-wide resources..."
    kubectl get nodes -o yaml > "${k8s_backup}/nodes.yaml" 2>/dev/null || true
    kubectl get storageclasses -o yaml > "${k8s_backup}/storageclasses.yaml" 2>/dev/null || true
    kubectl get clusterroles -o yaml > "${k8s_backup}/clusterroles.yaml" 2>/dev/null || true
    kubectl get clusterrolebindings -o yaml > "${k8s_backup}/clusterrolebindings.yaml" 2>/dev/null || true

    # Create resource inventory
    cat > "${k8s_backup}/inventory.txt" <<EOF
# Kubernetes Resource Inventory for ${env_name}
# Generated: $(date)

== Namespaces ==
$(kubectl get namespaces --no-headers 2>/dev/null || echo "Unable to retrieve namespaces")

== Coder Resources ==
$(kubectl get all -n coder --no-headers 2>/dev/null || echo "Coder namespace not found")

== Persistent Volumes ==
$(kubectl get pv --no-headers 2>/dev/null || echo "No persistent volumes found")

== Storage Classes ==
$(kubectl get storageclasses --no-headers 2>/dev/null || echo "No storage classes found")

== Node Information ==
$(kubectl get nodes -o wide --no-headers 2>/dev/null || echo "Unable to retrieve node information")
EOF

    log INFO "✅ Kubernetes backup completed for: $env_name"
}

backup_database() {
    local env_name="$1"
    local backup_path="$2"

    log STEP "Backing up database for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found for $env_name, skipping database backup"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info &> /dev/null; then
        log WARN "Cannot connect to cluster for $env_name, skipping database backup"
        return 0
    fi

    local data_backup="${backup_path}/data/${env_name}"
    mkdir -p "$data_backup"

    # Get database connection details from secrets
    local db_secret=""
    if kubectl get secret coder-db-secret -n coder &> /dev/null; then
        db_secret="coder-db-secret"
    elif kubectl get secret coder-database -n coder &> /dev/null; then
        db_secret="coder-database"
    else
        log WARN "No database secret found, skipping database backup"
        return 0
    fi

    log INFO "Found database secret: $db_secret"

    # Extract database connection details
    local db_host=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.host}' | base64 -d 2>/dev/null || echo "")
    local db_user=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "postgres")
    local db_name=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.database}' | base64 -d 2>/dev/null || echo "coder")
    local db_pass=$(kubectl get secret "$db_secret" -n coder -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")

    if [[ -z "$db_host" || -z "$db_pass" ]]; then
        log WARN "Incomplete database credentials, skipping database backup"
        return 0
    fi

    # Create database backup using pg_dump via kubectl
    log INFO "Creating database dump..."
    kubectl run database-backup-$(date +%s) \
        --image=postgres:15 \
        --rm -i \
        --restart=Never \
        --env="PGPASSWORD=$db_pass" \
        --command -- pg_dump \
        -h "$db_host" \
        -U "$db_user" \
        -d "$db_name" \
        --no-password \
        --clean \
        --create > "${data_backup}/database-dump.sql" 2>/dev/null || {
        log WARN "Database backup failed, but continuing with other backups"
        return 0
    }

    # Create database info file
    cat > "${data_backup}/database-info.txt" <<EOF
# Database Backup Information
# Generated: $(date)

Database Host: $db_host
Database User: $db_user
Database Name: $db_name
Backup File: database-dump.sql

# Restore Instructions:
# 1. Ensure PostgreSQL is running and accessible
# 2. Create database if it doesn't exist:
#    createdb -h <host> -U <user> <database_name>
# 3. Restore from dump:
#    psql -h <host> -U <user> -d <database_name> -f database-dump.sql
EOF

    log INFO "✅ Database backup completed for: $env_name"
}

backup_workspace_data() {
    local env_name="$1"
    local backup_path="$2"

    log STEP "Backing up workspace data for environment: $env_name"

    local kubeconfig="${HOME}/.kube/config-coder-${env_name}"
    if [[ ! -f "$kubeconfig" ]]; then
        log WARN "Kubeconfig not found for $env_name, skipping workspace data backup"
        return 0
    fi

    export KUBECONFIG="$kubeconfig"

    if ! kubectl cluster-info &> /dev/null; then
        log WARN "Cannot connect to cluster for $env_name, skipping workspace data backup"
        return 0
    fi

    local data_backup="${backup_path}/data/${env_name}"
    mkdir -p "${data_backup}/workspaces"

    # Get list of workspace PVCs
    local pvcs=($(kubectl get pvc -n coder -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""))

    if [[ ${#pvcs[@]} -eq 0 ]]; then
        log INFO "No workspace PVCs found for backup"
        return 0
    fi

    log INFO "Found ${#pvcs[@]} workspace PVCs to backup"

    # Create backup job for each PVC
    for pvc in "${pvcs[@]}"; do
        log INFO "Backing up workspace data from PVC: $pvc"

        # Create a backup job
        cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: backup-${pvc}
  namespace: coder
spec:
  template:
    spec:
      containers:
      - name: backup
        image: alpine:latest
        command:
        - /bin/sh
        - -c
        - |
          apk add --no-cache tar gzip
          cd /workspace
          tar -czf /backup/${pvc}-backup.tar.gz . 2>/dev/null || true
          echo "Backup completed for ${pvc}"
        volumeMounts:
        - name: workspace-data
          mountPath: /workspace
        - name: backup-volume
          mountPath: /backup
      volumes:
      - name: workspace-data
        persistentVolumeClaim:
          claimName: ${pvc}
      - name: backup-volume
        emptyDir: {}
      restartPolicy: Never
  backoffLimit: 3
EOF

        # Wait for job completion
        kubectl wait --for=condition=complete job/backup-${pvc} -n coder --timeout=300s || {
            log WARN "Backup job for $pvc timed out"
            kubectl delete job backup-${pvc} -n coder || true
            continue
        }

        # Copy backup file from pod
        local pod_name=$(kubectl get pods -n coder -l job-name=backup-${pvc} -o jsonpath='{.items[0].metadata.name}')
        if [[ -n "$pod_name" ]]; then
            kubectl cp "coder/${pod_name}:/backup/${pvc}-backup.tar.gz" "${data_backup}/workspaces/${pvc}-backup.tar.gz" 2>/dev/null || {
                log WARN "Failed to copy backup for $pvc"
            }
        fi

        # Clean up job
        kubectl delete job backup-${pvc} -n coder || true
    done

    log INFO "✅ Workspace data backup completed for: $env_name"
}

backup_configuration() {
    local env_name="$1"
    local backup_path="$2"

    log STEP "Backing up configuration for environment: $env_name"

    local config_backup="${backup_path}/config/${env_name}"
    mkdir -p "$config_backup"

    # Backup scripts
    log INFO "Backing up scripts..."
    cp -r "${PROJECT_ROOT}/scripts" "${config_backup}/"

    # Backup modules
    if [[ -d "${PROJECT_ROOT}/modules" ]]; then
        log INFO "Backing up modules..."
        cp -r "${PROJECT_ROOT}/modules" "${config_backup}/"
    fi

    # Backup documentation
    if [[ -d "${PROJECT_ROOT}/docs" ]]; then
        cp -r "${PROJECT_ROOT}/docs" "${config_backup}/"
    fi

    # Copy important files
    for file in "README.md" "CLAUDE.md" "LICENSE"; do
        if [[ -f "${PROJECT_ROOT}/$file" ]]; then
            cp "${PROJECT_ROOT}/$file" "${config_backup}/"
        fi
    done

    # Create environment summary
    cat > "${config_backup}/environment-summary.txt" <<EOF
# Environment Summary for ${env_name}
# Generated: $(date)

== Project Information ==
Project Root: ${PROJECT_ROOT}
Environment: ${env_name}
Backup Name: ${BACKUP_NAME}

== Environment Directory Contents ==
$(ls -la "${PROJECT_ROOT}/environments/${env_name}" 2>/dev/null || echo "Environment directory not accessible")

== Available Templates ==
$(find "${PROJECT_ROOT}/templates" -name "main.tf" -type f | sed 's|.*/templates/||;s|/main.tf||' | sort 2>/dev/null || echo "Templates directory not accessible")

== Modules ==
$(ls -1 "${PROJECT_ROOT}/modules" 2>/dev/null || echo "Modules directory not accessible")
EOF

    log INFO "✅ Configuration backup completed for: $env_name"
}

backup_templates() {
    local backup_path="$1"

    log STEP "Backing up workspace templates..."

    if [[ ! -d "${PROJECT_ROOT}/templates" ]]; then
        log WARN "Templates directory not found, skipping template backup"
        return 0
    fi

    local template_backup="${backup_path}/templates"
    cp -r "${PROJECT_ROOT}/templates" "$template_backup/"

    # Create template inventory
    cat > "${template_backup}/template-inventory.txt" <<EOF
# Template Inventory
# Generated: $(date)

== Available Templates ==
$(find "${PROJECT_ROOT}/templates" -name "main.tf" -type f | sed 's|.*/templates/||;s|/main.tf||' | sort | sed 's/^/  - /')

== Template Categories ==
$(find "${PROJECT_ROOT}/templates" -mindepth 1 -maxdepth 1 -type d | sed 's|.*/templates/||' | sort | sed 's/^/  - /')

== Total Templates ==
$(find "${PROJECT_ROOT}/templates" -name "main.tf" -type f | wc -l)
EOF

    log INFO "✅ Template backup completed"
}

cleanup_old_backups() {
    log STEP "Cleaning up old backups (retention: ${RETENTION_DAYS} days)..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log INFO "No backup directory found, skipping cleanup"
        return 0
    fi

    local deleted_count=0

    # Find and delete old backups
    while IFS= read -r -d '' backup_dir; do
        if [[ -n "$backup_dir" ]]; then
            rm -rf "$backup_dir"
            ((deleted_count++))
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -print0 2>/dev/null || true)

    log INFO "✅ Cleanup completed: removed $deleted_count old backup(s)"
}

create_backup_manifest() {
    local backup_path="$1"

    log STEP "Creating backup manifest..."

    local manifest_file="${backup_path}/backup-manifest.json"
    local size=$(du -sh "$backup_path" | cut -f1)

    cat > "$manifest_file" <<EOF
{
  "backup_name": "$BACKUP_NAME",
  "environment": "$ENVIRONMENT",
  "created_at": "$(date -Iseconds)",
  "created_by": "$(whoami)",
  "hostname": "$(hostname)",
  "backup_size": "$size",
  "retention_days": $RETENTION_DAYS,
  "contents": {
    "infrastructure": $([ -d "${backup_path}/infrastructure" ] && echo "true" || echo "false"),
    "kubernetes": $([ -d "${backup_path}/kubernetes" ] && echo "true" || echo "false"),
    "database": $([ -f "${backup_path}/data/*/database-dump.sql" ] && echo "true" || echo "false"),
    "workspace_data": $([ -d "${backup_path}/data/*/workspaces" ] && echo "true" || echo "false"),
    "configuration": $([ -d "${backup_path}/config" ] && echo "true" || echo "false"),
    "templates": $([ -d "${backup_path}/templates" ] && echo "true" || echo "false")
  },
  "restore_instructions": "See backup documentation for restore procedures",
  "checksum": "$(find "$backup_path" -type f -exec sha256sum {} \; | sha256sum | cut -d' ' -f1)"
}
EOF

    log INFO "✅ Backup manifest created"
}

compress_backup() {
    local backup_path="$1"

    if [[ "$AUTO_MODE" == "false" ]]; then
        echo
        read -p "Compress backup archive? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    log STEP "Compressing backup archive..."

    local archive_name="${BACKUP_NAME}.tar.gz"
    local archive_path="${BACKUP_DIR}/${archive_name}"

    cd "$BACKUP_DIR"
    tar -czf "$archive_name" "$BACKUP_NAME"

    if [[ $? -eq 0 ]]; then
        local original_size=$(du -sh "$BACKUP_NAME" | cut -f1)
        local compressed_size=$(du -sh "$archive_name" | cut -f1)

        log INFO "✅ Backup compressed successfully"
        log INFO "   Original size: $original_size"
        log INFO "   Compressed size: $compressed_size"
        log INFO "   Archive: $archive_path"

        if [[ "$AUTO_MODE" == "false" ]]; then
            echo
            read -p "Remove uncompressed backup directory? (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$backup_path"
                log INFO "Uncompressed backup directory removed"
            fi
        fi
    else
        log ERROR "Backup compression failed"
        return 1
    fi
}

print_summary() {
    log STEP "Backup Summary"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))

    echo
    echo -e "${GREEN}📦 Backup completed successfully! 📦${NC}"
    echo
    echo -e "${WHITE}Backup Name:${NC} $BACKUP_NAME"
    echo -e "${WHITE}Environment:${NC} $ENVIRONMENT"
    echo -e "${WHITE}Duration:${NC} ${duration_min}m ${duration_sec}s"
    echo -e "${WHITE}Location:${NC} $BACKUP_DIR"

    if [[ -f "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" ]]; then
        local size=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
        echo -e "${WHITE}Archive Size:${NC} $size"
    else
        local size=$(du -sh "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1 2>/dev/null || echo "Unknown")
        echo -e "${WHITE}Backup Size:${NC} $size"
    fi

    echo
    echo -e "${YELLOW}📋 Backup Contents:${NC}"
    [ -d "${BACKUP_DIR}/${BACKUP_NAME}/infrastructure" ] && echo "   ✓ Infrastructure configuration and state"
    [ -d "${BACKUP_DIR}/${BACKUP_NAME}/kubernetes" ] && echo "   ✓ Kubernetes resources and manifests"
    [ -f "${BACKUP_DIR}/${BACKUP_NAME}/data/*/database-dump.sql" ] && echo "   ✓ Database dumps"
    [ -d "${BACKUP_DIR}/${BACKUP_NAME}/data/*/workspaces" ] && echo "   ✓ Workspace persistent data"
    [ -d "${BACKUP_DIR}/${BACKUP_NAME}/config" ] && echo "   ✓ Configuration files and scripts"
    [ -d "${BACKUP_DIR}/${BACKUP_NAME}/templates" ] && echo "   ✓ Workspace templates"

    echo
    echo -e "${YELLOW}🔧 Next Steps:${NC}"
    echo "   • Verify backup integrity: tar -tzf ${BACKUP_NAME}.tar.gz"
    echo "   • Store backup in secure location"
    echo "   • Test restore procedures periodically"
    echo "   • Update backup retention policies as needed"

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
            --include-data)
                INCLUDE_DATA=true
                shift
                ;;
            --include-templates)
                INCLUDE_TEMPLATES=true
                shift
                ;;
            --no-config)
                INCLUDE_CONFIG=false
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --pre-destroy)
                PRE_DESTROY=true
                INCLUDE_DATA=true
                INCLUDE_TEMPLATES=true
                shift
                ;;
            --retention-days=*)
                RETENTION_DAYS="${1#*=}"
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

    if [[ -z "$ENVIRONMENT" ]]; then
        log ERROR "Environment is required. Use --env=ENV"
        print_usage
        exit 1
    fi

    print_banner
    setup_logging

    log INFO "Starting backup for environment: $ENVIRONMENT"
    if [[ "$PRE_DESTROY" == "true" ]]; then
        log INFO "🚨 Pre-destruction backup mode enabled"
    fi

    validate_environment
    local backup_path=$(prepare_backup_directory)

    # Process environments
    if [[ "$ENVIRONMENT" == "all" ]]; then
        for env in dev staging prod; do
            if [[ -d "${PROJECT_ROOT}/environments/$env" ]]; then
                log INFO "Processing environment: $env"
                backup_infrastructure "$env" "$backup_path"
                backup_kubernetes "$env" "$backup_path"
                if [[ "$INCLUDE_DATA" == "true" ]]; then
                    backup_database "$env" "$backup_path"
                    backup_workspace_data "$env" "$backup_path"
                fi
                if [[ "$INCLUDE_CONFIG" == "true" ]]; then
                    backup_configuration "$env" "$backup_path"
                fi
            fi
        done
    else
        backup_infrastructure "$ENVIRONMENT" "$backup_path"
        backup_kubernetes "$ENVIRONMENT" "$backup_path"
        if [[ "$INCLUDE_DATA" == "true" ]]; then
            backup_database "$ENVIRONMENT" "$backup_path"
            backup_workspace_data "$ENVIRONMENT" "$backup_path"
        fi
        if [[ "$INCLUDE_CONFIG" == "true" ]]; then
            backup_configuration "$ENVIRONMENT" "$backup_path"
        fi
    fi

    # Backup templates if requested
    if [[ "$INCLUDE_TEMPLATES" == "true" ]]; then
        backup_templates "$backup_path"
    fi

    create_backup_manifest "$backup_path"
    cleanup_old_backups
    compress_backup "$backup_path"
    print_summary
}

# Run main function with all arguments
main "$@"