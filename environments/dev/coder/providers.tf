terraform {
  required_version = ">= 1.13.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Backend configuration will be injected by CI/CD workflow
  # or can be configured manually for local development
}

# Data source to read infrastructure state for cluster connection
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

provider "kubernetes" {
  host                   = data.terraform_remote_state.infra.outputs.cluster_endpoint
  token                  = data.terraform_remote_state.infra.outputs.cluster_token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.infra.outputs.cluster_endpoint
    token                  = data.terraform_remote_state.infra.outputs.cluster_token
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.cluster_ca_certificate)
  }
}