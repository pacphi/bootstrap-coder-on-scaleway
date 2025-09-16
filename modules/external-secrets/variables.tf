variable "chart_version" {
  description = "Version of External Secrets Operator Helm chart"
  type        = string
  default     = "0.9.11"
}

variable "replica_count" {
  description = "Number of External Secrets Operator replicas"
  type        = number
  default     = 2
}

variable "resources" {
  description = "Resource limits and requests for External Secrets Operator"
  type = object({
    limits = object({
      cpu    = string
      memory = string
    })
    requests = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    limits = {
      cpu    = "100m"
      memory = "128Mi"
    }
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
  }
}

variable "monitoring_enabled" {
  description = "Enable monitoring for External Secrets Operator"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy for External Secrets Operator"
  type        = bool
  default     = true
}

variable "node_selector" {
  description = "Node selector for External Secrets Operator pods"
  type        = map(string)
  default     = {}
}

variable "tolerations" {
  description = "Tolerations for External Secrets Operator pods"
  type        = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))
  default = []
}

variable "affinity" {
  description = "Affinity rules for External Secrets Operator pods"
  type        = any
  default     = {}
}

# Scaleway configuration
variable "scaleway_region" {
  description = "Scaleway region"
  type        = string
}

variable "scaleway_project_id" {
  description = "Scaleway project ID"
  type        = string
}

variable "scaleway_access_key" {
  description = "Scaleway access key for External Secrets Operator"
  type        = string
  sensitive   = true
}

variable "scaleway_secret_key" {
  description = "Scaleway secret key for External Secrets Operator"
  type        = string
  sensitive   = true
}

variable "target_namespace" {
  description = "Target namespace for secrets and SecretStore"
  type        = string
  default     = "coder"
}

# Secret names from Scaleway Secret Manager
variable "database_secret_name" {
  description = "Name of the database secret in Scaleway Secret Manager"
  type        = string
}

variable "admin_secret_name" {
  description = "Name of the admin secret in Scaleway Secret Manager"
  type        = string
}

variable "oauth_github_secret_name" {
  description = "Name of the GitHub OAuth secret in Scaleway Secret Manager"
  type        = string
  default     = ""
}

variable "oauth_google_secret_name" {
  description = "Name of the Google OAuth secret in Scaleway Secret Manager"
  type        = string
  default     = ""
}

variable "additional_secret_mappings" {
  description = "Additional secret mappings for External Secrets"
  type = map(object({
    target_secret_name = string
    refresh_interval   = string
    labels            = map(string)
    template_data     = map(string)
    data_mappings = list(object({
      secretKey = string
      remoteRef = object({
        key      = string
        property = string
      })
    }))
  }))
  default = {}
}