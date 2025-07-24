# Remote State Management with Scaleway Object Storage

This document provides a comprehensive guide for implementing remote Terraform state storage using Scaleway Object Storage in the Coder platform deployment project.

## Overview

The implementation adds enterprise-grade remote state management capabilities to address the lack of centralized state storage and concurrent access issues identified in the GitHub Actions workflows.

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

### State Storage Structure

```
Scaleway Object Storage Buckets:
├── terraform-state-coder-dev/
│   └── dev/terraform.tfstate
├── terraform-state-coder-staging/
│   └── staging/terraform.tfstate
└── terraform-state-coder-prod/
    └── prod/terraform.tfstate
```

### Backend Configuration

Each environment gets a `backend.tf` file:

```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state-coder-dev"
    key    = "dev/terraform.tfstate"
    region = "fr-par"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

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

### 2. Automatic Backend Provisioning (Recommended)

**The remote state backend is now automatically provisioned during GitHub Actions workflows.**

When you run any deployment workflow (deploy-environment.yml, teardown-environment.yml, or validate-templates.yml), the system will:

1. **Check if backend infrastructure exists** for the target environment
2. **Automatically create backend infrastructure** if it doesn't exist
3. **Generate backend.tf configuration** files
4. **Validate backend connectivity** before proceeding with deployment

**No manual setup is required for normal CI/CD operations.**

### 3. Manual Backend Creation (Optional)

For local development or troubleshooting:

```bash
# Setup backend for all environments
./scripts/utils/setup-backend.sh --env=all

# Or setup individual environments
./scripts/utils/setup-backend.sh --env=dev
./scripts/utils/setup-backend.sh --env=staging
./scripts/utils/setup-backend.sh --env=prod
```

### 3. Migrate Existing State

For environments with existing local state:

```bash
# Preview migration (recommended first step)
./scripts/utils/migrate-state.sh --env=dev --dry-run

# Perform actual migration
./scripts/utils/migrate-state.sh --env=dev --verbose
```

### 4. Verify Remote State

```bash
# Check state connectivity
./scripts/utils/state-manager.sh show --env=dev

# List resources
./scripts/utils/state-manager.sh list --env=dev
```

## State Management Operations

### Daily Operations

```bash
# Check state summary
./scripts/utils/state-manager.sh show --env=prod

# Create backup before major changes
./scripts/utils/state-manager.sh backup --env=prod

# Check for configuration drift
./scripts/utils/state-manager.sh drift --env=prod

# Inspect state details
./scripts/utils/state-manager.sh inspect --env=prod --format=json
```

### Backup Management

```bash
# Create manual backup
./scripts/utils/state-manager.sh backup --env=staging

# List available backups
ls backups/state-backups/

# Restore from backup (if needed)
./scripts/utils/state-manager.sh restore --env=staging --backup=staging-20240723-143022
```

## GitHub Actions Integration

### Auto-Provisioning Workflow Features

1. **Backend Setup Phase** - Automatically provisions backend infrastructure before deployment
2. **Bucket Existence Checking** - Validates backend infrastructure exists or creates it
3. **Dynamic Configuration** - Generates backend.tf files during workflow execution
4. **Plan Phase** - Generates and uploads Terraform plans using remote state
5. **Apply Phase** - Uses pre-generated plans for consistent deployments
6. **PR Comments** - Automatic plan summaries on pull requests
7. **State Validation** - Comprehensive backend connectivity testing
8. **Error Handling** - Improved failure detection and reporting

### Workflow Changes

- **NEW**: `setup-backend.yml`: Reusable workflow for automatic backend provisioning
- `deploy-environment.yml`: Integrated with backend auto-provisioning
- `teardown-environment.yml`: Enhanced with backend auto-provisioning and plan-before-destroy
- `validate-templates.yml`: Updated with backend auto-provisioning for comprehensive tests

### Auto-Provisioning Benefits

- **Zero Manual Setup**: Backend infrastructure is created automatically
- **Idempotent Operations**: Safe to run multiple times without side effects
- **Environment Isolation**: Each environment gets its own backend configuration
- **Error Recovery**: Robust validation and error handling

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
```bash
# Check credentials
scw config info

# Verify bucket exists
scw object bucket list

# Re-initialize backend
cd environments/dev && terraform init -reconfigure
```

**State Migration Issues**
```bash
# Check migration prerequisites
./scripts/utils/migrate-state.sh --env=dev --dry-run

# Review migration logs
cat backups/state-migration/migration-*.log
```

**State Access Problems**
```bash
# Test state connectivity
./scripts/utils/state-manager.sh show --env=dev

# Check backend configuration
cd environments/dev && terraform init -backend=false && terraform validate
```

### Recovery Procedures

**Rollback to Local State**
```bash
# Copy from migration backup
cd environments/dev
cp ../../backups/state-migration/dev/terraform.tfstate ./

# Remove backend configuration temporarily
mv backend.tf backend.tf.backup

# Reinitialize with local backend
terraform init
```

**State Corruption Recovery**
```bash
# Restore from backup
./scripts/utils/state-manager.sh restore --env=dev --backup=<backup-name>

# Or use Object Storage versioning
# (manual process through Scaleway console)
```

## Migration Checklist

### Pre-Migration

- [ ] Verify Scaleway credentials are configured
- [ ] Ensure all team members have access to Scaleway project
- [ ] Create backup of current local state files
- [ ] Test backend setup script in development environment

### Migration Process

- [ ] Run `setup-backend.sh` to create Object Storage infrastructure
- [ ] Perform dry-run migration to preview changes
- [ ] Execute actual migration during maintenance window
- [ ] Verify remote state accessibility
- [ ] Test normal terraform operations

### Post-Migration

- [ ] Update team documentation with new procedures
- [ ] Configure GitHub Actions secrets for remote state access
- [ ] Test CI/CD pipelines with remote state
- [ ] Remove local state files after verification
- [ ] Train team on new state management tools

## Best Practices

### Development Workflow

1. **Always use remote state** for team environments
2. **Create backups** before major infrastructure changes
3. **Use GitHub Actions** for production deployments
4. **Monitor for drift** regularly using state manager
5. **Keep local state** only for temporary/experimental work

### Team Coordination

1. **Centralize deployments** through CI/CD pipelines
2. **Use PR reviews** for infrastructure changes
3. **Document state changes** in commit messages
4. **Coordinate manual operations** to avoid conflicts

### Monitoring and Maintenance

1. **Regular backup schedule** for critical environments
2. **Monthly drift detection** across all environments
3. **Cost monitoring** for Object Storage usage
4. **Access review** for state bucket permissions

## Support and Resources

### Documentation

- [Terraform Backend Module README](../modules/terraform-backend/README.md)
- [State Manager Script Help](../scripts/utils/state-manager.sh --help)
- [Migration Script Help](../scripts/utils/migrate-state.sh --help)

### Scaleway Resources

- [Object Storage Documentation](https://www.scaleway.com/en/docs/object-storage/)
- [S3 API Compatibility](https://www.scaleway.com/en/docs/object-storage/api-cli/object-storage-aws-cli/)
- [Terraform Provider](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs)

---

This implementation provides enterprise-grade state management while maintaining backward compatibility and providing comprehensive migration tools for safe transition from local to remote state storage.