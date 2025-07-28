variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to configure security for"
  type        = string
  default     = "coder"
}

variable "enable_pod_security_standards" {
  description = "Enable Pod Security Standards"
  type        = bool
  default     = true
}

variable "pod_security_standard" {
  description = "Pod Security Standard level to enforce"
  type        = string
  default     = "baseline"

  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.pod_security_standard)
    error_message = "Pod Security Standard must be one of: privileged, baseline, restricted."
  }
}

variable "enable_network_policies" {
  description = "Enable Network Policies"
  type        = bool
  default     = true
}

variable "enable_rbac" {
  description = "Enable RBAC configurations"
  type        = bool
  default     = true
}

variable "additional_namespaces" {
  description = "Additional namespaces to secure"
  type        = list(string)
  default     = ["monitoring", "kube-system"]
}

variable "allowed_registries" {
  description = "List of allowed container registries"
  type        = list(string)
  default = [
    "docker.io",
    "gcr.io",
    "ghcr.io",
    "quay.io",
    "registry.k8s.io",
    "codercom"
  ]
}

variable "resource_quotas" {
  description = "Resource quotas for namespaces"
  type = object({
    hard_limits = optional(map(string), {
      "requests.cpu"           = "4"
      "requests.memory"        = "8Gi"
      "limits.cpu"             = "8"
      "limits.memory"          = "16Gi"
      "pods"                   = "10"
      "services"               = "5"
      "persistentvolumeclaims" = "10"
    })
  })
  default = {}
}

variable "network_policy_rules" {
  description = "Custom network policy rules"
  type = list(object({
    name         = string
    namespace    = string
    pod_selector = map(string)
    ingress = optional(list(object({
      from = optional(list(object({
        pod_selector       = optional(map(string))
        namespace_selector = optional(map(string))
        ip_block = optional(object({
          cidr   = string
          except = optional(list(string))
        }))
      })))
      ports = optional(list(object({
        protocol = optional(string)
        port     = optional(string)
      })))
    })))
    egress = optional(list(object({
      to = optional(list(object({
        pod_selector       = optional(map(string))
        namespace_selector = optional(map(string))
        ip_block = optional(object({
          cidr   = string
          except = optional(list(string))
        }))
      })))
      ports = optional(list(object({
        protocol = optional(string)
        port     = optional(string)
      })))
    })))
  }))
  default = []
}