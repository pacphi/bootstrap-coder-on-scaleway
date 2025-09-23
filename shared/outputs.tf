# Shared Configuration Outputs
output "common_tags" {
  description = "Common tags for all resources"
  value       = local.common_tags
}

output "effective_config" {
  description = "Effective configuration after applying environment defaults"
  value       = local.effective_config
}

output "cluster_name" {
  description = "Generated cluster name"
  value       = local.cluster_name
}

output "database_name" {
  description = "Generated database name"
  value       = local.database_name
}

output "database_user" {
  description = "Database user name"
  value       = local.database_user
}

output "coder_namespace" {
  description = "Kubernetes namespace for Coder"
  value       = local.coder_namespace
}

output "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring"
  value       = local.monitoring_namespace
}

output "vpc_cidr" {
  description = "VPC CIDR for the current environment"
  value       = local.vpc_cidr[var.environment]
}

output "private_subnet_cidr" {
  description = "Private subnet CIDR for the current environment"
  value       = local.private_subnet_cidr[var.environment]
}

output "pod_security_standard" {
  description = "Pod security standard for the current environment"
  value       = local.pod_security_standard
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost in EUR"
  value = {
    cluster  = local.cluster_cost
    database = local.database_cost
    network  = local.network_cost
    total    = local.total_cost
  }
}

locals {
  # Cost estimates based on Scaleway pricing (EUR/month)
  node_costs = {
    "GP1-XS" = 66.43  # 4 vCPU, 16GB RAM
    "GP1-S"  = 136.51 # 8 vCPU, 32GB RAM
    "GP1-M"  = 274.48 # 16 vCPU, 64GB RAM
  }

  db_costs = {
    "DB-DEV-S" = 11.23  # 2 vCPU, 2GB RAM
    "DB-GP-S"  = 273.82 # 8 vCPU, 32GB RAM
    "DB-GP-M"  = 547.24 # 16 vCPU, 64GB RAM
  }

  cluster_cost  = local.effective_config.node_count * lookup(local.node_costs, local.effective_config.node_type, 0)
  database_cost = lookup(local.db_costs, local.effective_config.database_node_type, 0)
  network_cost  = var.enable_load_balancer ? 8.90 : 2.10 # LB + VPC costs
  total_cost    = local.cluster_cost + local.database_cost + local.network_cost
}