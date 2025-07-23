terraform {
  required_version = ">= 1.12.0"

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

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
  }
}