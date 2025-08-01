terraform {
  required_version = ">= 1.12.0"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.48"
    }
  }

  # Backend configuration will be injected by CI/CD workflow
  # or can be configured manually for local development
}

provider "scaleway" {
  region = var.scaleway_region
  zone   = var.scaleway_zone
}