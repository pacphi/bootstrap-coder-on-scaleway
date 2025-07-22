output "vpc_id" {
  description = "ID of the VPC"
  value       = scaleway_vpc.main.id
}

output "private_network_id" {
  description = "ID of the private network"
  value       = scaleway_vpc_private_network.private_network.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = scaleway_instance_security_group.kubernetes.id
}

output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = var.enable_load_balancer ? scaleway_lb.main[0].id : null
}

output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value       = var.enable_load_balancer ? scaleway_lb_ip.main[0].ip_address : null
}

output "load_balancer_hostname" {
  description = "Hostname of the load balancer"
  value       = var.enable_load_balancer ? scaleway_lb_ip.main[0].lb_id : null
}

output "ssl_certificate_id" {
  description = "ID of the SSL certificate"
  value       = var.enable_load_balancer && var.domain_name != "" ? scaleway_lb_certificate.main[0].id : null
}

output "public_gateway_id" {
  description = "ID of the public gateway"
  value       = scaleway_vpc_public_gateway.main.id
}

output "public_gateway_ip" {
  description = "IP address of the public gateway"
  value       = scaleway_vpc_public_gateway_ip.main.address
}

output "backend_ids" {
  description = "IDs of the load balancer backends"
  value = var.enable_load_balancer ? {
    http  = scaleway_lb_backend.http[0].id
    https = scaleway_lb_backend.https[0].id
  } : null
}

output "frontend_ids" {
  description = "IDs of the load balancer frontends"
  value = var.enable_load_balancer ? {
    http  = scaleway_lb_frontend.http[0].id
    https = scaleway_lb_frontend.https[0].id
  } : null
}

output "access_url" {
  description = "Access URL for the service"
  value = var.enable_load_balancer ? (
    var.domain_name != "" ? (
      var.subdomain != "" ?
        "https://${var.subdomain}.${var.domain_name}" :
        "https://${var.domain_name}"
    ) :
    "https://${scaleway_lb_ip.main[0].ip_address}"
  ) : null
}

output "wildcard_access_url" {
  description = "Wildcard access URL for workspaces"
  value = var.enable_load_balancer ? (
    var.domain_name != "" ? (
      var.subdomain != "" ?
        "https://*.${var.subdomain}.${var.domain_name}" :
        "https://*.${var.domain_name}"
    ) :
    "https://*.${scaleway_lb_ip.main[0].ip_address}.nip.io"
  ) : null
}