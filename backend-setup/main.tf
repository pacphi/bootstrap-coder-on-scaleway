provider "scaleway" {
  region     = var.region
  zone       = "${var.region}-1"
  project_id = var.project_id != "" ? var.project_id : null
}

module "terraform_backend" {
  source = "../modules/terraform-backend"

  bucket_name              = local.actual_bucket_name
  environment              = var.environment
  region                   = var.region
  project_id               = local.actual_project_id
  state_retention_days     = var.state_retention_days
  generate_backend_config  = var.generate_backend_config

  tags = merge(var.tags, {
    Environment = var.environment
    Project     = "coder-platform"
    Purpose     = "terraform-state"
    ManagedBy   = var.managed_by
  })
}