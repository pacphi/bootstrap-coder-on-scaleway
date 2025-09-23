output "coder_namespace" {
  description = "Name of the Coder namespace"
  value       = var.namespace
}

output "secured_namespaces" {
  description = "List of secured namespaces"
  value       = [for ns in kubernetes_namespace.secured_namespaces : ns.metadata[0].name]
}

output "coder_service_account_name" {
  description = "Name of the Coder service account"
  value       = var.enable_rbac ? kubernetes_service_account.coder[0].metadata[0].name : null
}

output "coder_cluster_role_name" {
  description = "Name of the Coder cluster role"
  value       = var.enable_legacy_rbac ? kubernetes_cluster_role.coder_legacy[0].metadata[0].name : null
}

output "resource_quotas" {
  description = "Resource quotas applied to namespaces"
  value = {
    for quota in kubernetes_resource_quota.namespace_quotas : quota.metadata[0].namespace => {
      name        = quota.metadata[0].name
      hard_limits = quota.spec[0].hard
    }
  }
}

output "network_policies" {
  description = "Network policies created"
  value = merge(
    {
      for policy in kubernetes_network_policy.deny_all : "${policy.metadata[0].namespace}-deny-all" => {
        name      = policy.metadata[0].name
        namespace = policy.metadata[0].namespace
      }
    },
    {
      for policy in kubernetes_network_policy.allow_dns : "${policy.metadata[0].namespace}-allow-dns" => {
        name      = policy.metadata[0].name
        namespace = policy.metadata[0].namespace
      }
    },
    var.enable_network_policies ? {
      "coder-server" = {
        name      = kubernetes_network_policy.allow_coder_server[0].metadata[0].name
        namespace = kubernetes_network_policy.allow_coder_server[0].metadata[0].namespace
      },
      "workspace-communication" = {
        name      = kubernetes_network_policy.allow_workspace_communication[0].metadata[0].name
        namespace = kubernetes_network_policy.allow_workspace_communication[0].metadata[0].namespace
      }
    } : {},
    {
      for name, policy in kubernetes_network_policy.custom_policies : name => {
        name      = policy.metadata[0].name
        namespace = policy.metadata[0].namespace
      }
    }
  )
}

output "pod_security_standard" {
  description = "Pod Security Standard level applied"
  value       = var.enable_pod_security_standards ? var.pod_security_standard : null
}

output "security_configuration" {
  description = "Summary of security configuration"
  value = {
    pod_security_standards_enabled = var.enable_pod_security_standards
    pod_security_standard          = var.pod_security_standard
    network_policies_enabled       = var.enable_network_policies
    rbac_enabled                   = var.enable_rbac
    secured_namespaces_count       = length(concat([var.namespace], var.additional_namespaces))
  }
}