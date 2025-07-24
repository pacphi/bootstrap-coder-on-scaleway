terraform {
  required_version = ">= 1.12.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}