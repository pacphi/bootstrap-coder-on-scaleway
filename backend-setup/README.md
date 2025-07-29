# Terraform Backend Setup Configuration

This directory contains the shared Terraform configuration for setting up remote state backends using Scaleway Object Storage. It provides a consistent approach for both local script execution and GitHub Actions workflows.

## Overview

The configuration uses the `terraform-backend` module to:
- Create Scaleway Object Storage buckets for Terraform state
- Enable versioning for state history
- Configure lifecycle policies for state retention
- Generate backend.tf configurations for environments

## Usage

### From setup-backend.sh Script

The script automatically copies this configuration and provides environment-specific values:

```bash
./scripts/utils/setup-backend.sh --env=dev
```

### From GitHub Actions

The workflow uses this same configuration:

```yaml
- name: Setup Backend
  uses: ./.github/workflows/setup-backend.yml
  with:
    environment: dev
```

### Direct Terraform Usage

```bash
cd backend-setup
terraform init
terraform apply -var="environment=dev" -var="project_id=$SCW_DEFAULT_PROJECT_ID"
```

## Variables

- `environment` - Environment name (dev, staging, prod)
- `bucket_name` - Custom bucket name (optional, defaults to terraform-state-coder-{env})
- `region` - Scaleway region (default: fr-par)
- `project_id` - Scaleway project ID (uses env var if not provided)
- `state_retention_days` - Days to retain old state versions (default: 90)
- `generate_backend_config` - Whether module generates backend.tf files locally (default: false, we use output instead)
- `managed_by` - Identifier for who manages this backend (default: terraform)

## Outputs

- `bucket_name` - Created bucket name
- `bucket_endpoint` - S3-compatible endpoint URL
- `backend_config` - Complete backend configuration object
- `backend_tf_content` - Rendered backend.tf content from the terraform-backend module

## Environment Variables

The configuration automatically uses these environment variables:
- `SCW_DEFAULT_PROJECT_ID` - Used when project_id not explicitly provided
- Standard Scaleway authentication variables (SCW_ACCESS_KEY, SCW_SECRET_KEY)

### S3 Backend Authentication

When using the generated backend configuration, you must also set:
- `AWS_ACCESS_KEY_ID` - Set to your SCW_ACCESS_KEY value
- `AWS_SECRET_ACCESS_KEY` - Set to your SCW_SECRET_KEY value

The Terraform S3 backend specifically looks for these AWS-named variables.

## Troubleshooting

### Recreating a bucket with the same name as one that had existed previously

If you see

```
│ Error: operation error S3: CreateBucket, https response error StatusCode: 409, RequestID: txg092eddc974474cbd9542-00688904b1, HostID: txg092eddc974474cbd9542-00688904b1, BucketAlreadyOwnedByYou:
│
│   with module.terraform_backend.scaleway_object_bucket.terraform_state,
│   on ../modules/terraform-backend/main.tf line 11, in resource "scaleway_object_bucket" "terraform_state":
│   11: resource "scaleway_object_bucket" "terraform_state" {
```

Choose one of the following options to resolve:

a) Change the value of `bucket_name` in your .tfvars file
b) Wait 24 hours. See https://www.scaleway.com/en/docs/object-storage/faq/#can-i-create-a-bucket-with-the-same-name-as-a-previously-deleted-one.