terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
  }
}

# Create Object Storage bucket for Terraform state
resource "scaleway_object_bucket" "terraform_state" {
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

# Create bucket policy for secure access (optional - disabled by default)
# Note: Scaleway Object Storage bucket policies have limited support
# Access control is typically handled via Scaleway IAM and API keys
resource "scaleway_object_bucket_policy" "terraform_state" {
  count  = var.enable_bucket_policy ? 1 : 0
  bucket = scaleway_object_bucket.terraform_state.name
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
    bucket = scaleway_object_bucket.terraform_state.name
    key    = "${var.environment}/terraform.tfstate"
    region = var.region

    # S3-compatibility flags for Scaleway
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true

    # Use endpoints block for better compatibility
    endpoints = {
      s3 = "https://s3.${var.region}.scw.cloud"
    }
  }
}


# Create environment-specific backend configuration
resource "local_file" "backend_env_config" {
  count = var.generate_backend_config && var.environments_dir != "" ? 1 : 0

  # Use path.root (module caller's root) with relative path
  filename = "${path.root}/${var.environments_dir}/${var.environment}/backend.tf"
  content = templatefile("${path.module}/templates/backend.tf.tpl", {
    bucket_name = scaleway_object_bucket.terraform_state.name
    state_key   = local.backend_config.key
    region      = var.region
    endpoint    = local.backend_config.endpoints.s3
  })

  file_permission = "0644"
}