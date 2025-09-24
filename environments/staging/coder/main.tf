terraform {
  required_version = ">= 1.13.0"
}

# Local variables for coder deployment
# Note: data.terraform_remote_state.infra is defined in providers.tf
locals {
  environment  = "staging"
  project_name = "coder"

  # Get infrastructure outputs
  kubeconfig                 = data.terraform_remote_state.infra.outputs.kubeconfig
  access_url                 = data.terraform_remote_state.infra.outputs.access_url
  wildcard_access_url        = data.terraform_remote_state.infra.outputs.wildcard_access_url
  database_connection_string = data.terraform_remote_state.infra.outputs.database_connection_string

  monitoring_config = {
    enable_monitoring = true
  }

  # Domain configuration
  domain_name = "" # Configure your domain here
}

# Coder Deployment Module
module "coder_deployment" {
  source = "../../../modules/coder-deployment"

  namespace            = "coder"
  environment          = local.environment
  coder_version        = "2.6.0"
  database_url         = local.database_connection_string
  access_url           = local.access_url
  wildcard_access_url  = local.wildcard_access_url
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
}