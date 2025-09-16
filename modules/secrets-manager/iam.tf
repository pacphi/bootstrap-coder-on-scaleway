# IAM Application for External Secrets Operator
resource "scaleway_iam_application" "external_secrets" {
  name        = "external-secrets-${var.environment}"
  description = "Application for External Secrets Operator in ${var.environment}"

  tags = {
    Environment = var.environment
    Service     = "external-secrets"
    ManagedBy   = "terraform"
  }
}

# API Key for External Secrets Operator
resource "scaleway_iam_api_key" "external_secrets" {
  application_id = scaleway_iam_application.external_secrets.id
  description    = "API key for External Secrets Operator in ${var.environment}"

  # Set reasonable expiration (1 year)
  expires_at = timeadd(timestamp(), "8760h") # 1 year
}

# IAM Group for secret readers
resource "scaleway_iam_group" "secret_readers" {
  name           = "secret-readers-${var.environment}"
  description    = "Group with read access to secrets in ${var.environment}"
  organization_id = var.organization_id

  tags = {
    Environment = var.environment
    Service     = "secrets-management"
    ManagedBy   = "terraform"
  }
}

# IAM Policy for secret read access
resource "scaleway_iam_policy" "secret_read" {
  name           = "secret-read-${var.environment}"
  description    = "Allow read access to secrets in ${var.environment}"
  organization_id = var.organization_id

  rule {
    project_ids          = [var.project_id]
    permission_set_names = ["SecretManagerReadOnly"]
  }

  tags = {
    Environment = var.environment
    Service     = "secrets-management"
    ManagedBy   = "terraform"
  }
}

# Group membership for External Secrets application
resource "scaleway_iam_group_membership" "external_secrets" {
  group_id       = scaleway_iam_group.secret_readers.id
  application_id = scaleway_iam_application.external_secrets.id
}

# Policy attachment to group
resource "scaleway_iam_group_membership" "secret_read_policy" {
  group_id  = scaleway_iam_group.secret_readers.id
  policy_id = scaleway_iam_policy.secret_read.id
}