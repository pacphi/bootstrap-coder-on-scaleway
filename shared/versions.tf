terraform {
  required_version = ">= 1.13.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }

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

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }
}