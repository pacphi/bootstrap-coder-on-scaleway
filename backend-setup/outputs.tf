# Pass through all module outputs for flexibility

output "bucket_name" {
  description = "Name of the created Terraform state bucket"
  value       = module.terraform_backend.bucket_name
}

output "bucket_endpoint" {
  description = "S3-compatible endpoint URL for the bucket"
  value       = module.terraform_backend.bucket_endpoint
}

output "bucket_region" {
  description = "Region where the bucket is located"
  value       = module.terraform_backend.bucket_region
}

output "state_key" {
  description = "Key path for the Terraform state file"
  value       = module.terraform_backend.state_key
}

output "backend_config" {
  description = "Complete backend configuration for Terraform"
  value       = module.terraform_backend.backend_config
  sensitive   = false
}

output "s3_endpoint" {
  description = "S3-compatible endpoint URL for Terraform backend configuration"
  value       = module.terraform_backend.s3_endpoint
}

output "bucket_arn" {
  description = "ARN of the created bucket"
  value       = module.terraform_backend.bucket_arn
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket"
  value       = module.terraform_backend.versioning_enabled
}

output "backend_tf_content" {
  description = "Rendered backend.tf content from the module"
  value       = module.terraform_backend.backend_tf_content
}

