output "database_secret_id" {
  description = "ID of the database credentials secret"
  value       = scaleway_secret.database_credentials.id
}

output "database_secret_name" {
  description = "Name of the database credentials secret"
  value       = scaleway_secret.database_credentials.name
}

output "admin_secret_id" {
  description = "ID of the admin credentials secret"
  value       = scaleway_secret.coder_admin_credentials.id
}

output "admin_secret_name" {
  description = "Name of the admin credentials secret"
  value       = scaleway_secret.coder_admin_credentials.name
}

output "oauth_github_secret_id" {
  description = "ID of the GitHub OAuth secret"
  value       = var.oauth_github_client_id != "" ? scaleway_secret.oauth_github[0].id : null
}

output "oauth_github_secret_name" {
  description = "Name of the GitHub OAuth secret"
  value       = var.oauth_github_client_id != "" ? scaleway_secret.oauth_github[0].name : null
}

output "oauth_google_secret_id" {
  description = "ID of the Google OAuth secret"
  value       = var.oauth_google_client_id != "" ? scaleway_secret.oauth_google[0].id : null
}

output "oauth_google_secret_name" {
  description = "Name of the Google OAuth secret"
  value       = var.oauth_google_client_id != "" ? scaleway_secret.oauth_google[0].name : null
}

output "application_secret_ids" {
  description = "IDs of additional application secrets"
  value       = { for k, v in scaleway_secret.application_secrets : k => v.id }
}

output "application_secret_names" {
  description = "Names of additional application secrets"
  value       = { for k, v in scaleway_secret.application_secrets : k => v.name }
}

# For debugging and verification (non-sensitive values only)
output "secrets_summary" {
  description = "Summary of created secrets"
  value = {
    database_secret  = scaleway_secret.database_credentials.name
    admin_secret     = scaleway_secret.coder_admin_credentials.name
    oauth_github     = var.oauth_github_client_id != "" ? scaleway_secret.oauth_github[0].name : "not_configured"
    oauth_google     = var.oauth_google_client_id != "" ? scaleway_secret.oauth_google[0].name : "not_configured"
    additional_count = length(var.additional_secrets)
  }
}