variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "Scaleway region"
  type        = string
}

variable "project_id" {
  description = "Scaleway project ID"
  type        = string
}

variable "organization_id" {
  description = "Scaleway organization ID"
  type        = string
}

# Database credentials
variable "database_username" {
  description = "Database username"
  type        = string
  default     = "coder"
}

variable "database_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "database_host" {
  description = "Database host"
  type        = string
}

variable "database_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "coder"
}

# Admin credentials
variable "admin_email" {
  description = "Admin user email"
  type        = string
}

# OAuth configurations
variable "oauth_github_client_id" {
  description = "GitHub OAuth client ID"
  type        = string
  default     = ""
}

variable "oauth_github_client_secret" {
  description = "GitHub OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oauth_google_client_id" {
  description = "Google OAuth client ID"
  type        = string
  default     = ""
}

variable "oauth_google_client_secret" {
  description = "Google OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

# Additional secrets
variable "additional_secrets" {
  description = "Additional application secrets to store"
  type = map(object({
    description = string
    data        = map(string)
    tags        = optional(map(string), {})
  }))
  default = {}
}