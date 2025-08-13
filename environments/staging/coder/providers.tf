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


provider "kubernetes" {
  host                   = module.scaleway_cluster.cluster_endpoint
  token                  = module.scaleway_cluster.cluster_token
  cluster_ca_certificate = base64decode(module.scaleway_cluster.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.scaleway_cluster.cluster_endpoint
    token                  = module.scaleway_cluster.cluster_token
    cluster_ca_certificate = base64decode(module.scaleway_cluster.cluster_ca_certificate)
  }
}