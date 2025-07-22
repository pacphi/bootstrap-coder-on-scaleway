locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # Generate cluster name if not provided
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${local.name_prefix}-cluster"

  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment   = var.environment
    Project       = var.project_name
    ManagedBy     = "terraform"
    CreatedAt     = timestamp()
  })

  # Environment-specific defaults
  environment_defaults = {
    dev = {
      node_count                          = 2
      node_type                          = "GP1-XS"
      min_size                           = 1
      max_size                           = 5
      database_node_type                 = "DB-DEV-S"
      database_is_ha_cluster             = false
      database_backup_schedule_retention = 7
      enable_monitoring                  = false
      enable_pod_security_policy         = false
      enable_network_policy              = false
    }

    staging = {
      node_count                          = 3
      node_type                          = "GP1-S"
      min_size                           = 2
      max_size                           = 8
      database_node_type                 = "DB-GP-S"
      database_is_ha_cluster             = false
      database_backup_schedule_retention = 30
      enable_monitoring                  = true
      enable_pod_security_policy         = true
      enable_network_policy              = true
    }

    prod = {
      node_count                          = 5
      node_type                          = "GP1-M"
      min_size                           = 3
      max_size                           = 15
      database_node_type                 = "DB-GP-M"
      database_is_ha_cluster             = true
      database_backup_schedule_retention = 90
      enable_monitoring                  = true
      enable_pod_security_policy         = true
      enable_network_policy              = true
    }
  }

  # Apply environment defaults (can be overridden by variables)
  effective_config = merge(
    local.environment_defaults[var.environment],
    {
      # Only override if variable was explicitly set (not default)
      node_count                          = var.node_count
      node_type                          = var.node_type
      min_size                           = var.min_size
      max_size                           = var.max_size
      database_node_type                 = var.database_node_type
      database_is_ha_cluster             = var.database_is_ha_cluster
      database_backup_schedule_retention = var.database_backup_schedule_retention
      enable_monitoring                  = var.enable_monitoring
      enable_pod_security_policy         = var.enable_pod_security_policy
      enable_network_policy              = var.enable_network_policy
    }
  )

  # Kubernetes namespace
  coder_namespace = "coder"

  # Database configuration
  database_name = "${replace(local.name_prefix, "-", "_")}_db"
  database_user = "coder"

  # Networking
  vpc_cidr = {
    dev     = "10.0.0.0/16"
    staging = "10.1.0.0/16"
    prod    = "10.2.0.0/16"
  }

  private_subnet_cidr = {
    dev     = "10.0.1.0/24"
    staging = "10.1.1.0/24"
    prod    = "10.2.1.0/24"
  }

  # Monitoring configuration
  monitoring_namespace = "monitoring"

  # Security configuration
  pod_security_standard = var.environment == "prod" ? "restricted" : "baseline"
}