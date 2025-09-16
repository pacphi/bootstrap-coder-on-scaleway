output "instance_id" {
  description = "ID of the PostgreSQL instance"
  value       = scaleway_rdb_instance.postgresql.id
}

output "endpoint" {
  description = "Connection endpoint for the PostgreSQL database"
  value       = scaleway_rdb_instance.postgresql.private_network[0].ip
}

output "port" {
  description = "Connection port for the PostgreSQL database"
  value       = scaleway_rdb_instance.postgresql.private_network[0].port
}

output "database_name" {
  description = "Name of the created database"
  value       = scaleway_rdb_database.coder_database.name
}

output "username" {
  description = "Database username"
  value       = scaleway_rdb_user.coder_user.name
}

output "password" {
  description = "Database password"
  value       = random_password.db_password.result
  sensitive   = true
}

output "connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${scaleway_rdb_user.coder_user.name}:${random_password.db_password.result}@${scaleway_rdb_instance.postgresql.private_network[0].ip}:${scaleway_rdb_instance.postgresql.private_network[0].port}/${scaleway_rdb_database.coder_database.name}?sslmode=require"
  sensitive   = true
}

output "connection_pool_string" {
  description = "PostgreSQL connection string for connection pooling"
  value       = "postgresql://${scaleway_rdb_user.coder_user.name}:${random_password.db_password.result}@${scaleway_rdb_instance.postgresql.private_network[0].ip}:${scaleway_rdb_instance.postgresql.private_network[0].port}/${scaleway_rdb_database.coder_database.name}?sslmode=require&pool_max_conns=10"
  sensitive   = true
}

output "engine_version" {
  description = "Version of the PostgreSQL engine"
  value       = scaleway_rdb_instance.postgresql.engine
}

output "node_type" {
  description = "Node type of the PostgreSQL instance"
  value       = scaleway_rdb_instance.postgresql.node_type
}

output "is_ha_cluster" {
  description = "Whether the instance is configured as high availability cluster"
  value       = scaleway_rdb_instance.postgresql.is_ha_cluster
}

output "backup_schedule" {
  description = "Backup schedule configuration"
  value = {
    frequency   = scaleway_rdb_instance.postgresql.backup_schedule_frequency
    retention   = scaleway_rdb_instance.postgresql.backup_schedule_retention
    same_region = scaleway_rdb_instance.postgresql.backup_same_region
  }
}

output "volume_info" {
  description = "Volume information"
  value = {
    type    = scaleway_rdb_instance.postgresql.volume_type
    size_gb = scaleway_rdb_instance.postgresql.volume_size_in_gb
  }
}

# Cost optimization outputs
output "cost_optimization_summary" {
  description = "Summary of cost optimization applied"
  value = var.cost_optimization_enabled ? {
    enabled          = true
    environment_tier = var.environment_tier
    node_type        = local.final_config.node_type
    volume_type      = local.final_config.volume_type
    volume_size_gb   = local.final_config.volume_size
    is_ha_cluster    = local.final_config.is_ha_cluster
    backup_retention = local.final_config.backup_retention
    estimated_monthly_cost = local.final_config.node_type == "DB-DEV-S" ? "€12-15" : (
      local.final_config.node_type == "DB-GP-S" ? "€25-35" : "€60-120"
    )
    } : {
    enabled = false
    message = "Cost optimization disabled - using provided configuration"
  }
}