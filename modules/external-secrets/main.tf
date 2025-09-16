terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

# Namespace for External Secrets Operator
resource "kubernetes_namespace" "external_secrets" {
  metadata {
    name = "external-secrets-system"

    labels = {
      "name"                               = "external-secrets-system"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "managed-by"                         = "terraform"
    }
  }
}

# External Secrets Operator Helm Release
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.chart_version
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name

  values = [
    yamlencode({
      installCRDs  = true
      replicaCount = var.replica_count

      resources = {
        limits = {
          cpu    = var.resources.limits.cpu
          memory = var.resources.limits.memory
        }
        requests = {
          cpu    = var.resources.requests.cpu
          memory = var.resources.requests.memory
        }
      }

      securityContext = {
        runAsNonRoot             = true
        runAsUser                = 65534
        runAsGroup               = 65534
        fsGroup                  = 65534
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = true
        seccompProfile = {
          type = "RuntimeDefault"
        }
        capabilities = {
          drop = ["ALL"]
        }
      }

      podSecurityContext = {
        runAsNonRoot = true
        runAsUser    = 65534
        runAsGroup   = 65534
        fsGroup      = 65534
        seccompProfile = {
          type = "RuntimeDefault"
        }
      }

      serviceMonitor = {
        enabled = var.monitoring_enabled
      }

      # Network policies
      networkPolicy = {
        enabled = var.enable_network_policy
      }

      # Pod disruption budget
      podDisruptionBudget = {
        enabled      = var.replica_count > 1
        minAvailable = 1
      }

      # Node selector and tolerations
      nodeSelector = var.node_selector
      tolerations  = var.tolerations
      affinity     = var.affinity
    })
  ]

  depends_on = [kubernetes_namespace.external_secrets]
}

# Scaleway credentials secret for External Secrets
resource "kubernetes_secret" "scaleway_credentials" {
  metadata {
    name      = "scaleway-credentials"
    namespace = var.target_namespace
  }

  data = {
    access-key = var.scaleway_access_key
    secret-key = var.scaleway_secret_key
  }

  type = "Opaque"
}

# SecretStore for Scaleway Secret Manager
resource "kubernetes_manifest" "scaleway_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = "scaleway-secret-store"
      namespace = var.target_namespace
    }
    spec = {
      provider = {
        scaleway = {
          region    = var.scaleway_region
          projectId = var.scaleway_project_id
          accessKey = {
            secretRef = {
              name = kubernetes_secret.scaleway_credentials.metadata[0].name
              key  = "access-key"
            }
          }
          secretKey = {
            secretRef = {
              name = kubernetes_secret.scaleway_credentials.metadata[0].name
              key  = "secret-key"
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.external_secrets,
    kubernetes_secret.scaleway_credentials
  ]
}

# Wait for External Secrets Operator to be ready
resource "kubernetes_manifest" "wait_for_eso" {
  manifest = {
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "eso-ready-check"
      namespace = var.target_namespace
    }
    data = {
      status = "external-secrets-operator-ready"
    }
  }

  depends_on = [kubernetes_manifest.scaleway_secret_store]

  wait {
    condition {
      type   = "Ready"
      status = "True"
    }
  }
}