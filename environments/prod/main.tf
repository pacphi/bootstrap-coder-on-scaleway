terraform {
  required_version = ">= 1.12.0"
}

# Import shared configuration
module "shared_config" {
  source = "../../shared"

  environment                = local.environment
  scaleway_organization_id   = var.scaleway_organization_id
  scaleway_project_id        = var.scaleway_project_id
}

# Local variables for production environment
locals {
  environment = "prod"
  project_name = "coder"

  # Production configuration (high availability, performance)
  cluster_config = {
    node_count     = 5
    node_type      = "GP1-M"  # 4 vCPU, 8GB RAM
    min_size       = 3
    max_size       = 15
    auto_upgrade   = true
  }

  database_config = {
    node_type                      = "DB-GP-M"  # 4 vCPU, 8GB RAM
    is_ha_cluster                  = true       # High availability
    backup_schedule_frequency      = 6          # Every 6 hours
    backup_schedule_retention      = 90         # 90 days retention
  }

  security_config = {
    enable_pod_security_standards = true
    pod_security_standard         = "restricted"  # Most secure
    enable_network_policies       = true
    enable_rbac                   = true
  }

  monitoring_config = {
    enable_monitoring = true
  }

  # Networking
  domain_name = ""  # Configure your production domain here
  subdomain   = "coder"  # Production on main domain
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  vpc_name             = "${local.project_name}-${local.environment}-vpc"
  private_network_name = "${local.project_name}-${local.environment}-network"
  load_balancer_name   = "${local.project_name}-${local.environment}-lb"
  load_balancer_type   = "LB-GP-M"  # Higher capacity for production

  enable_load_balancer = true
  domain_name         = local.domain_name
  subdomain           = local.subdomain

  ssl_compatibility_level = "ssl_compatibility_level_modern"

  # Enhanced security group rules for production
  security_group_rules = [
    {
      direction   = "inbound"
      action      = "accept"
      protocol    = "TCP"
      port        = 9443
      ip_range    = "10.0.0.0/8"
      description = "Internal monitoring"
    }
  ]

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
  cluster_description = "Production Kubernetes cluster for Coder"
  cluster_version     = "1.29"

  enable_dashboard = false  # Disabled for security in production
  auto_upgrade     = local.cluster_config.auto_upgrade

  maintenance_window_start_hour = 2
  maintenance_window_day        = "sunday"

  private_network_id = module.networking.private_network_id

  # Multi-zone node pools for high availability
  node_pools = [
    {
      name               = "default"
      node_type         = local.cluster_config.node_type
      size              = local.cluster_config.node_count
      min_size          = local.cluster_config.min_size
      max_size          = local.cluster_config.max_size
      autoscaling       = true
      autohealing       = true
      container_runtime = "containerd"
      root_volume_type  = "l_ssd"
      root_volume_size  = 100  # Larger disk for production
    }
  ]

  # Production security features
  feature_gates = [
    "CSIVolumeHealth=true",
    "ReadWriteOncePod=true"
  ]

  admission_plugins = [
    "NamespaceLifecycle",
    "LimitRanger",
    "ServiceAccount",
    "DefaultStorageClass",
    "DefaultTolerationSeconds",
    "MutatingAdmissionWebhook",
    "ValidatingAdmissionWebhook",
    "ResourceQuota",
    "PodSecurityPolicy"
  ]

  region = var.scaleway_region
  zone   = var.scaleway_zone

  tags = merge(var.tags, {
    Environment = local.environment
  })
}

# PostgreSQL Module with High Availability
module "postgresql" {
  source = "../../modules/postgresql"

  instance_name                   = "${local.project_name}-${local.environment}-db"
  database_name                   = "${replace(local.project_name, "-", "_")}_${local.environment}_db"
  user_name                       = "coder"

  node_type                      = local.database_config.node_type
  is_ha_cluster                  = local.database_config.is_ha_cluster
  backup_schedule_frequency      = local.database_config.backup_schedule_frequency
  backup_schedule_retention      = local.database_config.backup_schedule_retention
  backup_same_region            = false  # Cross-region backups for disaster recovery

  # Production-optimized database settings
  settings = {
    "max_connections"              = "500"
    "shared_preload_libraries"     = "pg_stat_statements,pg_stat_monitor,pg_cron"
    "log_min_duration_statement"   = "250"
    "log_connections"              = "on"
    "log_disconnections"          = "on"
    "log_lock_waits"              = "on"
    "log_statement"               = "ddl"
    "log_checkpoints"             = "on"
    "work_mem"                    = "16MB"
    "maintenance_work_mem"        = "512MB"
    "checkpoint_completion_target" = "0.9"
    "wal_buffers"                 = "64MB"
    "effective_cache_size"        = "2GB"
    "random_page_cost"            = "1.1"
    "seq_page_cost"               = "1"
    "default_statistics_target"   = "500"
  }

  volume_type = "bssd"  # Block SSD for better performance

  private_network_id = module.networking.private_network_id

  region = var.scaleway_region
  zone   = var.scaleway_zone

  tags = merge(var.tags, {
    Environment = local.environment
  })
}

# Enhanced Security Module
module "security" {
  source = "../../modules/security"

  cluster_name = module.scaleway_cluster.cluster_name
  namespace    = "coder"

  enable_pod_security_standards = local.security_config.enable_pod_security_standards
  pod_security_standard         = local.security_config.pod_security_standard
  enable_network_policies       = local.security_config.enable_network_policies
  enable_rbac                   = local.security_config.enable_rbac

  additional_namespaces = ["monitoring", "cert-manager", "ingress-nginx"]

  # Strict resource quotas for production
  resource_quotas = {
    hard_limits = {
      "requests.cpu"              = "16"
      "requests.memory"           = "32Gi"
      "limits.cpu"               = "32"
      "limits.memory"            = "64Gi"
      "pods"                     = "50"
      "services"                 = "20"
      "persistentvolumeclaims"   = "50"
    }
  }

  # Enhanced network policies for production
  network_policy_rules = [
    {
      name      = "deny-all-cross-namespace"
      namespace = "coder"
      pod_selector = {}
      ingress = [{
        from = [{
          namespace_selector = {
            "name" = "coder"
          }
        }]
      }]
    }
  ]

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
    "managed-by" = "terraform"
    "project"    = "coder"
    "environment" = "prod"
    "backup"     = "required"
    "monitoring" = "required"
  }
}