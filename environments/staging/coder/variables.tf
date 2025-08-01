variable "scaleway_zone" {
  description = "Scaleway zone"
  type        = string
  default     = "fr-par-1"
}

variable "scaleway_region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    "managed-by"  = "terraform"
    "project"     = "coder"
    "environment" = "staging"
    "component"   = "application"
  }
}