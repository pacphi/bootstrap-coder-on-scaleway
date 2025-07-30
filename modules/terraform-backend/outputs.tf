output "bucket_name" {
  description = "Name of the Terraform state bucket"
  value       = local.bucket_name
}

output "bucket_endpoint" {
  description = "S3-compatible endpoint URL for the bucket"
  value       = var.create_bucket ? scaleway_object_bucket.terraform_state[0].endpoint : data.scaleway_object_bucket.existing_terraform_state[0].endpoint
}

output "bucket_region" {
  description = "Region where the bucket is located"
  value       = local.bucket_region
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
  value       = "https://s3.${local.bucket_region}.scw.cloud"
}

output "bucket_arn" {
  description = "ARN of the bucket"
  value       = "arn:scw:s3:::${local.bucket_name}"
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket"
  value       = true
}

output "backend_tf_content" {
  description = "Rendered backend.tf content for the environment"
  value = templatefile("${path.module}/templates/backend.tf.tpl", {
    bucket_name = local.bucket_name
    state_key   = local.backend_config.key
    region      = local.bucket_region
    endpoint    = local.backend_config.endpoints.s3
  })
}
