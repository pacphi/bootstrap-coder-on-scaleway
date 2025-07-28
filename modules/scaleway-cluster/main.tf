terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
  }
}

# Kubernetes Cluster
resource "scaleway_k8s_cluster" "cluster" {
  name        = var.cluster_name
  description = var.cluster_description
  version     = var.cluster_version
  cni         = var.cni

  auto_upgrade {
    enable                        = var.auto_upgrade
    maintenance_window_start_hour = var.maintenance_window_start_hour
    maintenance_window_day        = var.maintenance_window_day
  }

  feature_gates       = var.feature_gates
  admission_plugins   = var.admission_plugins
  apiserver_cert_sans = var.apiserver_cert_sans

  dynamic "open_id_connect_config" {
    for_each = var.open_id_connect_config != null ? [var.open_id_connect_config] : []
    content {
      issuer_url      = open_id_connect_config.value.issuer_url
      client_id       = open_id_connect_config.value.client_id
      username_claim  = open_id_connect_config.value.username_claim
      username_prefix = open_id_connect_config.value.username_prefix
      groups_claim    = open_id_connect_config.value.groups_claim
      groups_prefix   = open_id_connect_config.value.groups_prefix
      required_claim  = open_id_connect_config.value.required_claim
    }
  }

  private_network_id = var.private_network_id

  delete_additional_resources = true

  tags = [for k, v in var.tags : "${k}:${v}"]
}

# Node Pools
resource "scaleway_k8s_pool" "pools" {
  for_each = { for pool in var.node_pools : pool.name => pool }

  cluster_id = scaleway_k8s_cluster.cluster.id
  name       = each.value.name
  node_type  = each.value.node_type
  size       = each.value.size

  min_size    = each.value.min_size
  max_size    = each.value.max_size
  autoscaling = each.value.autoscaling
  autohealing = each.value.autohealing

  container_runtime  = each.value.container_runtime
  placement_group_id = each.value.placement_group_id

  tags = each.value.tags

  kubelet_args = each.value.kubelet_args

  dynamic "upgrade_policy" {
    for_each = each.value.upgrade_policy != null ? [each.value.upgrade_policy] : []
    content {
      max_unavailable = upgrade_policy.value.max_unavailable
      max_surge       = upgrade_policy.value.max_surge
    }
  }

  zone = each.value.zone != null ? each.value.zone : var.zone

  root_volume_type = each.value.root_volume_type

  # Wait for cluster to be ready
  depends_on = [scaleway_k8s_cluster.cluster]
}

# Wait for cluster to be ready
resource "time_sleep" "wait_for_cluster" {
  depends_on = [
    scaleway_k8s_cluster.cluster,
    scaleway_k8s_pool.pools
  ]
  create_duration = "60s"
}

# Get cluster kubeconfig
data "scaleway_k8s_cluster" "cluster" {
  cluster_id = scaleway_k8s_cluster.cluster.id
  depends_on = [time_sleep.wait_for_cluster]
}