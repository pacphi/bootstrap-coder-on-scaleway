output "namespace" {
  description = "External Secrets Operator namespace"
  value       = kubernetes_namespace.external_secrets.metadata[0].name
}

output "secret_store_name" {
  description = "Name of the Scaleway SecretStore"
  value       = kubernetes_manifest.scaleway_secret_store.manifest.metadata.name
}

output "secret_store_namespace" {
  description = "Namespace of the Scaleway SecretStore"
  value       = kubernetes_manifest.scaleway_secret_store.manifest.metadata.namespace
}

output "helm_release_status" {
  description = "Status of External Secrets Operator Helm release"
  value       = helm_release.external_secrets.status
}

output "helm_release_version" {
  description = "Version of External Secrets Operator Helm release"
  value       = helm_release.external_secrets.version
}