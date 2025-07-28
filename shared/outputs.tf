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
    "GP1-XS" = 15.20  # 1 vCPU, 2GB RAM
    "GP1-S"  = 22.80  # 2 vCPU, 4GB RAM
    "GP1-M"  = 45.60  # 4 vCPU, 8GB RAM
    "GP1-L"  = 91.20  # 8 vCPU, 16GB RAM
    "GP1-XL" = 182.40 # 16 vCPU, 32GB RAM
  }

  db_costs = {
    "DB-DEV-S" = 12.30 # 1 vCPU, 2GB RAM
    "DB-GP-S"  = 18.45 # 2 vCPU, 4GB RAM
    "DB-GP-M"  = 36.90 # 4 vCPU, 8GB RAM
    "DB-GP-L"  = 73.80 # 8 vCPU, 16GB RAM
  }

  cluster_cost  = local.effective_config.node_count * lookup(local.node_costs, local.effective_config.node_type, 0)
  database_cost = lookup(local.db_costs, local.effective_config.database_node_type, 0)
  network_cost  = var.enable_load_balancer ? 8.90 : 2.10 # LB + VPC costs
  total_cost    = local.cluster_cost + local.database_cost + local.network_cost
}