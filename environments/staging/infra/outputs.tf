# Cluster outputs
output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = module.scaleway_cluster.cluster_name
}

output "cluster_id" {
  description = "ID of the Kubernetes cluster"
  value       = module.scaleway_cluster.cluster_id
}

output "kubeconfig" {
  description = "Kubernetes config file content"
  value       = module.scaleway_cluster.kubeconfig
  sensitive   = true
}

# Networking outputs
output "access_url" {
  description = "Access URL for Coder"
  value       = module.networking.access_url
}

output "wildcard_access_url" {
  description = "Wildcard access URL for Coder workspaces"
  value       = module.networking.wildcard_access_url
}

output "load_balancer_ip" {
  description = "Load balancer IP address"
  value       = module.networking.load_balancer_ip
}

output "private_network_id" {
  description = "Private network ID"
  value       = module.networking.private_network_id
}

# Database outputs
output "database_connection_string" {
  description = "Database connection string"
  value       = module.postgresql.connection_string
  sensitive   = true
}

output "database_host" {
  description = "Database host"
  value       = module.postgresql.host
}

output "database_port" {
  description = "Database port"
  value       = module.postgresql.port
}

output "database_name" {
  description = "Database name"
  value       = module.postgresql.database_name
}

output "database_username" {
  description = "Database username"
  value       = module.postgresql.username
}

# Environment information
output "environment" {
  description = "Environment name"
  value       = "staging"
}

output "project_name" {
  description = "Project name"
  value       = "coder"
}