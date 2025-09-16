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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# Generate random admin password
resource "random_password" "admin_password" {
  length  = 32
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Create secret for database connection
resource "kubernetes_secret" "database_url" {
  metadata {
    name      = "coder-database"
    namespace = var.namespace
  }

  data = {
    url = var.database_url
  }

  type = "Opaque"
}

# Create secret for admin credentials
resource "kubernetes_secret" "admin_credentials" {
  metadata {
    name      = "coder-admin"
    namespace = var.namespace
  }

  data = {
    username = "admin"
    password = random_password.admin_password.result
  }

  type = "Opaque"
}

# OAuth secrets (conditional)
resource "kubernetes_secret" "oauth_github" {
  count = var.oauth_config != null && var.oauth_config.github != null ? 1 : 0

  metadata {
    name      = "coder-oauth-github"
    namespace = var.namespace
  }

  data = {
    client_id     = var.oauth_config.github.client_id
    client_secret = var.oauth_config.github.client_secret
  }

  type = "Opaque"
}

resource "kubernetes_secret" "oauth_google" {
  count = var.oauth_config != null && var.oauth_config.google != null ? 1 : 0

  metadata {
    name      = "coder-oauth-google"
    namespace = var.namespace
  }

  data = {
    client_id     = var.oauth_config.google.client_id
    client_secret = var.oauth_config.google.client_secret
  }

  type = "Opaque"
}

# ConfigMap for Coder configuration
resource "kubernetes_config_map" "coder_config" {
  metadata {
    name      = "coder-config"
    namespace = var.namespace
  }

  data = {
    "coder.yaml" = yamlencode({
      accessURL         = var.access_url
      wildcardAccessURL = var.wildcard_access_url != "" ? var.wildcard_access_url : null
      httpAddress       = "0.0.0.0:${var.container_port}"
      prometheusAddress = var.monitoring_enabled ? "0.0.0.0:2112" : null
      pprofAddress      = "0.0.0.0:6060"

      # Workspace configuration
      workspaceTrafficPolicy = var.workspace_traffic_policy

      # Template providers
      terraform = var.enable_terraform ? {
        enabled = true
      } : null

      # Security
      secureAuthCookie        = true
      strictTransportSecurity = 31536000

      # Telemetry
      telemetry = {
        enable = false
      }

      # Logging
      logging = {
        human  = "/dev/stdout"
        json   = false
        filter = ["INFO"]
      }

      # OAuth configuration
      oauth2 = var.oauth_config != null ? {
        github = var.oauth_config.github != null ? {
          clientID      = var.oauth_config.github.client_id
          allowSignups  = var.oauth_config.github.allow_signups
          allowEveryone = var.oauth_config.github.allow_everyone
          allowedOrgs   = var.oauth_config.github.allowed_orgs
          allowedTeams  = var.oauth_config.github.allowed_teams
        } : null
        google = var.oauth_config.google != null ? {
          clientID     = var.oauth_config.google.client_id
          allowSignups = var.oauth_config.google.allow_signups
        } : null
      } : null
    })
  }
}

# Persistent Volume Claim for Coder data
resource "kubernetes_persistent_volume_claim" "coder_data" {
  metadata {
    name      = "coder-data"
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    # Use the specified storage class directly
    storage_class_name = var.storage_class

    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }
}

# Deployment for Coder
resource "kubernetes_deployment" "coder" {
  metadata {
    name      = "coder"
    namespace = var.namespace

    labels = merge({
      "app.kubernetes.io/name"      = "coder"
      "app.kubernetes.io/component" = "server"
      "app.kubernetes.io/version"   = var.coder_version
    }, var.tags)
  }

  spec {
    replicas = var.replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name"      = "coder"
        "app.kubernetes.io/component" = "server"
      }
    }

    template {
      metadata {
        labels = merge({
          "app.kubernetes.io/name"      = "coder"
          "app.kubernetes.io/component" = "server"
          "app.kubernetes.io/version"   = var.coder_version
        }, var.tags)

        annotations = {
          "prometheus.io/scrape" = var.monitoring_enabled ? "true" : "false"
          "prometheus.io/port"   = "2112"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name            = var.service_account_name
        automount_service_account_token = true

        security_context {
          run_as_non_root = var.pod_security_context.run_as_non_root
          run_as_user     = var.pod_security_context.run_as_user
          run_as_group    = var.pod_security_context.run_as_group
          fs_group        = var.pod_security_context.fs_group
        }

        container {
          name  = "coder"
          image = "${var.coder_image}:v${var.coder_version}"

          port {
            name           = "http"
            container_port = var.container_port
            protocol       = "TCP"
          }

          dynamic "port" {
            for_each = var.monitoring_enabled ? [1] : []
            content {
              name           = "metrics"
              container_port = 2112
              protocol       = "TCP"
            }
          }

          env {
            name = "CODER_PG_CONNECTION_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.database_url.metadata[0].name
                key  = "url"
              }
            }
          }

          env {
            name = "CODER_FIRST_USER_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.admin_credentials.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "CODER_FIRST_USER_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.admin_credentials.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "CODER_FIRST_USER_TRIAL"
            value = "true"
          }

          # OAuth environment variables
          dynamic "env" {
            for_each = var.oauth_config != null && var.oauth_config.github != null ? [1] : []
            content {
              name = "CODER_OAUTH2_GITHUB_CLIENT_SECRET"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.oauth_github[0].metadata[0].name
                  key  = "client_secret"
                }
              }
            }
          }

          dynamic "env" {
            for_each = var.oauth_config != null && var.oauth_config.google != null ? [1] : []
            content {
              name = "CODER_OAUTH2_GOOGLE_CLIENT_SECRET"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.oauth_google[0].metadata[0].name
                  key  = "client_secret"
                }
              }
            }
          }

          # Additional environment variables
          dynamic "env" {
            for_each = var.environment_variables
            content {
              name  = env.key
              value = env.value
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/coder"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/coder"
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          args = [
            "server",
            "--config", "/etc/coder/coder.yaml"
          ]

          resources {
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
          }

          security_context {
            allow_privilege_escalation = var.security_context.allow_privilege_escalation
            run_as_non_root            = var.security_context.run_as_non_root
            run_as_user                = var.security_context.run_as_user
            read_only_root_filesystem  = var.security_context.read_only_root_filesystem

            capabilities {
              drop = var.security_context.capabilities.drop
            }

            seccomp_profile {
              type = var.security_context.seccomp_profile.type
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = var.container_port
            }
            initial_delay_seconds = var.health_check_config.liveness_probe.initial_delay_seconds
            period_seconds        = var.health_check_config.liveness_probe.period_seconds
            timeout_seconds       = var.health_check_config.liveness_probe.timeout_seconds
            failure_threshold     = var.health_check_config.liveness_probe.failure_threshold
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = var.container_port
            }
            initial_delay_seconds = var.health_check_config.readiness_probe.initial_delay_seconds
            period_seconds        = var.health_check_config.readiness_probe.period_seconds
            timeout_seconds       = var.health_check_config.readiness_probe.timeout_seconds
            failure_threshold     = var.health_check_config.readiness_probe.failure_threshold
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.coder_config.metadata[0].name
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.coder_data.metadata[0].name
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.database_url,
    kubernetes_secret.admin_credentials,
    kubernetes_config_map.coder_config,
    kubernetes_persistent_volume_claim.coder_data
  ]
}

# Service for Coder
resource "kubernetes_service" "coder" {
  metadata {
    name      = "coder"
    namespace = var.namespace

    labels = merge({
      "app.kubernetes.io/name"      = "coder"
      "app.kubernetes.io/component" = "server"
    }, var.tags)

    annotations = var.monitoring_enabled ? {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "2112"
      "prometheus.io/path"   = "/metrics"
    } : {}
  }

  spec {
    type = var.service_type

    selector = {
      "app.kubernetes.io/name"      = "coder"
      "app.kubernetes.io/component" = "server"
    }

    port {
      name        = "http"
      port        = var.service_port
      target_port = var.container_port
      protocol    = "TCP"
    }

    dynamic "port" {
      for_each = var.monitoring_enabled ? [1] : []
      content {
        name        = "metrics"
        port        = 2112
        target_port = 2112
        protocol    = "TCP"
      }
    }
  }
}

# Ingress for Coder (conditional)
resource "kubernetes_ingress_v1" "coder" {
  count = var.ingress_enabled ? 1 : 0

  metadata {
    name      = "coder"
    namespace = var.namespace

    labels = merge({
      "app.kubernetes.io/name"      = "coder"
      "app.kubernetes.io/component" = "ingress"
    }, var.tags)

    annotations = var.ingress_annotations
  }

  spec {
    ingress_class_name = var.ingress_class

    dynamic "tls" {
      for_each = var.tls_enabled ? [1] : []
      content {
        hosts       = [replace(var.access_url, "https://", "")]
        secret_name = var.tls_secret_name != "" ? var.tls_secret_name : "coder-tls"
      }
    }

    rule {
      host = replace(var.access_url, "https://", "")

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.coder.metadata[0].name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }

    # Wildcard rule for workspaces
    dynamic "rule" {
      for_each = var.wildcard_access_url != "" && var.workspace_traffic_policy == "subdomain" ? [1] : []
      content {
        host = replace(var.wildcard_access_url, "https://", "")

        http {
          path {
            path      = "/"
            path_type = "Prefix"

            backend {
              service {
                name = kubernetes_service.coder.metadata[0].name
                port {
                  number = var.service_port
                }
              }
            }
          }
        }
      }
    }
  }
}