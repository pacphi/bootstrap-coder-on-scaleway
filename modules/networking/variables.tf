variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "private_network_name" {
  description = "Name of the private network"
  type        = string
}

variable "enable_load_balancer" {
  description = "Enable load balancer"
  type        = bool
  default     = true
}

variable "load_balancer_name" {
  description = "Name of the load balancer"
  type        = string
  default     = ""
}

variable "load_balancer_type" {
  description = "Type of load balancer"
  type        = string
  default     = "LB-S"

  validation {
    condition     = contains(["LB-S", "LB-GP-M", "LB-GP-L"], var.load_balancer_type)
    error_message = "Load balancer type must be one of: LB-S, LB-GP-M, LB-GP-L."
  }
}

variable "ssl_compatibility_level" {
  description = "SSL compatibility level"
  type        = string
  default     = "ssl_compatibility_level_modern"

  validation {
    condition = contains([
      "ssl_compatibility_level_old",
      "ssl_compatibility_level_intermediate",
      "ssl_compatibility_level_modern"
    ], var.ssl_compatibility_level)
    error_message = "SSL compatibility level must be old, intermediate, or modern."
  }
}

variable "region" {
  description = "Scaleway region"
  type        = string
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = list(string)
  default     = []
}

# Domain configuration for SSL certificates
variable "domain_name" {
  description = "Domain name for SSL certificate"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Subdomain for the service"
  type        = string
  default     = ""
}

# Security Group Rules
variable "security_group_rules" {
  description = "Security group rules"
  type = list(object({
    direction   = string
    action      = string
    protocol    = string
    port        = optional(number)
    port_range  = optional(string)
    ip_range    = string
    description = optional(string)
  }))
  default = []
}

# Network Access Control
variable "management_cidr" {
  description = "CIDR range for management access (SSH, monitoring)"
  type        = string
  default     = "0.0.0.0/0"  # Default to unrestricted for backward compatibility
}

variable "trusted_cidr" {
  description = "CIDR range for trusted access (Kubernetes API, admin interfaces)"
  type        = string
  default     = "0.0.0.0/0"  # Default to unrestricted for backward compatibility
}

variable "vpc_cidr" {
  description = "VPC CIDR range for internal communication"
  type        = string
  default     = "10.0.0.0/8"
}

variable "allow_public_api" {
  description = "Allow public access to Kubernetes API (not recommended for production)"
  type        = bool
  default     = true
}

variable "allow_public_ssh" {
  description = "Allow public SSH access (not recommended for production)"
  type        = bool
  default     = true
}