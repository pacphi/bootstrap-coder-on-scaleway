terraform {
  required_version = ">= 1.12.0"
}

# Import shared configuration
module "shared_config" {
  source = "../../shared"

  environment = local.environment
}

# Local variables for production environment
locals {
  environment  = "prod"
  project_name = "coder"

  # Production configuration (high availability, performance)
  cluster_config = {
    node_count   = 5
    node_type    = "GP1-M" # 4 vCPU, 8GB RAM
    min_size     = 3
    max_size     = 15
    auto_upgrade = true
  }

  database_config = {
    node_type                 = "DB-GP-M" # 4 vCPU, 8GB RAM
    is_ha_cluster             = true      # High availability
    backup_schedule_frequency = 6         # Every 6 hours
    backup_schedule_retention = 90        # 90 days retention
  }

  security_config = {
    enable_pod_security_standards = true
    pod_security_standard         = "restricted" # Most secure
    enable_network_policies       = true
    enable_rbac                   = true
  }

  monitoring_config = {
    enable_monitoring = true
  }

  # Networking
  domain_name = ""      # Configure your production domain here
  subdomain   = "coder" # Production on main domain
}

# Networking Module
module "networking" {
  source = "../../modules/networking"

  vpc_name             = "${local.project_name}-${local.environment}-vpc"
  private_network_name = "${local.project_name}-${local.environment}-network"
  load_balancer_name   = "${local.project_name}-${local.environment}-lb"
  load_balancer_type   = "LB-GP-M" # Higher capacity for production

  enable_load_balancer = true
  domain_name          = local.domain_name
  subdomain            = local.subdomain

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
  cluster_version     = "1.32"

  enable_dashboard = false # Disabled for security in production
  auto_upgrade     = local.cluster_config.auto_upgrade

  maintenance_window_start_hour = 2
  maintenance_window_day        = "sunday"

  private_network_id = module.networking.private_network_id

  # Multi-zone node pools for high availability
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
      root_volume_size  = 100 # Larger disk for production
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

  instance_name = "${local.project_name}-${local.environment}-db"
  database_name = "${replace(local.project_name, "-", "_")}_${local.environment}_db"
  user_name     = "coder"

  node_type                 = local.database_config.node_type
  is_ha_cluster             = local.database_config.is_ha_cluster
  backup_schedule_frequency = local.database_config.backup_schedule_frequency
  backup_schedule_retention = local.database_config.backup_schedule_retention
  backup_same_region        = false # Cross-region backups for disaster recovery

  # Production-optimized database settings
  settings = {
    "max_connections"            = "500"
    "shared_preload_libraries"   = "pg_stat_statements,pg_stat_monitor,pg_cron"
    "log_min_duration_statement" = "250"
    "log_statement"              = "ddl"
    "work_mem"                   = "16MB"
    "maintenance_work_mem"       = "512MB"
    # "checkpoint_completion_target" = "0.9" # Removed - not supported by Scaleway provider
    "wal_buffers"               = "64MB"
    "effective_cache_size"      = "2GB"
    "random_page_cost"          = "1.1"
    "seq_page_cost"             = "1"
    "default_statistics_target" = "500"
    # Note: Removed log_connections, log_disconnections, log_lock_waits, and log_checkpoints
    # as these advanced logging parameters may not be supported by Scaleway managed PostgreSQL
  }

  volume_type = "bssd" # Block SSD for better performance

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
      "requests.cpu"           = "16"
      "requests.memory"        = "32Gi"
      "limits.cpu"             = "32"
      "limits.memory"          = "64Gi"
      "pods"                   = "50"
      "services"               = "20"
      "persistentvolumeclaims" = "50"
    }
  }

  # Enhanced network policies for production
  network_policy_rules = [
    {
      name         = "deny-all-cross-namespace"
      namespace    = "coder"
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

# Coder Deployment Module - Production Configuration
module "coder_deployment" {
  source = "../../modules/coder-deployment"

  namespace            = "coder"
  environment          = local.environment
  coder_version        = "2.6.0"
  database_url         = module.postgresql.connection_string
  access_url           = module.networking.access_url
  wildcard_access_url  = module.networking.wildcard_access_url
  service_account_name = "coder"

  # Production-grade resource limits
  resources = {
    limits = {
      cpu    = "4000m"
      memory = "8Gi"
    }
    requests = {
      cpu    = "1000m"
      memory = "2Gi"
    }
  }

  # High availability configuration
  replica_count = 2

  # Storage configuration - use scw-bssd storage class
  storage_class = "scw-bssd"
  storage_size  = "50Gi"

  # Enable monitoring for production
  monitoring_enabled = local.monitoring_config.enable_monitoring

  # Workspace configuration
  workspace_traffic_policy = "subdomain"
  enable_terraform         = true

  # Production security settings (restricted)
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

  # Enhanced health checks for production
  health_check_config = {
    liveness_probe = {
      initial_delay_seconds = 120
      period_seconds        = 30
      timeout_seconds       = 10
      failure_threshold     = 3
    }
    readiness_probe = {
      initial_delay_seconds = 30
      period_seconds        = 10
      timeout_seconds       = 5
      failure_threshold     = 5
    }
  }

  # Ingress configuration based on domain setup
  ingress_enabled = local.domain_name != ""
  ingress_class   = "nginx"
  tls_enabled     = local.domain_name != ""

  # Production ingress annotations with security and performance optimizations
  ingress_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size"         = "0"
    "nginx.ingress.kubernetes.io/proxy-read-timeout"      = "86400"
    "nginx.ingress.kubernetes.io/proxy-send-timeout"      = "86400"
    "nginx.ingress.kubernetes.io/ssl-redirect"            = "true"
    "nginx.ingress.kubernetes.io/force-ssl-redirect"      = "true"
    "nginx.ingress.kubernetes.io/rate-limit"              = "200"
    "nginx.ingress.kubernetes.io/rate-limit-window"       = "1m"
    "nginx.ingress.kubernetes.io/rate-limit-rps"          = "5"
    "cert-manager.io/cluster-issuer"                      = "letsencrypt-prod"
    "nginx.ingress.kubernetes.io/proxy-buffer-size"       = "16k"
    "nginx.ingress.kubernetes.io/proxy-buffers"           = "8 16k"
    "nginx.ingress.kubernetes.io/enable-modsecurity"      = "true"
    "nginx.ingress.kubernetes.io/enable-owasp-core-rules" = "true"
  }

  # Production environment variables
  environment_variables = {
    "CODER_PROMETHEUS_ENABLE"              = "true"
    "CODER_PPROF_ENABLE"                   = "true"
    "CODER_VERBOSE"                        = "false"
    "CODER_SWAGGER_ENABLE"                 = "false"
    "CODER_RATE_LIMIT_API"                 = "512"
    "CODER_EXPERIMENTS"                    = "workspace_batch_actions,deployment_health_page"
    "CODER_MAX_SESSION_EXPIRY"             = "168h" # 7 days
    "CODER_DISABLE_SESSION_EXPIRY_REFRESH" = "false"
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
    "environment" = "prod"
    "backup"      = "required"
    "monitoring"  = "required"
  }
}