# Remote State Management with Scaleway Object Storage

This document provides a comprehensive guide for implementing remote Terraform state storage using Scaleway Object Storage in the Coder platform deployment project with **two-phase deployment architecture**.

## Overview

The implementation adds enterprise-grade remote state management capabilities with **separate state files for infrastructure and Coder application phases**, addressing the lack of centralized state storage and concurrent access issues identified in the GitHub Actions workflows.

## Key Features Implemented

### 🏗️ **Infrastructure Components**

- **Terraform Backend Module** (`modules/terraform-backend/`)
  - S3-compatible buckets for each environment
  - Bucket versioning and lifecycle management
  - Access control and security policies
  - Automated backend configuration generation

### 🔄 **Migration Tools**

- **Backend Setup Script** (`scripts/utils/setup-backend.sh`)
  - Creates Object Storage infrastructure for state storage
  - Supports single environment or batch setup
  - Dry-run capability for preview

- **State Migration Script** (`scripts/utils/migrate-state.sh`)
  - Safe migration from local to remote state
  - Backup creation and validation
  - Rollback capabilities

- **State Manager Utility** (`scripts/utils/state-manager.sh`)
  - State inspection and management
  - Backup and restore operations
  - Drift detection
  - Multi-format output (JSON, YAML, table)

### 🚀 **CI/CD Integration**

- **Enhanced GitHub Actions Workflows**
  - Separate plan and apply phases
  - Remote state support in all workflows
  - Plan artifacts and PR comments
  - Improved error handling and status reporting

## Architecture

### Two-Phase State Storage Structure

```text
Scaleway Object Storage Buckets (Two-Phase Architecture):
├── terraform-state-coder-dev/
│   ├── infra/terraform.tfstate      # Phase 1: Infrastructure state
│   └── coder/terraform.tfstate      # Phase 2: Coder application state
├── terraform-state-coder-staging/
│   ├── infra/terraform.tfstate
│   └── coder/terraform.tfstate
└── terraform-state-coder-prod/
    ├── infra/terraform.tfstate
    └── coder/terraform.tfstate
```

### Legacy vs Two-Phase Structure

The system automatically detects environment structure:

**Legacy Structure** (Single-phase, backward compatible):

```text
environments/dev/
├── main.tf
├── providers.tf
└── backend.tf → key = "dev/terraform.tfstate"
```

**Two-Phase Structure** (New architecture):

```text
environments/dev/
├── infra/
│   ├── main.tf
│   ├── providers.tf
│   └── backend.tf → key = "infra/terraform.tfstate"
└── coder/
    ├── main.tf
    ├── providers.tf
    └── backend.tf → key = "coder/terraform.tfstate"
```

### Backend Configuration

#### Infrastructure Phase (Phase 1)

```hcl
# environments/dev/infra/providers.tf
terraform {
  backend "s3" {
    bucket = "terraform-state-coder-dev"
    key    = "infra/terraform.tfstate"  # Infrastructure state
    region = "fr-par"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
  }
}
```

#### Coder Application Phase (Phase 2)

```hcl
# environments/dev/coder/providers.tf
terraform {
  backend "s3" {
    bucket = "terraform-state-coder-dev"
    key    = "coder/terraform.tfstate"  # Coder application state
    region = "fr-par"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
  }
}

# Remote state data source to read infrastructure outputs
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "terraform-state-coder-dev"
    key    = "infra/terraform.tfstate"
    region = "fr-par"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
  }
}
```

## Getting Started

### 1. Prerequisites

Ensure you have the required credentials configured:

```bash
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"
export SCW_DEFAULT_ORGANIZATION_ID="your-organization-id"
```

### AWS Environment Variables for S3 Backend

The Terraform S3 backend requires AWS-style environment variables for authentication, even when using Scaleway:

```bash
# Required for S3 backend authentication
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"
```

**Note**: These environment variables use AWS naming but contain your Scaleway credentials. This is a requirement of the Terraform S3 backend, which is designed for AWS S3 and expects these specific variable names.

### 2. Automatic Backend Provisioning (Recommended)

**The remote state backend is now automatically provisioned during GitHub Actions workflows with full two-phase support.**

When you run any deployment workflow (deploy-environment.yml, deploy-infrastructure.yml, deploy-coder.yml, teardown-environment.yml, or validate-templates.yml), the system will:

1. **Check if backend infrastructure exists** for the target environment
2. **Automatically create backend infrastructure** if it doesn't exist
3. **Generate phase-specific backend.tf configuration** files
   - `environments/{env}/infra/providers.tf` with key="infra/terraform.tfstate"
   - `environments/{env}/coder/providers.tf` with key="coder/terraform.tfstate"
4. **Validate backend connectivity** before proceeding with deployment
5. **Support both legacy and two-phase structures** automatically

**No manual setup is required for normal CI/CD operations.**

### 3. Manual Backend Creation (Optional)

For local development or troubleshooting (supports both legacy and two-phase structures):

```bash
# Setup backend for all environments (auto-detects structure)
./scripts/utils/setup-backend.sh --env=all

# Or setup individual environments
./scripts/utils/setup-backend.sh --env=dev
./scripts/utils/setup-backend.sh --env=staging
./scripts/utils/setup-backend.sh --env=prod

# The script automatically:
# - Detects if environment uses two-phase structure (infra/ + coder/)
# - Creates appropriate backend configurations for each phase
# - Generates remote state data sources for Phase 2
```

### 4. Migrate Existing State

For environments with existing local state (supports both structures):

#### Legacy Single-Phase Migration

```bash
# Preview migration (recommended first step)
./scripts/utils/migrate-state.sh --env=dev --dry-run

# Perform actual migration
./scripts/utils/migrate-state.sh --env=dev --verbose
```

#### Two-Phase Environment Migration

```bash
# Migrate infrastructure phase
./scripts/utils/migrate-state.sh --env=dev --phase=infra --dry-run
./scripts/utils/migrate-state.sh --env=dev --phase=infra --verbose

# Migrate Coder application phase
./scripts/utils/migrate-state.sh --env=dev --phase=coder --dry-run
./scripts/utils/migrate-state.sh --env=dev --phase=coder --verbose

# Or migrate both phases automatically
./scripts/utils/migrate-state.sh --env=dev --two-phase --dry-run
./scripts/utils/migrate-state.sh --env=dev --two-phase --verbose
```

### 5. Verify Remote State

#### Legacy Single-Phase Verification

```bash
# Check state connectivity
./scripts/utils/state-manager.sh show --env=dev

# List resources
./scripts/utils/state-manager.sh list --env=dev
```

#### Two-Phase Environment Verification

```bash
# Check infrastructure phase state
./scripts/utils/state-manager.sh show --env=dev --phase=infra

# Check Coder application phase state
./scripts/utils/state-manager.sh show --env=dev --phase=coder

# List resources in both phases
./scripts/utils/state-manager.sh list --env=dev --phase=infra
./scripts/utils/state-manager.sh list --env=dev --phase=coder

# Show comprehensive two-phase summary
./scripts/utils/state-manager.sh show --env=dev --two-phase
```

## State Management Operations

### Daily Operations

#### Legacy Single-Phase Operations

```bash
# Check state summary
./scripts/utils/state-manager.sh show --env=prod

# Create backup before major changes
./scripts/utils/state-manager.sh backup --env=prod

# Check for configuration drift
./scripts/utils/state-manager.sh drift --env=prod
```

#### Two-Phase Environment Operations

```bash
# Check both phases summary
./scripts/utils/state-manager.sh show --env=prod --two-phase

# Create backup of both phases before major changes
./scripts/utils/state-manager.sh backup --env=prod --two-phase

# Check for configuration drift in both phases
./scripts/utils/state-manager.sh drift --env=prod --two-phase

# Phase-specific operations
./scripts/utils/state-manager.sh show --env=prod --phase=infra
./scripts/utils/state-manager.sh backup --env=prod --phase=coder
./scripts/utils/state-manager.sh drift --env=prod --phase=infra

# Inspect state details with JSON output
./scripts/utils/state-manager.sh inspect --env=prod --phase=infra --format=json
./scripts/utils/state-manager.sh inspect --env=prod --phase=coder --format=json
```

### Backup Management

#### Legacy Single-Phase Backups

```bash
# Create manual backup
./scripts/utils/state-manager.sh backup --env=staging

# List available backups
ls backups/state-backups/

# Restore from backup (if needed)
./scripts/utils/state-manager.sh restore --env=staging --backup=staging-20240723-143022
```

#### Two-Phase Environment Backups

```bash
# Create backup of both phases
./scripts/utils/state-manager.sh backup --env=staging --two-phase

# Create phase-specific backups
./scripts/utils/state-manager.sh backup --env=staging --phase=infra
./scripts/utils/state-manager.sh backup --env=staging --phase=coder

# List available backups (organized by phase)
ls backups/state-backups/staging-infra/
ls backups/state-backups/staging-coder/

# Restore phase-specific backups
./scripts/utils/state-manager.sh restore --env=staging --phase=infra --backup=staging-infra-20240723-143022
./scripts/utils/state-manager.sh restore --env=staging --phase=coder --backup=staging-coder-20240723-143022
```

## GitHub Actions Integration

### Auto-Provisioning Workflow Features

1. **Backend Setup Phase** - Automatically provisions backend infrastructure before deployment
2. **Bucket Existence Checking** - Validates backend infrastructure exists or creates it
3. **Two-Phase Configuration** - Generates separate backend configurations for infrastructure and Coder phases
4. **Structure Detection** - Automatically detects legacy vs two-phase environment structure
5. **Remote State Data Sources** - Automatically configures Phase 2 to read Phase 1 outputs
6. **Plan Phase** - Generates and uploads Terraform plans using remote state for each phase
7. **Apply Phase** - Uses pre-generated plans for consistent deployments across both phases
8. **PR Comments** - Automatic plan summaries on pull requests for both phases
9. **State Validation** - Comprehensive backend connectivity testing for all state files
10. **Error Handling** - Improved failure detection and reporting with phase-specific error context

### Workflow Changes

- **NEW**: `manage-backend-bucket.yml`: Reusable workflow for automatic backend provisioning with enhanced bucket management and two-phase support
- **NEW**: `deploy-infrastructure.yml`: Phase 1 deployment workflow with infrastructure-specific state management
- **NEW**: `deploy-coder.yml`: Phase 2 deployment workflow with remote state data source integration
- `deploy-environment.yml`: Orchestrates both phases with integrated backend auto-provisioning
- `teardown-environment.yml`: Enhanced with two-phase teardown (Coder first, then infrastructure) and plan-before-destroy
- `validate-templates.yml`: Updated with backend auto-provisioning for comprehensive tests across both phases

### Auto-Provisioning Benefits

- **Zero Manual Setup**: Backend infrastructure is created automatically for both phases
- **Idempotent Operations**: Safe to run multiple times without side effects
- **Environment Isolation**: Each environment gets its own backend configuration with separate phase state files
- **Phase Isolation**: Infrastructure and Coder application states are completely separate
- **Better Troubleshooting**: Phase-specific state files enable targeted debugging
- **Independent Recovery**: Coder phase failures don't affect infrastructure state
- **Error Recovery**: Robust validation and error handling with phase-specific context

## Security Considerations

### Access Control

- Environment-specific buckets prevent cross-contamination
- Bucket policies restrict access to project resources
- Versioning enabled for state history and rollback

### State Locking Limitation

⚠️ **Important**: Scaleway Object Storage does not support DynamoDB-style state locking.

**Mitigation Strategies:**

- Use GitHub Actions for centralized deployments
- Coordinate team access through CI/CD pipelines
- Implement process-based coordination for manual operations

## Cost Analysis

### Storage Costs

Based on Scaleway Object Storage pricing:

- Storage: €0.01 per GB/month
- Requests: €0.01 per 1,000 requests

**Estimated Monthly Costs:**

- State files (< 1MB each): ~€0.01
- API requests (typical usage): ~€0.05
- **Total per environment: < €0.10/month**

### Benefits vs. Costs

The minimal cost (< €0.30/month for all environments) provides:

- Team collaboration capabilities
- State versioning and history
- Centralized deployment coordination
- Disaster recovery capabilities

## Troubleshooting

### Common Issues

**Backend Initialization Failures**

#### Legacy Single-Phase Environments

```bash
# Check credentials
scw config info

# Verify bucket exists
scw object bucket list

# Re-initialize backend
cd environments/dev && terraform init -reconfigure
```

#### Two-Phase Environments

```bash
# Check credentials
scw config info

# Verify bucket exists for the environment
scw object bucket list | grep terraform-state-coder-dev

# Re-initialize infrastructure phase
cd environments/dev/infra && terraform init -reconfigure

# Re-initialize Coder phase (includes remote state data source)
cd environments/dev/coder && terraform init -reconfigure

# Verify remote state connectivity for Coder phase
cd environments/dev/coder && terraform plan -refresh-only
```

**Authentication Errors with S3 Backend**

```bash
# Error: "no valid credential sources for S3 Backend found"
# Solution: Set AWS environment variables
export AWS_ACCESS_KEY_ID="$SCW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SCW_SECRET_KEY"

# Verify credentials are set
env | grep AWS_
```

**State Migration Issues**

#### Legacy Environment Migration

```bash
# Check migration prerequisites
./scripts/utils/migrate-state.sh --env=dev --dry-run

# Review migration logs
cat backups/state-migration/migration-*.log
```

#### Two-Phase Environment Migration

```bash
# Check prerequisites for both phases
./scripts/utils/migrate-state.sh --env=dev --two-phase --dry-run

# Check individual phase prerequisites
./scripts/utils/migrate-state.sh --env=dev --phase=infra --dry-run
./scripts/utils/migrate-state.sh --env=dev --phase=coder --dry-run

# Review phase-specific migration logs
cat backups/state-migration/migration-infra-*.log
cat backups/state-migration/migration-coder-*.log
```

**State Access Problems**

#### Legacy Environments

```bash
# Test state connectivity
./scripts/utils/state-manager.sh show --env=dev

# Check backend configuration
cd environments/dev && terraform init -backend=false && terraform validate
```

#### Two-Phase Environments

```bash
# Test state connectivity for both phases
./scripts/utils/state-manager.sh show --env=dev --two-phase

# Test individual phase connectivity
./scripts/utils/state-manager.sh show --env=dev --phase=infra
./scripts/utils/state-manager.sh show --env=dev --phase=coder

# Check backend configuration for each phase
cd environments/dev/infra && terraform init -backend=false && terraform validate
cd environments/dev/coder && terraform init -backend=false && terraform validate

# Test remote state data source connectivity (Phase 2)
cd environments/dev/coder && terraform refresh
```

### Recovery Procedures

**Rollback to Local State**

#### Legacy Environments

```bash
# Copy from migration backup
cd environments/dev
cp ../../backups/state-migration/dev/terraform.tfstate ./

# Remove backend configuration temporarily
mv providers.tf providers.tf.backup

# Reinitialize with local backend
terraform init
```

#### Two-Phase Environments

```bash
# Rollback infrastructure phase
cd environments/dev/infra
cp ../../../backups/state-migration/dev-infra/terraform.tfstate ./
mv providers.tf providers.tf.backup
terraform init

# Rollback Coder phase
cd environments/dev/coder
cp ../../../backups/state-migration/dev-coder/terraform.tfstate ./
mv providers.tf providers.tf.backup
terraform init

# Note: Remote state data source will need to be removed temporarily
# Edit main.tf to comment out the data "terraform_remote_state" "infra" block
```

**State Corruption Recovery**

#### Legacy Environments

```bash
# Restore from backup
./scripts/utils/state-manager.sh restore --env=dev --backup=<backup-name>

# Or use Object Storage versioning
# (manual process through Scaleway console)
```

#### Two-Phase Environments

```bash
# Restore specific phase from backup
./scripts/utils/state-manager.sh restore --env=dev --phase=infra --backup=<infra-backup-name>
./scripts/utils/state-manager.sh restore --env=dev --phase=coder --backup=<coder-backup-name>

# Restore both phases
./scripts/utils/state-manager.sh restore --env=dev --two-phase --backup=<backup-timestamp>

# Or use Object Storage versioning for specific state files
# Navigate to: s3://terraform-state-coder-dev/infra/terraform.tfstate
# Navigate to: s3://terraform-state-coder-dev/coder/terraform.tfstate
```

## Migration Checklist

### Pre-Migration

- [ ] Verify Scaleway credentials are configured
- [ ] Ensure all team members have access to Scaleway project
- [ ] Create backup of current local state files
- [ ] **Identify environment structure**: Legacy (single main.tf) vs Two-Phase (infra/ + coder/)
- [ ] Test backend setup script in development environment
- [ ] **For Two-Phase**: Verify remote state data source configuration in Coder phase

### Migration Process

#### Legacy Single-Phase Migration

- [ ] Run `setup-backend.sh` to create Object Storage infrastructure
- [ ] Perform dry-run migration to preview changes
- [ ] Execute actual migration during maintenance window
- [ ] Verify remote state accessibility
- [ ] Test normal terraform operations

#### Two-Phase Environment Migration

- [ ] Run `setup-backend.sh` to create Object Storage infrastructure with two-phase support
- [ ] **Phase 1 (Infrastructure)**:
  - [ ] Perform dry-run migration: `migrate-state.sh --env=dev --phase=infra --dry-run`
  - [ ] Execute infrastructure migration: `migrate-state.sh --env=dev --phase=infra`
  - [ ] Verify infrastructure state accessibility
  - [ ] Test infrastructure terraform operations
- [ ] **Phase 2 (Coder Application)**:
  - [ ] Perform dry-run migration: `migrate-state.sh --env=dev --phase=coder --dry-run`
  - [ ] Execute Coder migration: `migrate-state.sh --env=dev --phase=coder`
  - [ ] Verify Coder state accessibility
  - [ ] **Test remote state data source**: Verify Coder phase can read infrastructure outputs
  - [ ] Test Coder terraform operations

### Post-Migration

- [ ] Update team documentation with new procedures
- [ ] Configure GitHub Actions secrets for remote state access
- [ ] **Test Two-Phase CI/CD pipelines**: Verify both infrastructure and Coder workflows
- [ ] Remove local state files after verification (both phases for two-phase environments)
- [ ] Train team on new state management tools and two-phase architecture
- [ ] **Document phase dependencies**: Ensure team understands infrastructure → Coder dependency

## Best Practices

### Development Workflow

1. **Always use remote state** for team environments (both phases in two-phase setups)
2. **Create backups** before major infrastructure changes (phase-specific or comprehensive)
3. **Use GitHub Actions** for production deployments (leverages two-phase workflows)
4. **Monitor for drift** regularly using state manager (check both phases)
5. **Keep local state** only for temporary/experimental work
6. **Understand phase dependencies**: Infrastructure phase must be deployed before Coder phase
7. **Use appropriate workflows**: Complete deployment vs phase-specific deployments

### Team Coordination

1. **Centralize deployments** through CI/CD pipelines (two-phase workflows provide better reliability)
2. **Use PR reviews** for infrastructure changes (both phases)
3. **Document state changes** in commit messages (specify which phase)
4. **Coordinate manual operations** to avoid conflicts (especially important with two phases)
5. **Leverage kubeconfig artifacts**: Use immediate cluster access from infrastructure phase for troubleshooting

### Monitoring and Maintenance

1. **Regular backup schedule** for critical environments
   - Legacy: Environment-level backups
   - Two-Phase: Phase-specific backups or comprehensive backups
2. **Monthly drift detection** across all environments and phases
3. **Cost monitoring** for Object Storage usage (multiple state files per environment)
4. **Access review** for state bucket permissions
5. **Phase-specific monitoring**: Track infrastructure vs application state separately
6. **Remote state data source validation**: Ensure Phase 2 can always read Phase 1 outputs

## Support and Resources

### Documentation

- [Terraform Backend Module README](../modules/terraform-backend/README.md)
- [State Manager Script Help](../scripts/utils/state-manager.sh --help) - Now supports two-phase operations
- [Migration Script Help](../scripts/utils/migrate-state.sh --help) - Enhanced with phase-specific migration
- [Two-Phase Architecture Guide](ARCHITECTURE.md#two-phase-deployment-strategy)
- [GitHub Actions Workflows Guide](WORKFLOWS.md) - Complete two-phase workflow documentation

### Scaleway Resources

- [Object Storage Documentation](https://www.scaleway.com/en/docs/object-storage/)
- [S3 API Compatibility](https://www.scaleway.com/en/docs/object-storage/api-cli/object-storage-aws-cli/)
- [Terraform Provider](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs)

## Two-Phase Architecture Benefits

### State Management Advantages

1. **Improved Reliability**: Infrastructure state isolated from application state
2. **Better Troubleshooting**: Phase-specific state files enable targeted debugging
3. **Independent Recovery**: Coder deployment failures don't affect infrastructure state
4. **Cleaner Dependencies**: Clear separation between infrastructure and application concerns
5. **Enhanced CI/CD**: Better workflow orchestration with phase-specific deployments

### Operational Benefits

1. **Selective Operations**: Backup, restore, or modify individual phases
2. **Reduced Blast Radius**: Changes to one phase don't affect the other
3. **Parallel Development**: Teams can work on infrastructure and application independently
4. **Progressive Deployment**: Deploy infrastructure first, validate, then deploy application
5. **Better Cost Management**: Track state storage costs per phase

### Migration Path

The system supports both architectures:

- **Legacy Environments**: Continue working with single state files
- **New Environments**: Automatically use two-phase architecture
- **Gradual Migration**: Convert legacy environments to two-phase as needed

---

This implementation provides enterprise-grade state management with **two-phase deployment architecture** while maintaining backward compatibility and providing comprehensive migration tools for safe transition from local to remote state storage.
