variable "instance_name" {
  description = "Name of the PostgreSQL instance"
  type        = string
}

variable "engine" {
  description = "Database engine"
  type        = string
  default     = "PostgreSQL-15"
}

variable "node_type" {
  description = "Node type for the database instance"
  type        = string
  default     = "DB-DEV-S"
}

variable "is_ha_cluster" {
  description = "Enable high availability cluster"
  type        = bool
  default     = false
}

variable "disable_backup" {
  description = "Disable automatic backups"
  type        = bool
  default     = false
}

variable "backup_schedule_frequency" {
  description = "Backup frequency in hours"
  type        = number
  default     = 24

  validation {
    condition     = contains([24, 12, 8, 6, 4, 3, 2, 1], var.backup_schedule_frequency)
    error_message = "Backup frequency must be one of: 24, 12, 8, 6, 4, 3, 2, 1 hours."
  }
}

variable "backup_schedule_retention" {
  description = "Backup retention in days"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_schedule_retention >= 1 && var.backup_schedule_retention <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

variable "backup_same_region" {
  description = "Store backups in the same region"
  type        = bool
  default     = true
}

variable "user_name" {
  description = "Username for the database"
  type        = string
  default     = "coder"
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
}

variable "init_settings" {
  description = "Initial settings for the database"
  type        = map(string)
  default     = {}
}

variable "settings" {
  description = "Database settings - optimized for Scaleway managed PostgreSQL"
  type        = map(string)
  default     = {}
}

variable "private_network_id" {
  description = "ID of the private network"
  type        = string
}

variable "region" {
  description = "Scaleway region"
  type        = string
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "volume_type" {
  description = "Type of volume for database storage (lssd=Local SSD, bssd=Block SSD, sbv=SBV)"
  type        = string
  default     = "lssd"

  validation {
    condition     = contains(["lssd", "bssd", "sbv"], var.volume_type)
    error_message = "Volume type must be one of: 'lssd' (Local SSD - highest performance), 'bssd' (Block SSD - balanced), 'sbv' (SBV - cost-optimized)."
  }
}

variable "cost_optimization_enabled" {
  description = "Enable cost optimization features (storage tiering, auto-scaling)"
  type        = bool
  default     = false
}

variable "environment_tier" {
  description = "Environment tier for cost optimization (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment_tier)
    error_message = "Environment tier must be one of: dev, staging, prod."
  }
}

variable "volume_size" {
  description = "Size of the volume in GB"
  type        = number
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR range for database access control"
  type        = string
  default     = "10.0.0.0/8"
}