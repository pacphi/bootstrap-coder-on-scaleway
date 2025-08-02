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


# Configure Kubernetes provider using kubeconfig from infrastructure
provider "kubernetes" {
  # Use the kubeconfig content directly from remote state
  config_raw = data.terraform_remote_state.infra.outputs.kubeconfig
}

provider "helm" {
  kubernetes {
    # Use the kubeconfig content directly from remote state
    config_raw = data.terraform_remote_state.infra.outputs.kubeconfig
  }
}