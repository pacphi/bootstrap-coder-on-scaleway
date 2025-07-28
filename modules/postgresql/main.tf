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

# PostgreSQL Database Instance
resource "scaleway_rdb_instance" "postgresql" {
  name           = var.instance_name
  node_type      = var.node_type
  engine         = var.engine
  is_ha_cluster  = var.is_ha_cluster
  disable_backup = var.disable_backup

  volume_type       = var.volume_type
  volume_size_in_gb = var.volume_size

  backup_schedule_frequency = var.backup_schedule_frequency
  backup_schedule_retention = var.backup_schedule_retention
  backup_same_region        = var.backup_same_region

  private_network {
    pn_id = var.private_network_id
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

# ACL Rules for private network access
resource "scaleway_rdb_acl" "postgresql_acl" {
  instance_id = scaleway_rdb_instance.postgresql.id

  acl_rules {
    ip          = "0.0.0.0/0"
    description = "Allow all connections from private network"
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