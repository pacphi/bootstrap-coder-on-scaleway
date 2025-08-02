terraform {
  required_version = ">= 1.12.0"
}

# Data sources to read infrastructure outputs
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "terraform-state-coder-dev"
    key    = "infra/terraform.tfstate"
    region = var.scaleway_region
    endpoints = {
      s3 = "https://s3.${var.scaleway_region}.scw.cloud"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}

# Local variables for coder deployment
locals {
  environment  = "dev"
  project_name = "coder"

  # Get infrastructure outputs
  kubeconfig                 = data.terraform_remote_state.infra.outputs.kubeconfig
  access_url                 = data.terraform_remote_state.infra.outputs.access_url
  wildcard_access_url        = data.terraform_remote_state.infra.outputs.wildcard_access_url
  database_connection_string = data.terraform_remote_state.infra.outputs.database_connection_string

  monitoring_config = {
    enable_monitoring = false
  }

  # Domain configuration
  domain_name = "" # Use IP-based access for dev
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

  # Development-specific resource limits
  resources = {
    limits = {
      cpu    = "1000m"
      memory = "2Gi"
    }
    requests = {
      cpu    = "250m"
      memory = "512Mi"
    }
  }

  # Storage configuration - use scw-bssd storage class
  storage_class = "scw-bssd"
  storage_size  = "5Gi"

  # Enable monitoring for development
  monitoring_enabled = local.monitoring_config.enable_monitoring

  # Workspace configuration
  workspace_traffic_policy = "subdomain"
  enable_terraform         = true

  # Ingress configuration based on domain setup
  ingress_enabled = local.domain_name != ""
  ingress_class   = "nginx"
  tls_enabled     = local.domain_name != ""

  tags = merge(var.tags, {
    Environment = local.environment
  })
}