variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "environments_dir" {
  description = "Path to the environments directory for backend config generation"
  type        = string
  default     = "../environments"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for Terraform state storage"
  type        = string
  default     = ""
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
  description = "Scaleway project ID - defaults to SCW_DEFAULT_PROJECT_ID environment variable"
  type        = string
  default     = ""
}

variable "state_retention_days" {
  description = "Number of days to retain non-current state versions"
  type        = number
  default     = 90
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

variable "managed_by" {
  description = "Who is managing this backend (terraform, github-actions, etc)"
  type        = string
  default     = "terraform"
}

variable "enable_bucket_policy" {
  description = "Whether to create a bucket policy (disabled by default due to Scaleway compatibility issues)"
  type        = bool
  default     = false
}

locals {
  # Use provided bucket name or generate based on environment
  actual_bucket_name = var.bucket_name != "" ? var.bucket_name : "terraform-state-coder-${var.environment}"

  # Use provided project_id or fall back to environment variable via TF_VAR_project_id
  # Note: When project_id variable is empty, Terraform will use TF_VAR_project_id env var
  actual_project_id = var.project_id
}