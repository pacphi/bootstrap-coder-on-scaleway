output "bucket_name" {
  description = "Name of the created Terraform state bucket"
  value       = scaleway_object_bucket.terraform_state.name
}

output "bucket_endpoint" {
  description = "S3-compatible endpoint URL for the bucket"
  value       = scaleway_object_bucket.terraform_state.endpoint
}

output "bucket_region" {
  description = "Region where the bucket is located"
  value       = scaleway_object_bucket.terraform_state.region
}

output "state_key" {
  description = "Key path for the Terraform state file"
  value       = local.backend_config.key
}

output "backend_config" {
  description = "Complete backend configuration for Terraform"
  value       = local.backend_config
  sensitive   = false
}

output "s3_endpoint" {
  description = "S3-compatible endpoint URL for Terraform backend configuration"
  value       = "https://s3.${var.region}.scw.cloud"
}

output "bucket_arn" {
  description = "ARN of the created bucket"
  value       = "arn:scw:s3:::${scaleway_object_bucket.terraform_state.name}"
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket"
  value       = true
}