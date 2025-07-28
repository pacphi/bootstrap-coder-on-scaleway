terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
  }
}

# VPC
resource "scaleway_vpc" "main" {
  name = var.vpc_name
  tags = var.tags
}

# Private Network
resource "scaleway_vpc_private_network" "private_network" {
  vpc_id = scaleway_vpc.main.id
  name   = var.private_network_name
  tags   = var.tags
}

# Security Group for Kubernetes cluster
resource "scaleway_instance_security_group" "kubernetes" {
  name = "${var.vpc_name}-kubernetes-sg"

  # Allow all internal communication within VPC
  inbound_rule {
    action   = "accept"
    protocol = "ANY"
    ip_range = "10.0.0.0/8"
  }

  # Allow HTTPS from anywhere (for Coder web interface)
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 443
    ip_range = "0.0.0.0/0"
  }

  # Allow HTTP from anywhere (for HTTP to HTTPS redirect)
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 80
    ip_range = "0.0.0.0/0"
  }

  # Allow SSH from anywhere (for debugging)
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 22
    ip_range = "0.0.0.0/0"
  }

  # Allow Kubernetes API server
  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 6443
    ip_range = "0.0.0.0/0"
  }

  # Allow NodePort services (30000-32767)
  inbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "30000-32767"
    ip_range   = "0.0.0.0/0"
  }

  # Custom security group rules
  dynamic "inbound_rule" {
    for_each = [for rule in var.security_group_rules : rule if rule.direction == "inbound"]
    content {
      action     = inbound_rule.value.action
      protocol   = inbound_rule.value.protocol
      port       = inbound_rule.value.port
      port_range = inbound_rule.value.port_range
      ip_range   = inbound_rule.value.ip_range
    }
  }

  # Allow all outbound traffic
  outbound_rule {
    action   = "accept"
    protocol = "ANY"
    ip_range = "0.0.0.0/0"
  }

  # Custom outbound security group rules
  dynamic "outbound_rule" {
    for_each = [for rule in var.security_group_rules : rule if rule.direction == "outbound"]
    content {
      action     = outbound_rule.value.action
      protocol   = outbound_rule.value.protocol
      port       = outbound_rule.value.port
      port_range = outbound_rule.value.port_range
      ip_range   = outbound_rule.value.ip_range
    }
  }

  tags = var.tags
}

# Load Balancer (conditional)
resource "scaleway_lb" "main" {
  count = var.enable_load_balancer ? 1 : 0

  name = var.load_balancer_name != "" ? var.load_balancer_name : "${var.vpc_name}-lb"
  type = var.load_balancer_type

  ssl_compatibility_level = var.ssl_compatibility_level

  private_network {
    private_network_id = scaleway_vpc_private_network.private_network.id
    dhcp_config        = true
  }

  tags = var.tags
}

# Load Balancer IP
resource "scaleway_lb_ip" "main" {
  count = var.enable_load_balancer ? 1 : 0

  # lb_id removed - IP is automatically associated with the load balancer
}

# SSL Certificate (if domain is provided)
resource "scaleway_lb_certificate" "main" {
  count = var.enable_load_balancer && var.domain_name != "" ? 1 : 0

  lb_id = scaleway_lb.main[0].id
  name  = "${var.vpc_name}-ssl-cert"

  letsencrypt {
    common_name = var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name
  }
}

# Load Balancer Backend for HTTP
resource "scaleway_lb_backend" "http" {
  count = var.enable_load_balancer ? 1 : 0

  lb_id            = scaleway_lb.main[0].id
  name             = "http-backend"
  forward_protocol = "http"
  forward_port     = 80

  health_check_http {
    uri    = "/healthz"
    method = "GET"
  }

  server_ips = [] # Will be populated by the cluster module
}

# Load Balancer Backend for HTTPS
resource "scaleway_lb_backend" "https" {
  count = var.enable_load_balancer ? 1 : 0

  lb_id            = scaleway_lb.main[0].id
  name             = "https-backend"
  forward_protocol = "http"
  forward_port     = 80

  health_check_http {
    uri    = "/healthz"
    method = "GET"
  }

  server_ips = [] # Will be populated by the cluster module
}

# Load Balancer Frontend for HTTP (redirect to HTTPS)
resource "scaleway_lb_frontend" "http" {
  count = var.enable_load_balancer ? 1 : 0

  lb_id        = scaleway_lb.main[0].id
  backend_id   = scaleway_lb_backend.http[0].id
  name         = "http-frontend"
  inbound_port = 80

  # Redirect HTTP to HTTPS
  acl {
    action {
      type = "redirect"
      redirect {
        type = "scheme"
        # scheme removed - type="scheme" already indicates HTTPS redirect
        code = 301
      }
    }
    match {
      http_filter       = "path_begin"
      http_filter_value = ["/"]
    }
  }
}

# Load Balancer Frontend for HTTPS
resource "scaleway_lb_frontend" "https" {
  count = var.enable_load_balancer ? 1 : 0

  lb_id           = scaleway_lb.main[0].id
  backend_id      = scaleway_lb_backend.https[0].id
  name            = "https-frontend"
  inbound_port    = 443
  certificate_ids = var.domain_name != "" ? [scaleway_lb_certificate.main[0].id] : []
}

# Gateway IP (create first)
resource "scaleway_vpc_public_gateway_ip" "main" {
  tags = var.tags
}

# Gateway for private network (enables internet access)
resource "scaleway_vpc_public_gateway" "main" {
  name  = "${var.vpc_name}-gateway"
  type  = "VPC-GW-S"
  ip_id = scaleway_vpc_public_gateway_ip.main.id
  tags  = var.tags
}

# Attach gateway to private network
resource "scaleway_vpc_gateway_network" "main" {
  gateway_id         = scaleway_vpc_public_gateway.main.id
  private_network_id = scaleway_vpc_private_network.private_network.id
  dhcp_id            = scaleway_vpc_private_network.private_network.id
  # cleanup_dhcp deprecated - using ipam_config instead
  ipam_config {
    push_default_route = true
  }
  enable_masquerade = true
}