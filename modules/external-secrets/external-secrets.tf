# External Secret for Database Credentials
resource "kubernetes_manifest" "database_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "database-credentials"
      namespace = var.target_namespace
      labels = {
        "app.kubernetes.io/name"      = "coder"
        "app.kubernetes.io/component" = "database"
        "managed-by"                  = "terraform"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "SecretStore"
        name = kubernetes_manifest.scaleway_secret_store.manifest.metadata.name
      }
      target = {
        name = "database-credentials"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = {
            "POSTGRES_HOST"     = "{{ .host }}"
            "POSTGRES_PORT"     = "{{ .port }}"
            "POSTGRES_USER"     = "{{ .username }}"
            "POSTGRES_PASSWORD" = "{{ .password }}"
            "POSTGRES_DB"       = "{{ .database }}"
            "POSTGRES_SSLMODE"  = "{{ .ssl_mode }}"
            "DATABASE_URL"      = "postgres://{{ .username }}:{{ .password }}@{{ .host }}:{{ .port }}/{{ .database }}?sslmode={{ .ssl_mode }}"
          }
        }
      }
      data = [
        {
          secretKey = "host"
          remoteRef = {
            key      = var.database_secret_name
            property = "host"
          }
        },
        {
          secretKey = "port"
          remoteRef = {
            key      = var.database_secret_name
            property = "port"
          }
        },
        {
          secretKey = "username"
          remoteRef = {
            key      = var.database_secret_name
            property = "username"
          }
        },
        {
          secretKey = "password"
          remoteRef = {
            key      = var.database_secret_name
            property = "password"
          }
        },
        {
          secretKey = "database"
          remoteRef = {
            key      = var.database_secret_name
            property = "database"
          }
        },
        {
          secretKey = "ssl_mode"
          remoteRef = {
            key      = var.database_secret_name
            property = "ssl_mode"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.scaleway_secret_store]
}

# External Secret for Admin Credentials
resource "kubernetes_manifest" "admin_external_secret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "admin-credentials"
      namespace = var.target_namespace
      labels = {
        "app.kubernetes.io/name"      = "coder"
        "app.kubernetes.io/component" = "admin"
        "managed-by"                  = "terraform"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "SecretStore"
        name = kubernetes_manifest.scaleway_secret_store.manifest.metadata.name
      }
      target = {
        name = "admin-credentials"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = {
            "CODER_FIRST_USER_USERNAME" = "{{ .username }}"
            "CODER_FIRST_USER_PASSWORD" = "{{ .password }}"
            "CODER_FIRST_USER_EMAIL"    = "{{ .email }}"
          }
        }
      }
      data = [
        {
          secretKey = "username"
          remoteRef = {
            key      = var.admin_secret_name
            property = "username"
          }
        },
        {
          secretKey = "password"
          remoteRef = {
            key      = var.admin_secret_name
            property = "password"
          }
        },
        {
          secretKey = "email"
          remoteRef = {
            key      = var.admin_secret_name
            property = "email"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.scaleway_secret_store]
}

# External Secret for OAuth GitHub (conditional)
resource "kubernetes_manifest" "oauth_github_external_secret" {
  count = var.oauth_github_secret_name != "" ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "oauth-github-credentials"
      namespace = var.target_namespace
      labels = {
        "app.kubernetes.io/name"      = "coder"
        "app.kubernetes.io/component" = "oauth"
        "oauth.provider"              = "github"
        "managed-by"                  = "terraform"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "SecretStore"
        name = kubernetes_manifest.scaleway_secret_store.manifest.metadata.name
      }
      target = {
        name = "oauth-github-credentials"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = {
            "CODER_OAUTH2_GITHUB_CLIENT_ID"     = "{{ .client_id }}"
            "CODER_OAUTH2_GITHUB_CLIENT_SECRET" = "{{ .client_secret }}"
          }
        }
      }
      data = [
        {
          secretKey = "client_id"
          remoteRef = {
            key      = var.oauth_github_secret_name
            property = "client_id"
          }
        },
        {
          secretKey = "client_secret"
          remoteRef = {
            key      = var.oauth_github_secret_name
            property = "client_secret"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.scaleway_secret_store]
}

# External Secret for OAuth Google (conditional)
resource "kubernetes_manifest" "oauth_google_external_secret" {
  count = var.oauth_google_secret_name != "" ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "oauth-google-credentials"
      namespace = var.target_namespace
      labels = {
        "app.kubernetes.io/name"      = "coder"
        "app.kubernetes.io/component" = "oauth"
        "oauth.provider"              = "google"
        "managed-by"                  = "terraform"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "SecretStore"
        name = kubernetes_manifest.scaleway_secret_store.manifest.metadata.name
      }
      target = {
        name = "oauth-google-credentials"
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = {
            "CODER_OAUTH2_GOOGLE_CLIENT_ID"     = "{{ .client_id }}"
            "CODER_OAUTH2_GOOGLE_CLIENT_SECRET" = "{{ .client_secret }}"
          }
        }
      }
      data = [
        {
          secretKey = "client_id"
          remoteRef = {
            key      = var.oauth_google_secret_name
            property = "client_id"
          }
        },
        {
          secretKey = "client_secret"
          remoteRef = {
            key      = var.oauth_google_secret_name
            property = "client_secret"
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.scaleway_secret_store]
}

# Additional application secrets
resource "kubernetes_manifest" "additional_external_secrets" {
  for_each = var.additional_secret_mappings

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = each.key
      namespace = var.target_namespace
      labels = merge({
        "app.kubernetes.io/name"      = "coder"
        "app.kubernetes.io/component" = "application"
        "managed-by"                  = "terraform"
      }, each.value.labels)
    }
    spec = {
      refreshInterval = each.value.refresh_interval
      secretStoreRef = {
        kind = "SecretStore"
        name = kubernetes_manifest.scaleway_secret_store.manifest.metadata.name
      }
      target = {
        name = each.value.target_secret_name
        creationPolicy = "Owner"
        template = {
          type = "Opaque"
          data = each.value.template_data
        }
      }
      data = each.value.data_mappings
    }
  }

  depends_on = [kubernetes_manifest.scaleway_secret_store]
}