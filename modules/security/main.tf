terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
  }
}

# Create namespaces with security labels
resource "kubernetes_namespace" "secured_namespaces" {
  for_each = toset(concat([var.namespace], var.additional_namespaces))

  metadata {
    name = each.value

    labels = merge({
      "name" = each.value
      "managed-by" = "terraform"
    }, var.enable_pod_security_standards ? {
      "pod-security.kubernetes.io/enforce" = var.pod_security_standard
      "pod-security.kubernetes.io/audit"   = var.pod_security_standard
      "pod-security.kubernetes.io/warn"    = var.pod_security_standard
    } : {})
  }
}

# Resource Quotas
resource "kubernetes_resource_quota" "namespace_quotas" {
  for_each = var.enable_rbac ? toset(concat([var.namespace], var.additional_namespaces)) : toset([])

  metadata {
    name      = "${each.value}-quota"
    namespace = kubernetes_namespace.secured_namespaces[each.value].metadata[0].name
  }

  spec {
    hard = var.resource_quotas.hard_limits
  }
}

# Service Account for Coder
resource "kubernetes_service_account" "coder" {
  count = var.enable_rbac ? 1 : 0

  metadata {
    name      = "coder"
    namespace = kubernetes_namespace.secured_namespaces[var.namespace].metadata[0].name

    labels = {
      "app.kubernetes.io/name"      = "coder"
      "app.kubernetes.io/component" = "server"
      "managed-by"                  = "terraform"
    }
  }

  automount_service_account_token = true
}

# ClusterRole for Coder
resource "kubernetes_cluster_role" "coder" {
  count = var.enable_rbac ? 1 : 0

  metadata {
    name = "coder"
    labels = {
      "app.kubernetes.io/name" = "coder"
      "managed-by"             = "terraform"
    }
  }

  # Permissions for managing workspaces
  rule {
    api_groups = [""]
    resources = [
      "pods",
      "pods/log",
      "pods/exec",
      "services",
      "persistentvolumeclaims",
      "secrets",
      "configmaps"
    ]
    verbs = ["*"]
  }

  rule {
    api_groups = ["apps"]
    resources = [
      "deployments",
      "replicasets"
    ]
    verbs = ["*"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources = ["ingresses", "networkpolicies"]
    verbs = ["*"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources = ["pods", "nodes"]
    verbs = ["get", "list"]
  }
}

# ClusterRoleBinding for Coder
resource "kubernetes_cluster_role_binding" "coder" {
  count = var.enable_rbac ? 1 : 0

  metadata {
    name = "coder"
    labels = {
      "app.kubernetes.io/name" = "coder"
      "managed-by"             = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.coder[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.coder[0].metadata[0].name
    namespace = kubernetes_service_account.coder[0].metadata[0].namespace
  }
}

# Default deny-all network policy
resource "kubernetes_network_policy" "deny_all" {
  for_each = var.enable_network_policies ? toset(concat([var.namespace], var.additional_namespaces)) : toset([])

  metadata {
    name      = "deny-all"
    namespace = kubernetes_namespace.secured_namespaces[each.value].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# Allow DNS resolution network policy
resource "kubernetes_network_policy" "allow_dns" {
  for_each = var.enable_network_policies ? toset(concat([var.namespace], var.additional_namespaces)) : toset([])

  metadata {
    name      = "allow-dns"
    namespace = kubernetes_namespace.secured_namespaces[each.value].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
  }
}

# Allow Coder server communication
resource "kubernetes_network_policy" "allow_coder_server" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-coder-server"
    namespace = kubernetes_namespace.secured_namespaces[var.namespace].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "coder"
      }
    }
    policy_types = ["Ingress", "Egress"]

    # Allow ingress from load balancer and within namespace
    ingress {
      from {
        pod_selector {}
      }
      ports {
        protocol = "TCP"
        port     = "7080"
      }
    }

    # Allow egress to database and internet
    egress {
      to {}  # Allow all egress for Coder server
    }
  }
}

# Allow workspace communication
resource "kubernetes_network_policy" "allow_workspace_communication" {
  count = var.enable_network_policies ? 1 : 0

  metadata {
    name      = "allow-workspace-communication"
    namespace = kubernetes_namespace.secured_namespaces[var.namespace].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "workspace"
      }
    }
    policy_types = ["Ingress", "Egress"]

    # Allow ingress from Coder server and other workspaces
    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "coder"
          }
        }
      }
    }

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/component" = "workspace"
          }
        }
      }
    }

    # Allow egress to internet (for package downloads, etc.)
    egress {
      to {}
    }
  }
}

# Custom network policies
resource "kubernetes_network_policy" "custom_policies" {
  for_each = { for policy in var.network_policy_rules : policy.name => policy }

  metadata {
    name      = each.value.name
    namespace = kubernetes_namespace.secured_namespaces[each.value.namespace].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = each.value.pod_selector
    }

    policy_types = concat(
      each.value.ingress != null ? ["Ingress"] : [],
      each.value.egress != null ? ["Egress"] : []
    )

    dynamic "ingress" {
      for_each = each.value.ingress != null ? each.value.ingress : []
      content {
        dynamic "from" {
          for_each = ingress.value.from != null ? ingress.value.from : []
          content {
            dynamic "pod_selector" {
              for_each = from.value.pod_selector != null ? [from.value.pod_selector] : []
              content {
                match_labels = pod_selector.value
              }
            }

            dynamic "namespace_selector" {
              for_each = from.value.namespace_selector != null ? [from.value.namespace_selector] : []
              content {
                match_labels = namespace_selector.value
              }
            }

            dynamic "ip_block" {
              for_each = from.value.ip_block != null ? [from.value.ip_block] : []
              content {
                cidr   = ip_block.value.cidr
                except = ip_block.value.except
              }
            }
          }
        }

        dynamic "ports" {
          for_each = ingress.value.ports != null ? ingress.value.ports : []
          content {
            protocol = ports.value.protocol
            port     = ports.value.port
          }
        }
      }
    }

    dynamic "egress" {
      for_each = each.value.egress != null ? each.value.egress : []
      content {
        dynamic "to" {
          for_each = egress.value.to != null ? egress.value.to : []
          content {
            dynamic "pod_selector" {
              for_each = to.value.pod_selector != null ? [to.value.pod_selector] : []
              content {
                match_labels = pod_selector.value
              }
            }

            dynamic "namespace_selector" {
              for_each = to.value.namespace_selector != null ? [to.value.namespace_selector] : []
              content {
                match_labels = namespace_selector.value
              }
            }

            dynamic "ip_block" {
              for_each = to.value.ip_block != null ? [to.value.ip_block] : []
              content {
                cidr   = ip_block.value.cidr
                except = ip_block.value.except
              }
            }
          }
        }

        dynamic "ports" {
          for_each = egress.value.ports != null ? egress.value.ports : []
          content {
            protocol = ports.value.protocol
            port     = ports.value.port
          }
        }
      }
    }
  }
}