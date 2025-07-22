# Scaleway Configuration
variable "scaleway_zone" {
  description = "Scaleway zone"
  type        = string
  default     = "fr-par-1"
}

variable "scaleway_region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "scaleway_organization_id" {
  description = "Scaleway organization ID"
  type        = string
  sensitive   = true
}

variable "scaleway_project_id" {
  description = "Scaleway project ID"
  type        = string
  sensitive   = true
}

# Environment Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "coder"
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Number of nodes in the cluster"
  type        = number
  default     = 2
}

variable "node_type" {
  description = "Node type for the cluster"
  type        = string
  default     = "GP1-XS"
}

variable "min_size" {
  description = "Minimum number of nodes in autoscaling pool"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes in autoscaling pool"
  type        = number
  default     = 10
}

variable "auto_upgrade" {
  description = "Enable automatic upgrades for the cluster"
  type        = bool
  default     = true
}

# Database Configuration
variable "database_node_type" {
  description = "Database node type"
  type        = string
  default     = "DB-DEV-S"
}

variable "database_is_ha_cluster" {
  description = "Enable high availability for database"
  type        = bool
  default     = false
}

variable "database_backup_schedule_frequency" {
  description = "Backup frequency in hours"
  type        = number
  default     = 24
}

variable "database_backup_schedule_retention" {
  description = "Backup retention in days"
  type        = number
  default     = 7
}

# Coder Configuration
variable "coder_version" {
  description = "Coder version to deploy"
  type        = string
  default     = "2.6.0"
}

variable "coder_access_url" {
  description = "Access URL for Coder"
  type        = string
  default     = ""
}

variable "coder_wildcard_access_url" {
  description = "Wildcard access URL for Coder workspaces"
  type        = string
  default     = ""
}

# Networking
variable "enable_load_balancer" {
  description = "Enable load balancer for Coder"
  type        = bool
  default     = true
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for SSL certificates and access URLs"
  type        = string
  default     = ""
  validation {
    condition = var.domain_name == "" || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9\\-]*[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9\\-]*[a-zA-Z0-9])?)*$", var.domain_name))
    error_message = "Domain name must be a valid DNS name (e.g., example.com, my-site.co.uk) or empty for IP-based access."
  }
}

variable "subdomain" {
  description = "Subdomain prefix for the Coder instance"
  type        = string
  default     = ""
  validation {
    condition = var.subdomain == "" || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9\\-]*[a-zA-Z0-9])?$", var.subdomain))
    error_message = "Subdomain must contain only letters, numbers, and hyphens, or be empty."
  }
}

# Security
variable "enable_pod_security_policy" {
  description = "Enable Pod Security Policy"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable Network Policy"
  type        = bool
  default     = true
}

# Monitoring
variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus/Grafana)"
  type        = bool
  default     = false
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "project"    = "coder"
  }
}