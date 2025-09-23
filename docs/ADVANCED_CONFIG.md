# Advanced Configuration Schema

## Overview

Due to GitHub Actions' 10-input limitation for `workflow_dispatch` events, advanced configuration options are provided through a JSON configuration parameter. This allows access to all security, secret management, and cost optimization features.

## Usage

When manually triggering the "Deploy Complete Coder Environment" workflow, use the `advanced_config` input field with a JSON configuration following the schema below.

## Schema

### Complete Configuration Example

```json
{
  "monitoring": {
    "enabled": true,
    "stack": "prometheus"
  },
  "security": {
    "management_cidr": "203.0.113.0/24",
    "trusted_cidr": "198.51.100.0/24",
    "vpc_cidr": "10.0.0.0/8",
    "pod_security_standard": "restricted",
    "enable_pod_security_standards": true,
    "enable_network_policies": true,
    "allow_public_api": false,
    "allow_public_ssh": false
  },
  "secrets": {
    "use_external_secrets": true,
    "external_secrets_config": {
      "database_secret_name": "coder-database-credentials",
      "admin_secret_name": "coder-admin-credentials",
      "github_secret_name": "coder-github-oauth",
      "google_secret_name": "coder-google-oauth"
    }
  },
  "cost_optimization": {
    "enabled": true,
    "volume_type": "bssd",
    "environment_tier": "staging"
  },
  "coder": {
    "use_external_secrets": true,
    "replica_count": 2,
    "resources": {
      "limits": {
        "cpu": "2000m",
        "memory": "4Gi"
      },
      "requests": {
        "cpu": "500m",
        "memory": "1Gi"
      }
    }
  }
}
```

### Minimal Configuration Examples

**Development Environment (Cost-Optimized)**:
```json
{
  "cost_optimization": {
    "enabled": true,
    "volume_type": "sbv",
    "environment_tier": "dev"
  },
  "security": {
    "pod_security_standard": "baseline"
  }
}
```

**Production Environment (Security-Hardened)**:

```json
{
  "security": {
    "management_cidr": "203.0.113.0/24",
    "trusted_cidr": "198.51.100.0/24",
    "pod_security_standard": "restricted",
    "allow_public_api": false,
    "allow_public_ssh": false
  },
  "secrets": {
    "use_external_secrets": true
  },
  "monitoring": {
    "enabled": true
  }
}
```

**External Secrets Only**:

```json
{
  "secrets": {
    "use_external_secrets": true,
    "external_secrets_config": {
      "database_secret_name": "my-database-secret",
      "admin_secret_name": "my-admin-secret"
    }
  }
}
```

## Configuration Sections

### 1. Monitoring Configuration

Enhanced monitoring capabilities

```json
{
  "monitoring": {
    "enabled": true,         // Enable monitoring stack (default: false)
    "stack": "prometheus"    // Monitoring stack type (default: prometheus)
  }
}
```

### 2. Security Configuration

Network security, RBAC, Pod Security Standards

```json
{
  "security": {
    "management_cidr": "203.0.113.0/24",        // CIDR for management access (SSH, monitoring)
    "trusted_cidr": "198.51.100.0/24",          // CIDR for trusted access (K8s API, admin)
    "vpc_cidr": "10.0.0.0/8",                   // VPC CIDR range (default: 10.0.0.0/8)
    "pod_security_standard": "restricted",       // Pod Security Standard: baseline|restricted
    "enable_pod_security_standards": true,       // Enable Pod Security Standards (default: true)
    "enable_network_policies": true,             // Enable Network Policies (default: true)
    "allow_public_api": false,                   // Allow public K8s API access (default: true)
    "allow_public_ssh": false                    // Allow public SSH access (default: true)
  }
}
```

**Security Levels**:

- **`baseline`**: Basic security with some restrictions
- **`restricted`**: Strict security with comprehensive restrictions (recommended for production)

**CIDR Configuration**:

- **`management_cidr`**: IP ranges allowed for SSH and monitoring access
- **`trusted_cidr`**: IP ranges allowed for Kubernetes API and admin interfaces
- **`vpc_cidr`**: Internal VPC communication range

### 3. Secret Management Configuration

External Secrets Operator integration

```json
{
  "secrets": {
    "use_external_secrets": true,                // Use External Secrets Operator (default: false)
    "external_secrets_config": {
      "database_secret_name": "coder-db-creds", // Scaleway Secret Manager secret name for DB
      "admin_secret_name": "coder-admin-creds", // Secret name for admin credentials
      "github_secret_name": "coder-github-oauth", // Optional: GitHub OAuth secret
      "google_secret_name": "coder-google-oauth"  // Optional: Google OAuth secret
    }
  }
}
```

**Secret Types**:

- **Database**: PostgreSQL connection credentials
- **Admin**: Coder admin user credentials
- **OAuth**: GitHub/Google OAuth application credentials (optional)

### 4. Cost Optimization Configuration

Environment-tiered cost optimization

```json
{
  "cost_optimization": {
    "enabled": true,              // Enable cost optimization (default: false)
    "volume_type": "bssd",        // Storage type: lssd|bssd|sbv
    "environment_tier": "staging" // Environment tier: dev|staging|prod
  }
}
```

**Volume Types**:

- **`lssd`**: High-performance SSD (fastest, most expensive)
- **`bssd`**: Balanced SSD (good performance, moderate cost)
- **`sbv`**: Cost-optimized storage (slowest, cheapest)

**Environment Tiers**:

- **`dev`**: Minimal resources, cost-optimized defaults
- **`staging`**: Production-like but reduced resources
- **`prod`**: Full resources, performance optimized

### 5. Coder Application Configuration

Enhanced Coder deployment options

```json
{
  "coder": {
    "replica_count": 2,           // Number of Coder replicas (default: 1)
    "use_external_secrets": true, // Use External Secrets for Coder (inherits from secrets.use_external_secrets)
    "resources": {
      "limits": {
        "cpu": "2000m",           // CPU limit (default: 2000m)
        "memory": "4Gi"           // Memory limit (default: 4Gi)
      },
      "requests": {
        "cpu": "500m",            // CPU request (default: 500m)
        "memory": "1Gi"           // Memory request (default: 1Gi)
      }
    },
    "storage": {
      "class": "scw-bssd",        // Storage class (default: scw-bssd)
      "size": "20Gi"              // Storage size (default: 10Gi)
    }
  }
}
```

## Environment-Specific Defaults

### Development Environment

When no advanced configuration is provided for `dev` environment:

```json
{
  "cost_optimization": {
    "enabled": true,
    "volume_type": "sbv",
    "environment_tier": "dev"
  },
  "security": {
    "pod_security_standard": "baseline",
    "allow_public_api": true,
    "allow_public_ssh": true
  },
  "monitoring": {
    "enabled": false
  }
}
```

### Staging Environment

When no advanced configuration is provided for `staging` environment:

```json
{
  "cost_optimization": {
    "enabled": true,
    "volume_type": "bssd",
    "environment_tier": "staging"
  },
  "security": {
    "pod_security_standard": "restricted",
    "allow_public_api": true,
    "allow_public_ssh": false
  },
  "monitoring": {
    "enabled": true
  }
}
```

### Production Environment

When no advanced configuration is provided for `prod` environment:

```json
{
  "security": {
    "pod_security_standard": "restricted",
    "enable_pod_security_standards": true,
    "enable_network_policies": true,
    "allow_public_api": false,
    "allow_public_ssh": false
  },
  "secrets": {
    "use_external_secrets": true
  },
  "monitoring": {
    "enabled": true
  }
}
```

## Validation

The workflow automatically validates the provided JSON configuration:

1. **JSON Syntax**: Must be valid JSON
2. **Schema Validation**: Values must match expected types and constraints
3. **Security Validation**: Security-sensitive options are verified
4. **Environment Compatibility**: Configuration is checked against environment requirements

## Examples by Use Case

### Scenario 1: Secure Production Deployment

```json
{
  "security": {
    "management_cidr": "203.0.113.0/24",
    "trusted_cidr": "198.51.100.0/24",
    "pod_security_standard": "restricted",
    "allow_public_api": false,
    "allow_public_ssh": false
  },
  "secrets": {
    "use_external_secrets": true,
    "external_secrets_config": {
      "database_secret_name": "prod-coder-database",
      "admin_secret_name": "prod-coder-admin"
    }
  },
  "monitoring": {
    "enabled": true
  }
}
```

### Scenario 2: Cost-Optimized Development

```json
{
  "cost_optimization": {
    "enabled": true,
    "volume_type": "sbv",
    "environment_tier": "dev"
  },
  "coder": {
    "resources": {
      "limits": {
        "cpu": "1000m",
        "memory": "2Gi"
      },
      "requests": {
        "cpu": "250m",
        "memory": "512Mi"
      }
    }
  }
}
```

### Scenario 3: External Secrets Migration

```json
{
  "secrets": {
    "use_external_secrets": true,
    "external_secrets_config": {
      "database_secret_name": "migrated-database-creds",
      "admin_secret_name": "migrated-admin-creds",
      "github_secret_name": "migrated-github-oauth"
    }
  }
}
```

## Troubleshooting

### Common Issues

1. **Invalid JSON**: Ensure JSON is properly formatted
2. **Unknown Properties**: Use only documented configuration keys
3. **Type Mismatches**: Ensure boolean values are `true`/`false`, not `"true"`/`"false"`
4. **CIDR Format**: Use proper CIDR notation (e.g., `192.168.1.0/24`)

### Validation Errors

The workflow will fail with clear error messages if:

- JSON syntax is invalid
- Required fields are missing when features are enabled
- Values don't match validation constraints
- Security configurations are incompatible with environment

### Getting Help

- Check workflow logs for detailed validation errors
- Refer to module documentation in `modules/*/variables.tf`
- Review feature documentation in `docs/FEATURES.md`
- Use minimal configurations and add features incrementally

## Migration from Previous Versions

If you were using individual workflow inputs before:

**Old Approach** (no longer works due to 10-input limit):

```yaml
enable_monitoring: true
```

**New Approach**:

```json
{
  "monitoring": {
    "enabled": true
  }
}
```

The workflow is backward compatible for basic deployments when no advanced configuration is provided.
