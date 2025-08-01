# Coder deployment outputs
output "coder_url" {
  description = "URL to access Coder"
  value       = data.terraform_remote_state.infra.outputs.access_url
}

output "access_url" {
  description = "Access URL for Coder (alias for coder_url)"
  value       = data.terraform_remote_state.infra.outputs.access_url
}

output "wildcard_access_url" {
  description = "Wildcard access URL for Coder workspaces"
  value       = data.terraform_remote_state.infra.outputs.wildcard_access_url
}

output "admin_username" {
  description = "Admin username for Coder"
  value       = module.coder_deployment.admin_username
}

output "admin_password" {
  description = "Admin password for Coder"
  value       = module.coder_deployment.admin_password
  sensitive   = true
}

output "namespace" {
  description = "Kubernetes namespace where Coder is deployed"
  value       = module.coder_deployment.namespace
}

output "service_name" {
  description = "Kubernetes service name for Coder"
  value       = module.coder_deployment.service_name
}

output "persistent_volume_claim_name" {
  description = "Name of the persistent volume claim for Coder data"
  value       = module.coder_deployment.pvc_name
}

# Environment information
output "environment" {
  description = "Environment name"
  value       = "dev"
}

output "project_name" {
  description = "Project name"
  value       = "coder"
}