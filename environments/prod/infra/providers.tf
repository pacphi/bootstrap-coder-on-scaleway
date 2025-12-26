terraform {
  required_version = ">= 1.13.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.48"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # Backend configuration will be injected by CI/CD workflow
  # or can be configured manually for local development
}

provider "scaleway" {
  region = var.scaleway_region
  zone   = var.scaleway_zone
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