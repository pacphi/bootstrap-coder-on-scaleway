terraform {
  required_version = ">= 1.12.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
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

# Data source to get kubeconfig from infrastructure state
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "terraform-state-coder-staging"
    key    = "infra/terraform.tfstate"
    region = var.scaleway_region
    endpoints = {
      s3 = "https://s3.${var.scaleway_region}.scw.cloud"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}

# Configure Kubernetes provider using kubeconfig from infrastructure
provider "kubernetes" {
  config_path = "${path.module}/kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "${path.module}/kubeconfig"
  }
}

# Write kubeconfig to file for providers
resource "local_file" "kubeconfig" {
  content  = data.terraform_remote_state.infra.outputs.kubeconfig
  filename = "${path.module}/kubeconfig"
}