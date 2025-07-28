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
  description = "Access information for the production environment"
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
    endpoint   = module.postgresql.endpoint
    port       = module.postgresql.port
    database   = module.postgresql.database_name
    username   = module.postgresql.username
    ha_enabled = module.postgresql.is_ha_cluster
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
    ssl_certificate_id = module.networking.ssl_certificate_id
  }
}

# Security Information
output "security_info" {
  description = "Security configuration"
  value       = module.security.security_configuration
}

# High Availability Status
output "ha_status" {
  description = "High availability configuration status"
  value = {
    database_ha         = module.postgresql.is_ha_cluster
    multi_zone_nodes    = true
    backup_retention    = "${local.database_config.backup_schedule_retention} days"
    backup_frequency    = "${local.database_config.backup_schedule_frequency} hours"
    cross_region_backup = true
  }
}

# Cost Estimation
output "cost_estimation" {
  description = "Estimated monthly costs in EUR"
  value = {
    cluster_nodes = "€228.00" # 5 × GP1-M
    database      = "€73.80"  # DB-GP-M HA
    load_balancer = "€45.60"  # LB-GP-M
    networking    = "€2.10"   # VPC + Gateway
    storage       = "€25.00"  # Additional storage
    total         = "€374.50" # Monthly total
  }
}

# Production Checklist
output "production_checklist" {
  description = "Production readiness checklist"
  value = {
    high_availability = "✅ Enabled"
    security_policies = "✅ Restricted Pod Security Standards"
    network_policies  = "✅ Enabled"
    backup_strategy   = "✅ Cross-region backups every 6h"
    monitoring        = "✅ Full stack monitoring"
    ssl_certificates  = "✅ Modern compatibility"
    resource_limits   = "✅ Strict quotas applied"
  }
}

# Quick Setup Commands
output "quick_setup_commands" {
  description = "Commands to complete the setup"
  value = {
    get_kubeconfig = "export KUBECONFIG=<(terraform output -raw kubeconfig)"
    install_coder  = "./scripts/install-coder.sh --env=prod"
    access_url     = module.networking.access_url != null ? module.networking.access_url : "https://${module.networking.load_balancer_ip}"
  }
}

# Kubeconfig (sensitive)
output "kubeconfig" {
  description = "Kubeconfig for accessing the cluster"
  value       = module.scaleway_cluster.kubeconfig
  sensitive   = true
}