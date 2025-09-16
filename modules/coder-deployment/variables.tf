variable "namespace" {
  description = "Kubernetes namespace for Coder deployment"
  type        = string
  default     = "coder"
}

variable "coder_version" {
  description = "Version of Coder to deploy"
  type        = string
  default     = "2.6.0"
}

variable "coder_image" {
  description = "Coder Docker image"
  type        = string
  default     = "ghcr.io/coder/coder"
}

variable "database_url" {
  description = "PostgreSQL database connection URL (only used when use_external_secrets = false)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "use_external_secrets" {
  description = "Use External Secrets Operator for secret management instead of direct Kubernetes secrets"
  type        = bool
  default     = false
}

variable "external_secrets_config" {
  description = "Configuration for External Secrets integration"
  type = object({
    database_secret_name = string
    admin_secret_name    = string
    github_secret_name   = optional(string, "")
    google_secret_name   = optional(string, "")
  })
  default = {
    database_secret_name = ""
    admin_secret_name    = ""
    github_secret_name   = ""
    google_secret_name   = ""
  }
}

variable "access_url" {
  description = "External URL for accessing Coder"
  type        = string
}

variable "wildcard_access_url" {
  description = "Wildcard URL for workspace access"
  type        = string
  default     = ""
}

variable "service_account_name" {
  description = "Service account name for Coder"
  type        = string
  default     = "coder"
}

# Resource Configuration
variable "resources" {
  description = "Resource limits and requests for Coder"
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
      cpu    = "2000m"
      memory = "4Gi"
    }
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
  }
}

variable "replica_count" {
  description = "Number of Coder replicas"
  type        = number
  default     = 1
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for persistent volumes"
  type        = string
  default     = "scw-bssd"
}

variable "storage_size" {
  description = "Size of storage for Coder data"
  type        = string
  default     = "10Gi"
}

# Security Configuration
variable "pod_security_context" {
  description = "Pod security context"
  type = object({
    run_as_non_root = bool
    run_as_user     = number
    run_as_group    = number
    fs_group        = number
  })
  default = {
    run_as_non_root = true
    run_as_user     = 1000
    run_as_group    = 1000
    fs_group        = 1000
  }
}

variable "security_context" {
  description = "Container security context"
  type = object({
    allow_privilege_escalation = bool
    run_as_non_root            = bool
    run_as_user                = number
    capabilities = object({
      drop = list(string)
    })
    read_only_root_filesystem = bool
    seccomp_profile = optional(object({
      type = string
      }), {
      type = "RuntimeDefault"
    })
  })
  default = {
    allow_privilege_escalation = false
    run_as_non_root            = true
    run_as_user                = 1000
    capabilities = {
      drop = ["ALL"]
    }
    read_only_root_filesystem = true
    seccomp_profile = {
      type = "RuntimeDefault"
    }
  }
}

# Network Configuration
variable "service_type" {
  description = "Kubernetes service type"
  type        = string
  default     = "ClusterIP"
}

variable "service_port" {
  description = "Service port for Coder"
  type        = number
  default     = 80
}

variable "container_port" {
  description = "Container port for Coder"
  type        = number
  default     = 7080
}

# Health Check Configuration
variable "health_check_config" {
  description = "Health check configuration"
  type = object({
    liveness_probe = object({
      initial_delay_seconds = number
      period_seconds        = number
      timeout_seconds       = number
      failure_threshold     = number
    })
    readiness_probe = object({
      initial_delay_seconds = number
      period_seconds        = number
      timeout_seconds       = number
      failure_threshold     = number
    })
  })
  default = {
    liveness_probe = {
      initial_delay_seconds = 60
      period_seconds        = 30
      timeout_seconds       = 10
      failure_threshold     = 3
    }
    readiness_probe = {
      initial_delay_seconds = 10
      period_seconds        = 5
      timeout_seconds       = 5
      failure_threshold     = 3
    }
  }
}

# Environment Configuration
variable "environment_variables" {
  description = "Additional environment variables for Coder"
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Ingress Configuration
variable "ingress_enabled" {
  description = "Enable ingress for Coder"
  type        = bool
  default     = true
}

variable "ingress_class" {
  description = "Ingress class name"
  type        = string
  default     = "nginx"
}

variable "ingress_annotations" {
  description = "Ingress annotations"
  type        = map(string)
  default = {
    "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
    "nginx.ingress.kubernetes.io/proxy-read-timeout" = "86400"
    "nginx.ingress.kubernetes.io/proxy-send-timeout" = "86400"
    "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
    "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
  }
}

# TLS Configuration
variable "tls_enabled" {
  description = "Enable TLS for ingress"
  type        = bool
  default     = true
}

variable "tls_secret_name" {
  description = "TLS secret name for ingress"
  type        = string
  default     = ""
}

# Monitoring Configuration
variable "monitoring_enabled" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = false
}

# Workspace Configuration
variable "workspace_traffic_policy" {
  description = "Workspace traffic policy (own, path, subdomain)"
  type        = string
  default     = "subdomain"

  validation {
    condition     = contains(["own", "path", "subdomain"], var.workspace_traffic_policy)
    error_message = "Workspace traffic policy must be one of: own, path, subdomain."
  }
}

# Template Configuration
variable "enable_terraform" {
  description = "Enable Terraform provider for workspace templates"
  type        = bool
  default     = true
}

variable "enable_docker" {
  description = "Enable Docker provider for workspace templates"
  type        = string
  default     = "true"
}

# OAuth Configuration
variable "oauth_config" {
  description = "OAuth configuration"
  type = object({
    github = optional(object({
      client_id      = string
      client_secret  = string
      allow_signups  = bool
      allow_everyone = bool
      allowed_orgs   = list(string)
      allowed_teams  = list(string)
    }))
    google = optional(object({
      client_id     = string
      client_secret = string
      allow_signups = bool
    }))
  })
  default = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}