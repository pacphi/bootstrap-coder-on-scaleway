terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.34"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}

provider "scaleway" {
  zone            = var.scaleway_zone
  region          = var.scaleway_region
  organization_id = var.scaleway_organization_id
  project_id      = var.scaleway_project_id
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