terraform {
  required_version = ">= 1.12.0"
}

# Import shared configuration
module "shared_config" {
  source = "../../shared"

  environment              = local.environment
  scaleway_organization_id = var.scaleway_organization_id
  scaleway_project_id      = var.scaleway_project_id
}

# Local variables for development environment
locals {
  environment  = "dev"
  project_name = "coder"

  # Development-specific overrides
  cluster_config = {
    node_count   = 2
    node_type    = "GP1-XS" # 1 vCPU, 2GB RAM
    min_size     = 1
    max_size     = 5
    auto_upgrade = true
  }

  database_config = {
    node_type                 = "DB-DEV-S" # 1 vCPU, 2GB RAM
    is_ha_cluster             = false
    backup_schedule_frequency = 24
    backup_schedule_retention = 7
  }

  security_config = {
    enable_pod_security_standards = false
    pod_security_standard         = "baseline"
    enable_network_policies       = false
    enable_rbac                   = true
  }

  monitoring_config = {
    enable_monitoring = false
  }

  # Networking
  domain_name = "" # Use IP-based access for dev
  subdomain   = "coder-dev"
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  vpc_name             = "${local.project_name}-${local.environment}-vpc"
  private_network_name = "${local.project_name}-${local.environment}-network"
  load_balancer_name   = "${local.project_name}-${local.environment}-lb"
  load_balancer_type   = "LB-S"

  enable_load_balancer = true
  domain_name          = local.domain_name
  subdomain            = local.subdomain

  region = var.scaleway_region
  zone   = var.scaleway_zone

  tags = [for k, v in merge(var.tags, {
    Environment = local.environment
  }) : "${k}:${v}"]
}

# Scaleway Cluster Module
module "scaleway_cluster" {
  source = "../../modules/scaleway-cluster"

  cluster_name        = "${local.project_name}-${local.environment}-cluster"
  cluster_description = "Development Kubernetes cluster for Coder"
  cluster_version     = "1.32"

  enable_dashboard = false
  auto_upgrade     = local.cluster_config.auto_upgrade

  private_network_id = module.networking.private_network_id

  node_pools = [
    {
      name              = "default"
      node_type         = local.cluster_config.node_type
      size              = local.cluster_config.node_count
      min_size          = local.cluster_config.min_size
      max_size          = local.cluster_config.max_size
      autoscaling       = true
      autohealing       = true
      container_runtime = "containerd"
      root_volume_type  = "l_ssd"
      root_volume_size  = 20
    }
  ]

  region = var.scaleway_region
  zone   = var.scaleway_zone

  tags = merge(var.tags, {
    Environment = local.environment
  })
}

# PostgreSQL Module
module "postgresql" {
  source = "../../modules/postgresql"

  instance_name = "${local.project_name}-${local.environment}-db"
  database_name = "${replace(local.project_name, "-", "_")}_${local.environment}_db"
  user_name     = "coder"

  node_type                 = local.database_config.node_type
  is_ha_cluster             = local.database_config.is_ha_cluster
  backup_schedule_frequency = local.database_config.backup_schedule_frequency
  backup_schedule_retention = local.database_config.backup_schedule_retention

  private_network_id = module.networking.private_network_id

  region = var.scaleway_region
  zone   = var.scaleway_zone

  tags = merge(var.tags, {
    Environment = local.environment
  })
}

# Security Module
module "security" {
  source = "../../modules/security"

  cluster_name = module.scaleway_cluster.cluster_name
  namespace    = "coder"

  enable_pod_security_standards = local.security_config.enable_pod_security_standards
  pod_security_standard         = local.security_config.pod_security_standard
  enable_network_policies       = local.security_config.enable_network_policies
  enable_rbac                   = local.security_config.enable_rbac

  additional_namespaces = ["monitoring"]

  depends_on = [module.scaleway_cluster]
}

# Import variables from shared configuration
variable "scaleway_zone" {
  description = "Scaleway zone"
  type        = string
  default     = "fr-par-1"
}

variable "scaleway_region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "scaleway_organization_id" {
  description = "Scaleway organization ID"
  type        = string
  sensitive   = true
}

variable "scaleway_project_id" {
  description = "Scaleway project ID"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    "managed-by"  = "terraform"
    "project"     = "coder"
    "environment" = "dev"
  }
}