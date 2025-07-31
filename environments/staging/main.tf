terraform {
  required_version = ">= 1.12.0"
}

# Import shared configuration
module "shared_config" {
  source = "../../shared"

  environment = local.environment
}

# Local variables for staging environment
locals {
  environment  = "staging"
  project_name = "coder"

  # Staging-specific overrides (production-like)
  cluster_config = {
    node_count   = 3
    node_type    = "GP1-S" # 2 vCPU, 4GB RAM
    min_size     = 2
    max_size     = 8
    auto_upgrade = true
  }

  database_config = {
    node_type                 = "DB-GP-S" # 2 vCPU, 4GB RAM
    is_ha_cluster             = false
    backup_schedule_frequency = 12 # Every 12 hours
    backup_schedule_retention = 30
  }

  security_config = {
    enable_pod_security_standards = true
    pod_security_standard         = "baseline"
    enable_network_policies       = true
    enable_rbac                   = true
  }

  monitoring_config = {
    enable_monitoring = true
  }

  # Networking
  domain_name = "" # Configure your domain here
  subdomain   = "coder-staging"
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
  cluster_description = "Staging Kubernetes cluster for Coder (Production-like)"
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
      root_volume_size  = 40
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

  # Enhanced settings for staging
  settings = {
    "max_connections"            = "300"
    "shared_preload_libraries"   = "pg_stat_statements,pg_stat_monitor"
    "log_min_duration_statement" = "500"
    "log_statement"              = "ddl"
    "work_mem"                   = "8MB"
    "maintenance_work_mem"       = "256MB"
    # "checkpoint_completion_target" = "0.9" # Removed - not supported by Scaleway provider
    "wal_buffers"          = "32MB"
    "effective_cache_size" = "512MB"
    # Note: Removed log_connections, log_disconnections, and log_lock_waits
    # as these logging parameters may not be supported by Scaleway managed PostgreSQL
  }

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

  additional_namespaces = ["monitoring", "cert-manager"]

  # Enhanced resource quotas for staging
  resource_quotas = {
    hard_limits = {
      "requests.cpu"           = "8"
      "requests.memory"        = "16Gi"
      "limits.cpu"             = "16"
      "limits.memory"          = "32Gi"
      "pods"                   = "20"
      "services"               = "10"
      "persistentvolumeclaims" = "20"
    }
  }

  depends_on = [module.scaleway_cluster]
}

# Coder Deployment Module
module "coder_deployment" {
  source = "../../modules/coder-deployment"

  namespace            = "coder"
  environment          = local.environment
  coder_version        = "2.6.0"
  database_url         = module.postgresql.connection_string
  access_url           = module.networking.access_url
  wildcard_access_url  = module.networking.wildcard_access_url
  service_account_name = "coder"

  # Staging-specific resource limits (production-like)
  resources = {
    limits = {
      cpu    = "2000m"
      memory = "4Gi"
    }
    requests = {
      cpu    = "500m"
      memory = "1Gi"
    }
  }

  # Storage configuration - use scw-bssd storage class
  storage_class = "scw-bssd"
  storage_size  = "20Gi"

  # Enable monitoring for staging
  monitoring_enabled = local.monitoring_config.enable_monitoring

  # Workspace configuration
  workspace_traffic_policy = "subdomain"
  enable_terraform         = true

  # Enhanced security settings for staging
  pod_security_context = {
    run_as_non_root = true
    run_as_user     = 1000
    run_as_group    = 1000
    fs_group        = 1000
  }

  security_context = {
    allow_privilege_escalation = false
    run_as_non_root            = true
    run_as_user                = 1000
    capabilities = {
      drop = ["ALL"]
    }
    read_only_root_filesystem = true
  }

  # Ingress configuration based on domain setup
  ingress_enabled = local.domain_name != ""
  ingress_class   = "nginx"
  tls_enabled     = local.domain_name != ""

  # Enhanced ingress annotations for staging
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
    "nginx.ingress.kubernetes.io/proxy-read-timeout" = "86400"
    "nginx.ingress.kubernetes.io/proxy-send-timeout" = "86400"
    "nginx.ingress.kubernetes.io/ssl-redirect"       = "true"
    "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
    "nginx.ingress.kubernetes.io/rate-limit"         = "100"
    "cert-manager.io/cluster-issuer"                 = "letsencrypt-prod"
  }

  tags = merge(var.tags, {
    Environment = local.environment
  })

  depends_on = [
    module.scaleway_cluster,
    module.postgresql,
    module.networking,
    module.security
  ]
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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    "managed-by"  = "terraform"
    "project"     = "coder"
    "environment" = "staging"
  }
}