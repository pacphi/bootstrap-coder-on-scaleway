terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# Generate a random password for the database user
resource "random_password" "db_password" {
  length  = 32
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Smart defaults based on environment tier for cost optimization
locals {
  # Cost-optimized configurations by environment
  cost_optimized_config = var.cost_optimization_enabled ? {
    dev = {
      node_type        = "DB-DEV-S"
      volume_type      = "sbv" # Cost-optimized storage
      volume_size      = 20    # Minimal size
      backup_retention = 3     # Short retention
      is_ha_cluster    = false # No HA for dev
    }
    staging = {
      node_type        = "DB-GP-S"
      volume_type      = "bssd" # Balanced performance/cost
      volume_size      = 50     # Medium size
      backup_retention = 7      # Standard retention
      is_ha_cluster    = false  # Single instance
    }
    prod = {
      node_type        = var.node_type   # Use provided or default
      volume_type      = var.volume_type # Use provided for prod
      volume_size      = var.volume_size != null ? var.volume_size : 100
      backup_retention = var.backup_schedule_retention
      is_ha_cluster    = true # Always HA for prod
    }
  } : {}

  # Final configuration (cost-optimized or user-provided)
  final_config = var.cost_optimization_enabled ? local.cost_optimized_config[var.environment_tier] : {
    node_type        = var.node_type
    volume_type      = var.volume_type
    volume_size      = var.volume_size
    backup_retention = var.backup_schedule_retention
    is_ha_cluster    = var.is_ha_cluster
  }
}

# PostgreSQL Database Instance
resource "scaleway_rdb_instance" "postgresql" {
  name           = var.instance_name
  node_type      = local.final_config.node_type
  engine         = var.engine
  is_ha_cluster  = local.final_config.is_ha_cluster
  disable_backup = var.disable_backup

  volume_type       = local.final_config.volume_type
  volume_size_in_gb = local.final_config.volume_size

  backup_schedule_frequency = var.backup_schedule_frequency
  backup_schedule_retention = local.final_config.backup_retention
  backup_same_region        = var.backup_same_region

  private_network {
    pn_id       = var.private_network_id
    enable_ipam = true
  }

  settings = merge(var.settings, var.init_settings)

  tags = [for k, v in var.tags : "${k}:${v}"]

  depends_on = [random_password.db_password]
}

# Database User
resource "scaleway_rdb_user" "coder_user" {
  instance_id = scaleway_rdb_instance.postgresql.id
  name        = var.user_name
  password    = random_password.db_password.result
  is_admin    = true
}

# Database
resource "scaleway_rdb_database" "coder_database" {
  instance_id = scaleway_rdb_instance.postgresql.id
  name        = var.database_name
  # owner removed - automatically set based on user creation

  depends_on = [scaleway_rdb_user.coder_user]
}

# ACL Rules for VPC-only access (restricted)
resource "scaleway_rdb_acl" "postgresql_acl" {
  instance_id = scaleway_rdb_instance.postgresql.id

  acl_rules {
    ip          = var.vpc_cidr
    description = "Allow connections from VPC network only"
  }
}

# Privilege for the user
resource "scaleway_rdb_privilege" "coder_privilege" {
  instance_id   = scaleway_rdb_instance.postgresql.id
  user_name     = scaleway_rdb_user.coder_user.name
  database_name = scaleway_rdb_database.coder_database.name
  permission    = "all"

  depends_on = [
    scaleway_rdb_user.coder_user,
    scaleway_rdb_database.coder_database
  ]
}