terraform {
  required_version = ">= 1.12.0"
}

# Data sources to read infrastructure outputs
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket                      = "terraform-state-coder-prod"
    key                         = "infra/terraform.tfstate"
    region                      = var.scaleway_region
    endpoints = {
      s3 = "https://s3.${var.scaleway_region}.scw.cloud"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

# Local variables for coder deployment
locals {
  environment  = "prod"
  project_name = "coder"

  # Get infrastructure outputs
  kubeconfig              = data.terraform_remote_state.infra.outputs.kubeconfig
  access_url              = data.terraform_remote_state.infra.outputs.access_url
  wildcard_access_url     = data.terraform_remote_state.infra.outputs.wildcard_access_url
  database_connection_string = data.terraform_remote_state.infra.outputs.database_connection_string

  monitoring_config = {
    enable_monitoring = true
  }

  # Domain configuration
  domain_name = ""      # Configure your production domain here
}

# Coder Deployment Module - Production Configuration
module "coder_deployment" {
  source = "../../../modules/coder-deployment"

  namespace            = "coder"
  environment          = local.environment
  coder_version        = "2.6.0"
  database_url         = local.database_connection_string
  access_url           = local.access_url
  wildcard_access_url  = local.wildcard_access_url
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
}