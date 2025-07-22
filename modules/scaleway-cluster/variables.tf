variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "cluster_description" {
  description = "Description of the Kubernetes cluster"
  type        = string
  default     = "Kubernetes cluster for Coder development environment"
}

variable "cluster_version" {
  description = "Version of Kubernetes to deploy"
  type        = string
  default     = "1.29"
}

variable "cni" {
  description = "Container Network Interface to use"
  type        = string
  default     = "cilium"
}

variable "enable_dashboard" {
  description = "Enable Kubernetes dashboard"
  type        = bool
  default     = false
}

variable "ingress" {
  description = "Ingress controller to use"
  type        = string
  default     = "nginx"
}

variable "auto_upgrade" {
  description = "Enable automatic upgrades"
  type        = bool
  default     = true
}

variable "maintenance_window_start_hour" {
  description = "Start hour for maintenance window"
  type        = number
  default     = 2
}

variable "maintenance_window_day" {
  description = "Day of the week for maintenance window"
  type        = string
  default     = "sunday"
}

variable "feature_gates" {
  description = "Feature gates to enable"
  type        = list(string)
  default     = []
}

variable "admission_plugins" {
  description = "Admission plugins to enable"
  type        = list(string)
  default     = []
}

variable "open_id_connect_config" {
  description = "OpenID Connect configuration"
  type = object({
    issuer_url      = string
    client_id       = string
    username_claim  = string
    username_prefix = string
    groups_claim    = list(string)
    groups_prefix   = string
    required_claim  = list(string)
  })
  default = null
}

variable "apiserver_cert_sans" {
  description = "Additional certificate SANs for the API server"
  type        = list(string)
  default     = []
}

variable "private_network_id" {
  description = "ID of the private network"
  type        = string
}

# Node Pool Configuration
variable "node_pools" {
  description = "Configuration for node pools"
  type = list(object({
    name            = string
    node_type       = string
    size            = number
    min_size        = number
    max_size        = number
    autoscaling     = bool
    autohealing     = bool
    container_runtime = string
    placement_group_id = optional(string)
    tags            = optional(list(string), [])
    kubelet_args    = optional(map(string), {})
    upgrade_policy = optional(object({
      max_unavailable = optional(number)
      max_surge       = optional(number)
    }))
    zone = optional(string)
    root_volume_type = optional(string, "l_ssd")
    root_volume_size = optional(number, 20)
  }))
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "Scaleway region"
  type        = string
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
}