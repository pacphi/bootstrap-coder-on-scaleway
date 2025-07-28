output "cluster_id" {
  description = "ID of the Kubernetes cluster"
  value       = scaleway_k8s_cluster.cluster.id
}

output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = scaleway_k8s_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the Kubernetes cluster"
  value       = data.scaleway_k8s_cluster.cluster.apiserver_url
}

output "cluster_ca_certificate" {
  description = "CA certificate of the Kubernetes cluster"
  value       = data.scaleway_k8s_cluster.cluster.kubeconfig[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_token" {
  description = "Authentication token for the Kubernetes cluster"
  value       = data.scaleway_k8s_cluster.cluster.kubeconfig[0].token
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig for the Kubernetes cluster"
  value       = data.scaleway_k8s_cluster.cluster.kubeconfig[0].config_file
  sensitive   = true
}

output "cluster_status" {
  description = "Status of the Kubernetes cluster"
  value       = scaleway_k8s_cluster.cluster.status
}

output "cluster_upgrade_available" {
  description = "Whether an upgrade is available for the cluster"
  value       = scaleway_k8s_cluster.cluster.upgrade_available
}

output "cluster_version" {
  description = "Version of the Kubernetes cluster"
  value       = scaleway_k8s_cluster.cluster.version
}

output "wildcard_dns" {
  description = "Wildcard DNS for the cluster"
  value       = scaleway_k8s_cluster.cluster.wildcard_dns
}

output "node_pools" {
  description = "Information about node pools"
  value = {
    for name, pool in scaleway_k8s_pool.pools : name => {
      id                 = pool.id
      status             = pool.status
      nodes              = pool.nodes
      current_size       = pool.current_size
      public_ip_disabled = pool.public_ip_disabled
    }
  }
}

output "cluster_url" {
  description = "URL to access the cluster dashboard (if enabled)"
  value       = var.enable_dashboard ? "https://${data.scaleway_k8s_cluster.cluster.apiserver_url}/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/" : null
}