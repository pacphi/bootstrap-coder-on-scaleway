terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
  }
}

# Data source to reference existing bucket (when not creating)
data "scaleway_object_bucket" "existing_terraform_state" {
  count  = var.create_bucket ? 0 : 1
  name   = var.bucket_name
  region = var.region
}

# Create Object Storage bucket for Terraform state (conditional)
resource "scaleway_object_bucket" "terraform_state" {
  count  = var.create_bucket ? 1 : 0
  name   = var.bucket_name
  region = var.region

  # Enable versioning for state history
  versioning {
    enabled = true
  }

  # CORS configuration for potential web-based access
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }

  # Lifecycle configuration to manage state versions
  lifecycle_rule {
    id      = "terraform_state_lifecycle"
    enabled = true

    # Keep current version forever, but limit non-current versions
    expiration {
      days = var.state_retention_days
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload_days = 1
  }

  tags = merge(var.tags, {
    Purpose     = "terraform-state"
    Environment = var.environment
    Project     = "coder-platform"
  })
}

# Local values for unified bucket reference
locals {
  bucket_name   = var.create_bucket ? scaleway_object_bucket.terraform_state[0].name : data.scaleway_object_bucket.existing_terraform_state[0].name
  bucket_region = var.create_bucket ? scaleway_object_bucket.terraform_state[0].region : data.scaleway_object_bucket.existing_terraform_state[0].region
}

# Create bucket policy for secure access (optional - disabled by default)
# Note: Scaleway Object Storage bucket policies have limited support
# Access control is typically handled via Scaleway IAM and API keys
resource "scaleway_object_bucket_policy" "terraform_state" {
  count  = var.enable_bucket_policy ? 1 : 0
  bucket = local.bucket_name
  region = var.region

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowTerraformStateAccess"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${var.bucket_name}",
          "${var.bucket_name}/*"
        ]
        Condition = {
          StringEquals = {
            "scw:project" = var.project_id
          }
        }
      }
    ]
  })
}

# Generate backend configuration for Terraform
locals {
  backend_config = {
    bucket = local.bucket_name
    key    = "${var.environment}/terraform.tfstate"
    region = local.bucket_region

    # S3-compatibility flags for Scaleway
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    # Use endpoints block for better compatibility
    endpoints = {
      s3 = "https://s3.${local.bucket_region}.scw.cloud"
    }
  }
}


# Create environment-specific backend configuration
resource "local_file" "backend_env_config" {
  count = var.generate_backend_config && var.environments_dir != "" ? 1 : 0

  # Use path.root (module caller's root) with relative path
  filename = "${path.root}/${var.environments_dir}/${var.environment}/backend.tf"
  content = templatefile("${path.module}/templates/backend.tf.tpl", {
    bucket_name = local.bucket_name
    state_key   = local.backend_config.key
    region      = local.bucket_region
    endpoint    = local.backend_config.endpoints.s3
  })

  file_permission = "0644"
}