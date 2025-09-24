output "coder_url" {
  description = "URL to access Coder"
  value       = var.access_url
}

output "wildcard_url" {
  description = "Wildcard URL for workspace access"
  value       = var.wildcard_access_url
}

output "admin_username" {
  description = "Admin username for initial login"
  value       = "admin"
}

output "admin_password" {
  description = "Admin password for initial login"
  value       = random_password.admin_password.result
  sensitive   = true
}

output "namespace" {
  description = "Kubernetes namespace where Coder is deployed"
  value       = var.namespace
}

output "service_name" {
  description = "Name of the Coder service"
  value       = kubernetes_service.coder.metadata[0].name
}

output "service_port" {
  description = "Port of the Coder service"
  value       = var.service_port
}

output "deployment_name" {
  description = "Name of the Coder deployment"
  value       = kubernetes_deployment.coder.metadata[0].name
}

output "deployment_status" {
  description = "Status of the Coder deployment"
  value = {
    replicas = kubernetes_deployment.coder.spec[0].replicas
  }
}

output "secrets" {
  description = "Names of created secrets"
  value = {
    database     = var.use_external_secrets ? null : kubernetes_secret.database_url[0].metadata[0].name
    admin        = var.use_external_secrets ? null : kubernetes_secret.admin_credentials[0].metadata[0].name
    oauth_github = var.oauth_config != null && var.oauth_config.github != null ? kubernetes_secret.oauth_github[0].metadata[0].name : null
    oauth_google = var.oauth_config != null && var.oauth_config.google != null ? kubernetes_secret.oauth_google[0].metadata[0].name : null
  }
}

output "configmap_name" {
  description = "Name of the Coder configuration ConfigMap"
  value       = kubernetes_config_map.coder_config.metadata[0].name
}

output "pvc_name" {
  description = "Name of the persistent volume claim"
  value       = kubernetes_persistent_volume_claim.coder_data.metadata[0].name
}

output "ingress_name" {
  description = "Name of the ingress resource"
  value       = var.ingress_enabled ? kubernetes_ingress_v1.coder[0].metadata[0].name : null
}

output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.monitoring_enabled
}

output "metrics_endpoint" {
  description = "Prometheus metrics endpoint"
  value       = var.monitoring_enabled ? "http://${kubernetes_service.coder.metadata[0].name}.${var.namespace}.svc.cluster.local:2112/metrics" : null
}

output "health_endpoints" {
  description = "Health check endpoints"
  value = {
    liveness  = "http://${kubernetes_service.coder.metadata[0].name}.${var.namespace}.svc.cluster.local:${var.service_port}/healthz"
    readiness = "http://${kubernetes_service.coder.metadata[0].name}.${var.namespace}.svc.cluster.local:${var.service_port}/healthz"
  }
}

output "resource_usage" {
  description = "Resource requests and limits"
  value = {
    requests = var.resources.requests
    limits   = var.resources.limits
  }
}

output "oauth_configuration" {
  description = "OAuth configuration status"
  value = {
    github_enabled = var.oauth_config != null && var.oauth_config.github != null
    google_enabled = var.oauth_config != null && var.oauth_config.google != null
  }
}

output "workspace_configuration" {
  description = "Workspace configuration"
  value = {
    traffic_policy    = var.workspace_traffic_policy
    terraform_enabled = var.enable_terraform
    docker_enabled    = var.enable_docker
  }
}

output "security_configuration" {
  description = "Security configuration applied"
  value = {
    run_as_non_root            = var.pod_security_context.run_as_non_root
    read_only_root_filesystem  = var.security_context.read_only_root_filesystem
    allow_privilege_escalation = var.security_context.allow_privilege_escalation
    capabilities_dropped       = var.security_context.capabilities.drop
  }
}

# CLI connection info
output "cli_connection_info" {
  description = "Information for connecting via Coder CLI"
  value = {
    url      = var.access_url
    username = "admin"
    password = random_password.admin_password.result
    commands = {
      login      = "coder login ${var.access_url}"
      templates  = "coder templates list"
      workspaces = "coder list"
    }
  }
  sensitive = true
}