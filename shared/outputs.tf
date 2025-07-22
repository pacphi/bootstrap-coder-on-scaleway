# Cluster Outputs
output "cluster_id" {
  description = "ID of the Kubernetes cluster"
  value       = module.scaleway_cluster.cluster_id
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = module.scaleway_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint of the Kubernetes cluster"
  value       = module.scaleway_cluster.cluster_endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "CA certificate of the Kubernetes cluster"
  value       = module.scaleway_cluster.cluster_ca_certificate
  sensitive   = true
}

output "cluster_token" {
  description = "Authentication token for the Kubernetes cluster"
  value       = module.scaleway_cluster.cluster_token
  sensitive   = true
}

# Database Outputs
output "database_endpoint" {
  description = "Endpoint of the PostgreSQL database"
  value       = module.postgresql.endpoint
  sensitive   = true
}

output "database_port" {
  description = "Port of the PostgreSQL database"
  value       = module.postgresql.port
}

output "database_name" {
  description = "Name of the PostgreSQL database"
  value       = module.postgresql.database_name
}

output "database_username" {
  description = "Username for the PostgreSQL database"
  value       = module.postgresql.username
  sensitive   = true
}

output "database_password" {
  description = "Password for the PostgreSQL database"
  value       = module.postgresql.password
  sensitive   = true
}

# Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_network_id" {
  description = "ID of the private network"
  value       = module.networking.private_network_id
}

output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value       = var.enable_load_balancer ? module.networking.load_balancer_ip : null
}

# Coder Outputs
output "coder_url" {
  description = "URL to access Coder"
  value       = module.coder_deployment.coder_url
}

output "coder_admin_username" {
  description = "Initial admin username for Coder"
  value       = module.coder_deployment.admin_username
  sensitive   = true
}

output "coder_admin_password" {
  description = "Initial admin password for Coder"
  value       = module.coder_deployment.admin_password
  sensitive   = true
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost in EUR"
  value = {
    cluster   = local.cluster_cost
    database  = local.database_cost
    network   = local.network_cost
    total     = local.total_cost
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
    "DB-DEV-S" = 12.30  # 1 vCPU, 2GB RAM
    "DB-GP-S"  = 18.45  # 2 vCPU, 4GB RAM
    "DB-GP-M"  = 36.90  # 4 vCPU, 8GB RAM
    "DB-GP-L"  = 73.80  # 8 vCPU, 16GB RAM
  }

  cluster_cost  = var.node_count * lookup(local.node_costs, var.node_type, 0)
  database_cost = lookup(local.db_costs, var.database_node_type, 0)
  network_cost  = var.enable_load_balancer ? 8.90 : 2.10  # LB + VPC costs
  total_cost    = local.cluster_cost + local.database_cost + local.network_cost
}