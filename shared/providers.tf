# Scaleway provider configuration
# Credentials are sourced from environment variables:
# SCW_ACCESS_KEY, SCW_SECRET_KEY, SCW_DEFAULT_PROJECT_ID
provider "scaleway" {
  zone   = var.scaleway_zone
  region = var.scaleway_region
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