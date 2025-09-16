terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.57"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# Generate secure passwords for secrets
resource "random_password" "coder_admin" {
  length  = 32
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Database credentials secret
resource "scaleway_secret" "database_credentials" {
  name        = "${var.environment}-database-credentials"
  description = "Database connection credentials for ${var.environment}"
  region      = var.region
  project_id  = var.project_id

  tags = {
    Environment = var.environment
    Service     = "coder"
    Type        = "database"
    ManagedBy   = "terraform"
  }
}

resource "scaleway_secret_version" "database_password" {
  secret_id = scaleway_secret.database_credentials.id
  data = jsonencode({
    username = var.database_username
    password = var.database_password
    host     = var.database_host
    port     = var.database_port
    database = var.database_name
    ssl_mode = "require"
  })
}

# Coder admin credentials secret
resource "scaleway_secret" "coder_admin_credentials" {
  name        = "${var.environment}-coder-admin"
  description = "Coder admin user credentials for ${var.environment}"
  region      = var.region
  project_id  = var.project_id

  tags = {
    Environment = var.environment
    Service     = "coder"
    Type        = "admin"
    ManagedBy   = "terraform"
  }
}

resource "scaleway_secret_version" "coder_admin_password" {
  secret_id = scaleway_secret.coder_admin_credentials.id
  data = jsonencode({
    username = "admin"
    password = random_password.coder_admin.result
    email    = var.admin_email
  })
}

# OAuth secrets (GitHub)
resource "scaleway_secret" "oauth_github" {
  count = var.oauth_github_client_id != "" ? 1 : 0

  name        = "${var.environment}-oauth-github"
  description = "GitHub OAuth credentials for ${var.environment}"
  region      = var.region
  project_id  = var.project_id

  tags = {
    Environment = var.environment
    Service     = "coder"
    Type        = "oauth"
    Provider    = "github"
    ManagedBy   = "terraform"
  }
}

resource "scaleway_secret_version" "oauth_github" {
  count = var.oauth_github_client_id != "" ? 1 : 0

  secret_id = scaleway_secret.oauth_github[0].id
  data = jsonencode({
    client_id     = var.oauth_github_client_id
    client_secret = var.oauth_github_client_secret
  })
}

# OAuth secrets (Google)
resource "scaleway_secret" "oauth_google" {
  count = var.oauth_google_client_id != "" ? 1 : 0

  name        = "${var.environment}-oauth-google"
  description = "Google OAuth credentials for ${var.environment}"
  region      = var.region
  project_id  = var.project_id

  tags = {
    Environment = var.environment
    Service     = "coder"
    Type        = "oauth"
    Provider    = "google"
    ManagedBy   = "terraform"
  }
}

resource "scaleway_secret_version" "oauth_google" {
  count = var.oauth_google_client_id != "" ? 1 : 0

  secret_id = scaleway_secret.oauth_google[0].id
  data = jsonencode({
    client_id     = var.oauth_google_client_id
    client_secret = var.oauth_google_client_secret
  })
}

# Additional application secrets
resource "scaleway_secret" "application_secrets" {
  for_each = var.additional_secrets

  name        = "${var.environment}-${each.key}"
  description = "Application secret: ${each.value.description}"
  region      = var.region
  project_id  = var.project_id

  tags = merge({
    Environment = var.environment
    Service     = "coder"
    Type        = "application"
    ManagedBy   = "terraform"
  }, each.value.tags)
}

resource "scaleway_secret_version" "application_secrets" {
  for_each = var.additional_secrets

  secret_id = scaleway_secret.application_secrets[each.key].id
  data      = jsonencode(each.value.data)
}