variable "bucket_name" {
  description = "Name of the S3 bucket for Terraform state storage"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name)) && length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63
    error_message = "Bucket name must be 3-63 characters long, start and end with alphanumeric characters, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "Scaleway region for the Object Storage bucket"
  type        = string
  default     = "fr-par"

  validation {
    condition     = contains(["fr-par", "nl-ams", "pl-waw"], var.region)
    error_message = "Region must be one of: fr-par, nl-ams, pl-waw."
  }
}

variable "project_id" {
  description = "Scaleway project ID for bucket access control"
  type        = string
}

variable "state_retention_days" {
  description = "Number of days to retain non-current state versions"
  type        = number
  default     = 90

  validation {
    condition     = var.state_retention_days >= 7 && var.state_retention_days <= 365
    error_message = "State retention days must be between 7 and 365."
  }
}

variable "generate_backend_config" {
  description = "Whether to generate backend configuration files"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to the bucket"
  type        = map(string)
  default     = {}
}