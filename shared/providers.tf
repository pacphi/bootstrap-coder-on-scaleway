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