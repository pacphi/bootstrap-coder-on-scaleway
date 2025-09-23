# Cluster Information
output "cluster_info" {
  description = "Kubernetes cluster information"
  value = {
    id       = module.scaleway_cluster.cluster_id
    name     = module.scaleway_cluster.cluster_name
    endpoint = module.scaleway_cluster.cluster_endpoint
    version  = module.scaleway_cluster.cluster_version
    status   = module.scaleway_cluster.cluster_status
  }
  sensitive = true
}

# Access Information
output "access_info" {
  description = "Access information for the development environment"
  value = {
    coder_url           = module.networking.access_url
    wildcard_access_url = module.networking.wildcard_access_url
    load_balancer_ip    = module.networking.load_balancer_ip
  }
}

# Database Information
output "database_info" {
  description = "Database connection information"
  value = {
    endpoint = module.postgresql.endpoint
    port     = module.postgresql.port
    database = module.postgresql.database_name
    username = module.postgresql.username
  }
  sensitive = true
}

# Networking Information
output "networking_info" {
  description = "Networking configuration"
  value = {
    vpc_id             = module.networking.vpc_id
    private_network_id = module.networking.private_network_id
    security_group_id  = module.networking.security_group_id
    public_gateway_ip  = module.networking.public_gateway_ip
  }
}

# Security Information
output "security_info" {
  description = "Security configuration"
  value       = module.security.security_configuration
}

# Cost Estimation
output "cost_estimation" {
  description = "Estimated monthly costs in EUR"
  value = {
    cluster_nodes = "€132.86" # 2 × GP1-XS
    database      = "€11.23"  # DB-DEV-S
    load_balancer = "€8.90"   # LB-S
    networking    = "€2.10"   # VPC + Gateway
    total         = "€155.09" # Monthly total
  }
}

# Quick Setup Commands
output "quick_setup_commands" {
  description = "Commands to complete the setup"
  value = {
    get_kubeconfig   = "export KUBECONFIG=<(terraform output -raw kubeconfig)"
    deploy_templates = "./scripts/lifecycle/setup.sh --env=dev --template=<template-name> --auto-approve"
    access_url       = module.networking.access_url != null ? module.networking.access_url : "https://${module.networking.load_balancer_ip}"
    coder_admin_info = "Coder is deployed and running. Access admin credentials from Kubernetes secrets."
  }
}

# Kubeconfig (sensitive)
output "kubeconfig" {
  description = "Kubeconfig for accessing the cluster"
  value       = module.scaleway_cluster.kubeconfig
  sensitive   = true
}

# Direct outputs for GitHub Actions workflow
output "load_balancer_ip" {
  description = "Load balancer IP address"
  value       = module.networking.load_balancer_ip
}

output "access_url" {
  description = "Main access URL for Coder"
  value       = module.networking.access_url
}

output "admin_username" {
  description = "Coder admin username"
  value       = "admin" # Default admin username
}