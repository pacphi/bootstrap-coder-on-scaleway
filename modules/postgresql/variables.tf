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
  default = {
    # Connection and performance settings (well-supported)
    "max_connections"           = "200"
    "work_mem"                  = "4MB"
    "maintenance_work_mem"      = "128MB"
    "wal_buffers"               = "16MB"
    "default_statistics_target" = "100"
    "random_page_cost"          = "1.1"
    "effective_cache_size"      = "128MB"

    # Basic logging settings (commonly supported)
    "log_min_duration_statement" = "1000"
    "log_statement"              = "ddl"

    # Note: shared_preload_libraries is managed automatically by Scaleway.
    # Extensions like pg_cron are pre-loaded by default.
    # Advanced logging parameters like log_connections, log_lock_waits,
    # log_temp_files, and log_disconnections may not be supported by
    # Scaleway's managed PostgreSQL service. Add these manually via
    # init_settings or settings override if needed and confirmed to work.
  }
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
  description = "Type of volume for database storage"
  type        = string
  default     = "lssd"

  validation {
    condition     = contains(["lssd", "bssd"], var.volume_type)
    error_message = "Volume type must be either 'lssd' or 'bssd'."
  }
}

variable "volume_size" {
  description = "Size of the volume in GB"
  type        = number
  default     = null
}