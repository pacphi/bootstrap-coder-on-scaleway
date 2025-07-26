terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

# Variables
variable "use_kubeconfig" {
  type        = bool
  sensitive   = true
  description = "Use host kubeconfig? (true/false)"
  default     = false
}

variable "namespace" {
  type        = string
  sensitive   = true
  description = "The Kubernetes namespace to create workspaces in"
  default     = "coder"
}

# Data sources
data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
  option {
    name  = "32 GB"
    value = "32"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "20"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = false
  validation {
    min = 15
    max = 100
  }
}

data "coder_parameter" "rust_version" {
  name         = "rust_version"
  display_name = "Rust Version"
  description  = "Rust version to install"
  default      = "stable"
  icon         = "/icon/rust.svg"
  mutable      = false
  option {
    name  = "Stable"
    value = "stable"
  }
  option {
    name  = "Beta"
    value = "beta"
  }
  option {
    name  = "Nightly"
    value = "nightly"
  }
}

data "coder_parameter" "ide" {
  name         = "ide"
  display_name = "IDE"
  description  = "IDE to use"
  default      = "vscode"
  icon         = "/icon/code.svg"
  mutable      = true
  option {
    name  = "VS Code"
    value = "vscode"
  }
  option {
    name  = "RustRover"
    value = "rustrover"
  }
  option {
    name  = "Terminal Only"
    value = "terminal"
  }
}

# Providers
provider "kubernetes" {
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

# Workspace
resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash

    echo "🦀 Setting up Rust development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y \
      curl \
      wget \
      git \
      build-essential \
      pkg-config \
      libssl-dev \
      libpq-dev \
      postgresql-client \
      redis-tools \
      htop \
      tree \
      jq \
      unzip

    # Install Rust
    echo "🦀 Installing Rust ${data.coder_parameter.rust_version.value}..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain ${data.coder_parameter.rust_version.value}
    source ~/.cargo/env
    echo 'source ~/.cargo/env' >> ~/.bashrc

    # Install additional Rust components
    rustup component add clippy rustfmt rust-analyzer

    # Install useful Rust tools
    cargo install cargo-watch cargo-edit cargo-audit cargo-outdated
    cargo install diesel_cli --no-default-features --features postgres
    cargo install sqlx-cli

    # Install Docker
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # IDE-specific installations
    case "${data.coder_parameter.ide.value}" in
      "vscode")
        echo "💻 Installing VS Code..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        sudo apt update
        sudo apt install -y code

        # Install Rust extensions
        code --install-extension rust-lang.rust-analyzer
        code --install-extension serayuzgur.crates
        code --install-extension vadimcn.vscode-lldb
        code --install-extension tamasfe.even-better-toml
        code --install-extension ms-vscode.vscode-json
        ;;
      "rustrover")
        echo "🧠 Installing RustRover..."
        wget -q https://download.jetbrains.com/rustrover/RustRover-2023.3.tar.gz -O /tmp/rustrover.tar.gz
        sudo tar -xzf /tmp/rustrover.tar.gz -C /opt
        sudo ln -sf /opt/RustRover-*/bin/rustrover.sh /usr/local/bin/rustrover
        rm /tmp/rustrover.tar.gz
        ;;
    esac

    # Create Actix Web project
    echo "🚀 Creating Actix Web project..."
    cd /home/coder
    cargo new actix-api --bin
    cd actix-api

    # Update Cargo.toml with dependencies
    cat > Cargo.toml << 'EOF'
[package]
name = "actix-api"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.4"
actix-cors = "0.7"
tokio = { version = "1.35", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
sqlx = { version = "0.7", features = ["runtime-tokio-rustls", "postgres", "uuid", "chrono"] }
uuid = { version = "1.6", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
dotenvy = "0.15"
env_logger = "0.11"
log = "0.4"
anyhow = "1.0"
thiserror = "1.0"

[dev-dependencies]
actix-rt = "2.9"

[[bin]]
name = "actix-api"
path = "src/main.rs"
EOF

    # Create main.rs with Actix Web API
    cat > src/main.rs << 'EOF'
use actix_cors::Cors;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer, Result};
use serde::{Deserialize, Serialize};
use sqlx::{PgPool, Row};
use std::env;
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
struct User {
    id: Uuid,
    name: String,
    email: String,
    created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
struct CreateUser {
    name: String,
    email: String,
}

#[derive(Debug, Serialize)]
struct ApiResponse<T> {
    status: String,
    data: Option<T>,
    message: Option<String>,
}

impl<T> ApiResponse<T> {
    fn success(data: T) -> Self {
        Self {
            status: "success".to_string(),
            data: Some(data),
            message: None,
        }
    }

    fn error(message: String) -> ApiResponse<()> {
        ApiResponse {
            status: "error".to_string(),
            data: None,
            message: Some(message),
        }
    }
}

async fn health() -> Result<HttpResponse> {
    Ok(HttpResponse::Ok().json(ApiResponse::success(serde_json::json!({
        "message": "Actix Web API is running!",
        "timestamp": Utc::now()
    }))))
}

async fn get_users(pool: web::Data<PgPool>) -> Result<HttpResponse> {
    match sqlx::query_as::<_, User>("SELECT id, name, email, created_at FROM users ORDER BY created_at DESC")
        .fetch_all(pool.get_ref())
        .await
    {
        Ok(users) => Ok(HttpResponse::Ok().json(ApiResponse::success(users))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<()>::error(
            format!("Database error: {}", e)
        ))),
    }
}

async fn create_user(
    pool: web::Data<PgPool>,
    user_data: web::Json<CreateUser>,
) -> Result<HttpResponse> {
    let user_id = Uuid::new_v4();

    match sqlx::query_as::<_, User>(
        "INSERT INTO users (id, name, email) VALUES ($1, $2, $3) RETURNING id, name, email, created_at"
    )
    .bind(&user_id)
    .bind(&user_data.name)
    .bind(&user_data.email)
    .fetch_one(pool.get_ref())
    .await
    {
        Ok(user) => Ok(HttpResponse::Created().json(ApiResponse::success(user))),
        Err(e) => Ok(HttpResponse::BadRequest().json(ApiResponse::<()>::error(
            format!("Failed to create user: {}", e)
        ))),
    }
}

async fn get_user(
    pool: web::Data<PgPool>,
    path: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();

    match sqlx::query_as::<_, User>("SELECT id, name, email, created_at FROM users WHERE id = $1")
        .bind(&user_id)
        .fetch_optional(pool.get_ref())
        .await
    {
        Ok(Some(user)) => Ok(HttpResponse::Ok().json(ApiResponse::success(user))),
        Ok(None) => Ok(HttpResponse::NotFound().json(ApiResponse::<()>::error(
            "User not found".to_string()
        ))),
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<()>::error(
            format!("Database error: {}", e)
        ))),
    }
}

async fn delete_user(
    pool: web::Data<PgPool>,
    path: web::Path<Uuid>,
) -> Result<HttpResponse> {
    let user_id = path.into_inner();

    match sqlx::query("DELETE FROM users WHERE id = $1")
        .bind(&user_id)
        .execute(pool.get_ref())
        .await
    {
        Ok(result) => {
            if result.rows_affected() > 0 {
                Ok(HttpResponse::Ok().json(ApiResponse::success(serde_json::json!({
                    "message": "User deleted successfully"
                }))))
            } else {
                Ok(HttpResponse::NotFound().json(ApiResponse::<()>::error(
                    "User not found".to_string()
                )))
            }
        }
        Err(e) => Ok(HttpResponse::InternalServerError().json(ApiResponse::<()>::error(
            format!("Database error: {}", e)
        ))),
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize logger
    env_logger::init();

    // Load environment variables
    dotenvy::dotenv().ok();

    let database_url = env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgresql://postgres:password@localhost:5432/actix_db".to_string());

    // Create database connection pool
    let pool = PgPool::connect(&database_url)
        .await
        .expect("Failed to create database pool");

    // Run migrations (in a real app, you'd use sqlx migrate)
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY,
            name VARCHAR NOT NULL,
            email VARCHAR NOT NULL UNIQUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
        "#,
    )
    .execute(&pool)
    .await
    .expect("Failed to run migrations");

    let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());

    println!("🚀 Starting Actix Web server on {}:{}", host, port);

    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allow_any_method()
            .allow_any_header();

        App::new()
            .app_data(web::Data::new(pool.clone()))
            .wrap(Logger::default())
            .wrap(cors)
            .route("/health", web::get().to(health))
            .service(
                web::scope("/api/v1")
                    .route("/health", web::get().to(health))
                    .route("/users", web::get().to(get_users))
                    .route("/users", web::post().to(create_user))
                    .route("/users/{id}", web::get().to(get_user))
                    .route("/users/{id}", web::delete().to(delete_user))
            )
    })
    .bind(format!("{}:{}", host, port))?
    .run()
    .await
}
EOF

    # Create .env file
    cat > .env << 'EOF'
DATABASE_URL=postgresql://postgres:password@localhost:5432/actix_db
HOST=0.0.0.0
PORT=8080
RUST_LOG=debug
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/actix_db
      - RUST_LOG=debug
    depends_on:
      - postgres
      - redis
    volumes:
      - .:/app
      - /app/target  # Anonymous volume for target directory

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: actix_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  postgres_data:
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM rust:1.75 as builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
RUN cargo fetch

COPY src ./src
RUN cargo build --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/actix-api .

EXPOSE 8080

CMD ["./actix-api"]
EOF

    # Create Makefile
    cat > Makefile << 'EOF'
.PHONY: run build clean test docker-build docker-run watch lint fmt

run:
	cargo run

build:
	cargo build --release

clean:
	cargo clean

test:
	cargo test

watch:
	cargo watch -x run

docker-build:
	docker-compose build

docker-run:
	docker-compose up

docker-down:
	docker-compose down

lint:
	cargo clippy -- -D warnings

fmt:
	cargo fmt

check:
	cargo check

audit:
	cargo audit

outdated:
	cargo outdated
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
/target
**/*.rs.bk
Cargo.lock
.env.local
*.pdb
.DS_Store
EOF

    # Create configuration for development
    mkdir -p .vscode
    cat > .vscode/settings.json << 'EOF'
{
    "rust-analyzer.cargo.watchOptions": {
        "enable": true,
        "arguments": ["--workspace"]
    },
    "rust-analyzer.checkOnSave.command": "clippy",
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "rust-lang.rust-analyzer"
}
EOF

    cat > .vscode/launch.json << 'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "lldb",
            "request": "launch",
            "name": "Debug executable 'actix-api'",
            "cargo": {
                "args": [
                    "build",
                    "--bin=actix-api",
                    "--package=actix-api"
                ],
                "filter": {
                    "name": "actix-api",
                    "kind": "bin"
                }
            },
            "args": [],
            "cwd": "$${workspaceFolder}"
        }
    ]
}
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/actix-api

    # Build the project
    cd /home/coder/actix-api
    source ~/.cargo/env
    cargo check

    echo "✅ Rust Actix Web development environment ready!"
    echo "Run 'cargo watch -x run' to start development server with auto-reload"

  EOT

}

# Metadata
resource "coder_metadata" "rust_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "rust_version"
    value = data.coder_parameter.rust_version.value
  }
}

resource "coder_metadata" "cpu_cores" {
  resource_id = coder_agent.main.id
  item {
    key   = "cpu"
    value = "${data.coder_parameter.cpu.value} cores"
  }
}

resource "coder_metadata" "memory" {
  resource_id = coder_agent.main.id
  item {
    key   = "memory"
    value = "${data.coder_parameter.memory.value}GB"
  }
}

resource "coder_metadata" "ide" {
  resource_id = coder_agent.main.id
  item {
    key   = "ide"
    value = data.coder_parameter.ide.value
  }
}

# Applications
resource "coder_app" "actix_api" {
  agent_id     = coder_agent.main.id
  slug         = "actix-api"
  display_name = "Actix Web API"
  url          = "http://localhost:8080"
  icon         = "/icon/rust.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080/health"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "vscode" {
  count        = data.coder_parameter.ide.value == "vscode" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/actix-api"
  share        = "owner"
}

resource "coder_app" "rustrover" {
  count        = data.coder_parameter.ide.value == "rustrover" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "rustrover"
  display_name = "RustRover"
  icon         = "/icon/rustrover.svg"
  command      = "rustrover /home/coder/actix-api"
  share        = "owner"
}

# Kubernetes resources
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace
  }

  wait_until_bound = false

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }

    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "coder-workspace"
          "app.kubernetes.io/instance"  = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
          "app.kubernetes.io/component" = "workspace"
        }
      }

      spec {
        security_context {
          run_as_user  = 1000
          run_as_group = 1000
          fs_group     = 1000
        }

        container {
          name              = "dev"
          image             = "ubuntu:22.04"
          image_pull_policy = "Always"
          command           = ["/bin/bash", "-c", coder_agent.main.init_script]

          security_context {
            run_as_user                = 1000
            allow_privilege_escalation = false
            capabilities {
              add = ["SYS_ADMIN"]
            }
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          resources {
            requests = {
              "cpu"    = "${data.coder_parameter.cpu.value}000m"
              "memory" = "${data.coder_parameter.memory.value}G"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}000m"
              "memory" = "${data.coder_parameter.memory.value}G"
            }
          }

          volume_mount {
            mount_path = "/home/coder"
            name       = "home"
            read_only  = false
          }
        }

        volume {
          name = "home"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home.metadata.0.name
            read_only  = false
          }
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.home]
}
