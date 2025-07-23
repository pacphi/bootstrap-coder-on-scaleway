# Terraform Backend Module for Scaleway Object Storage

This module creates and configures Scaleway Object Storage buckets for storing Terraform state files remotely. It provides a secure, versioned storage solution with proper lifecycle management and access controls.

## Features

- **S3-Compatible Storage**: Uses Scaleway Object Storage with S3-compatible API
- **State Versioning**: Automatically versions state files for rollback capability
- **Lifecycle Management**: Configures retention policies for old state versions
- **Security**: Implements bucket policies for controlled access
- **Multi-Environment**: Supports separate buckets per environment
- **Backend Generation**: Automatically generates Terraform backend configuration files

## Usage

### Basic Usage

```hcl
module "terraform_backend" {
  source = "./modules/terraform-backend"

  bucket_name = "terraform-state-coder-dev"
  environment = "dev"
  project_id  = var.scaleway_project_id
  region      = "fr-par"
}
```

### With Custom Configuration

```hcl
module "terraform_backend" {
  source = "./modules/terraform-backend"

  bucket_name           = "terraform-state-coder-prod"
  environment          = "prod"
  project_id           = var.scaleway_project_id
  region               = "fr-par"
  state_retention_days = 180

  tags = {
    Team        = "Platform"
    CostCenter  = "Engineering"
    Environment = "production"
  }
}
```

## Backend Configuration

After creating the module, use the generated backend configuration in your environment:

```hcl
terraform {
  backend "s3" {
    bucket = "terraform-state-coder-dev"
    key    = "dev/terraform.tfstate"
    region = "fr-par"

    endpoint = "https://s3.fr-par.scw.cloud"

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }
  }
}
```

## Authentication

Ensure your Scaleway credentials are configured:

```bash
export SCW_ACCESS_KEY="your-access-key"
export SCW_SECRET_KEY="your-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"
```

Or using AWS CLI configuration (for S3 compatibility):

```bash
# ~/.aws/credentials
[default]
aws_access_key_id = <SCW_ACCESS_KEY>
aws_secret_access_key = <SCW_SECRET_KEY>
region = fr-par
```

## Migration from Local State

To migrate existing local state to the remote backend:

1. Create the backend infrastructure:
   ```bash
   terraform apply
   ```

2. Add the backend configuration to your main Terraform configuration

3. Initialize with the new backend:
   ```bash
   terraform init
   ```

4. Terraform will detect the existing state and offer to copy it to the remote backend

## Important Limitations

⚠️ **State Locking**: Scaleway Object Storage does not support DynamoDB-style state locking. For team environments:

- Implement coordination mechanisms to prevent concurrent applies
- Consider using CI/CD pipelines to serialize operations
- Use external locking solutions if needed

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket_name | Name of the S3 bucket for Terraform state storage | `string` | n/a | yes |
| environment | Environment name (dev, staging, prod) | `string` | n/a | yes |
| project_id | Scaleway project ID for bucket access control | `string` | n/a | yes |
| region | Scaleway region for the Object Storage bucket | `string` | `"fr-par"` | no |
| state_retention_days | Number of days to retain non-current state versions | `number` | `90` | no |
| generate_backend_config | Whether to generate backend configuration files | `bool` | `true` | no |
| tags | Additional tags to apply to the bucket | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Name of the created Terraform state bucket |
| bucket_endpoint | S3-compatible endpoint URL for the bucket |
| bucket_region | Region where the bucket is located |
| state_key | Key path for the Terraform state file |
| backend_config | Complete backend configuration for Terraform |
| s3_endpoint | S3-compatible endpoint URL for Terraform backend configuration |
| bucket_arn | ARN of the created bucket |
| versioning_enabled | Whether versioning is enabled on the bucket |

## Best Practices

1. **Separate Buckets**: Use separate buckets for each environment
2. **Descriptive Names**: Use clear, descriptive bucket names
3. **Retention Policies**: Configure appropriate retention for your needs
4. **Access Control**: Limit bucket access to necessary principals only
5. **Monitoring**: Monitor bucket access and costs
6. **Backup Strategy**: Consider additional backup strategies for critical environments

## Troubleshooting

### Common Issues

**Bucket Already Exists**: Bucket names must be globally unique across Scaleway
- Solution: Use more specific naming conventions

**Access Denied**: Check your Scaleway credentials and project permissions
- Solution: Verify SCW_ACCESS_KEY, SCW_SECRET_KEY, and project_id

**Region Mismatch**: Ensure the region matches your Scaleway configuration
- Solution: Use consistent regions across your configuration

### Debugging

Enable Terraform debug logging:
```bash
export TF_LOG=DEBUG
terraform init
```

Check Scaleway CLI access:
```bash
scw config info
scw object bucket list
```