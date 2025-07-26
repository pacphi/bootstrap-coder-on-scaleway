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
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
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
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "10"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = false
  validation {
    min = 1
    max = 100
  }
}

data "coder_parameter" "go_version" {
  name         = "go_version"
  display_name = "Go Version"
  description  = "Go version to install"
  default      = "1.21"
  icon         = "/icon/go.svg"
  mutable      = false
  option {
    name  = "Go 1.21"
    value = "1.21"
  }
  option {
    name  = "Go 1.22"
    value = "1.22"
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
    name  = "GoLand"
    value = "goland"
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

    # Install Go ${data.coder_parameter.go_version.value}
    echo "🐹 Installing Go ${data.coder_parameter.go_version.value}..."
    sudo apt-get update
    sudo apt-get install -y wget curl git build-essential

    wget -q https://golang.org/dl/go${data.coder_parameter.go_version.value}.linux-amd64.tar.gz -O /tmp/go.tar.gz
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz

    # Setup Go environment
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/coder/.bashrc
    echo 'export GOPATH=/home/coder/go' >> /home/coder/.bashrc
    echo 'export GOPROXY=https://proxy.golang.org,direct' >> /home/coder/.bashrc
    echo 'export GOSUMDB=sum.golang.org' >> /home/coder/.bashrc
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH=/home/coder/go

    # Create Go workspace
    mkdir -p /home/coder/go/{bin,pkg,src}

    # Install useful Go tools
    go install github.com/cosmtrek/air@latest
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
    go install github.com/swaggo/swag/cmd/swag@latest
    go install golang.org/x/tools/cmd/goimports@latest
    go install github.com/go-delve/delve/cmd/dlv@latest

    # Install Docker
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Install useful system tools
    sudo apt-get install -y htop tree jq unzip postgresql-client redis-tools

    # IDE-specific installations
    case "${data.coder_parameter.ide.value}" in
      "vscode")
        echo "💻 Installing VS Code..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        sudo apt update
        sudo apt install -y code

        # Install Go extensions
        code --install-extension golang.go
        code --install-extension ms-vscode.vscode-json
        code --install-extension bradlc.vscode-tailwindcss
        code --install-extension GitHub.copilot
        ;;
      "goland")
        echo "🧠 Installing GoLand..."
        wget -q https://download.jetbrains.com/go/goland-2023.3.2.tar.gz -O /tmp/goland.tar.gz
        sudo tar -xzf /tmp/goland.tar.gz -C /opt
        sudo ln -sf /opt/GoLand-*/bin/goland.sh /usr/local/bin/goland
        rm /tmp/goland.tar.gz
        ;;
    esac

    # Create Fiber project
    echo "🚀 Setting up Fiber project..."
    cd /home/coder
    mkdir -p fiber-api
    cd fiber-api

    # Initialize Go module
    go mod init fiber-api

    # Install Fiber and dependencies
    go get github.com/gofiber/fiber/v2
    go get github.com/gofiber/fiber/v2/middleware/cors
    go get github.com/gofiber/fiber/v2/middleware/logger
    go get github.com/gofiber/fiber/v2/middleware/recover
    go get github.com/gofiber/swagger
    go get github.com/swaggo/swag/example/celler/docs
    go get gorm.io/gorm
    go get gorm.io/driver/postgres
    go get gorm.io/driver/sqlite
    go get github.com/joho/godotenv

    # Create main.go
    cat > main.go << 'EOF'
package main

import (
    "log"
    "os"

    "github.com/gofiber/fiber/v2"
    "github.com/gofiber/fiber/v2/middleware/cors"
    "github.com/gofiber/fiber/v2/middleware/logger"
    "github.com/gofiber/fiber/v2/middleware/recover"
    "github.com/joho/godotenv"
    "gorm.io/driver/sqlite"
    "gorm.io/gorm"
)

type User struct {
    ID    uint   `json:"id" gorm:"primaryKey"`
    Name  string `json:"name"`
    Email string `json:"email"`
}

var db *gorm.DB

func setupDatabase() {
    var err error
    db, err = gorm.Open(sqlite.Open("fiber.db"), &gorm.Config{})
    if err != nil {
        panic("Failed to connect to database!")
    }

    db.AutoMigrate(&User{})
}

func setupRoutes(app *fiber.App) {
    api := app.Group("/api/v1")

    // Health check
    api.Get("/health", func(c *fiber.Ctx) error {
        return c.JSON(fiber.Map{
            "status":  "success",
            "message": "Fiber API is running!",
            "data":    nil,
        })
    })

    // Users routes
    users := api.Group("/users")
    users.Get("/", getUsers)
    users.Post("/", createUser)
    users.Get("/:id", getUser)
    users.Put("/:id", updateUser)
    users.Delete("/:id", deleteUser)
}

// @Summary Get all users
// @Description Get all users from database
// @Tags users
// @Accept json
// @Produce json
// @Success 200 {array} User
// @Router /api/v1/users [get]
func getUsers(c *fiber.Ctx) error {
    var users []User
    db.Find(&users)

    return c.JSON(fiber.Map{
        "status": "success",
        "data":   users,
    })
}

// @Summary Create user
// @Description Create a new user
// @Tags users
// @Accept json
// @Produce json
// @Param user body User true "User object"
// @Success 201 {object} User
// @Router /api/v1/users [post]
func createUser(c *fiber.Ctx) error {
    user := new(User)

    if err := c.BodyParser(user); err != nil {
        return c.Status(400).JSON(fiber.Map{
            "status":  "error",
            "message": "Cannot parse JSON",
        })
    }

    db.Create(&user)

    return c.Status(201).JSON(fiber.Map{
        "status": "success",
        "data":   user,
    })
}

// @Summary Get user by ID
// @Description Get a single user by ID
// @Tags users
// @Accept json
// @Produce json
// @Param id path int true "User ID"
// @Success 200 {object} User
// @Router /api/v1/users/{id} [get]
func getUser(c *fiber.Ctx) error {
    id := c.Params("id")
    var user User

    if err := db.First(&user, id).Error; err != nil {
        return c.Status(404).JSON(fiber.Map{
            "status":  "error",
            "message": "User not found",
        })
    }

    return c.JSON(fiber.Map{
        "status": "success",
        "data":   user,
    })
}

// @Summary Update user
// @Description Update user by ID
// @Tags users
// @Accept json
// @Produce json
// @Param id path int true "User ID"
// @Param user body User true "User object"
// @Success 200 {object} User
// @Router /api/v1/users/{id} [put]
func updateUser(c *fiber.Ctx) error {
    id := c.Params("id")
    var user User

    if err := db.First(&user, id).Error; err != nil {
        return c.Status(404).JSON(fiber.Map{
            "status":  "error",
            "message": "User not found",
        })
    }

    if err := c.BodyParser(&user); err != nil {
        return c.Status(400).JSON(fiber.Map{
            "status":  "error",
            "message": "Cannot parse JSON",
        })
    }

    db.Save(&user)

    return c.JSON(fiber.Map{
        "status": "success",
        "data":   user,
    })
}

// @Summary Delete user
// @Description Delete user by ID
// @Tags users
// @Accept json
// @Produce json
// @Param id path int true "User ID"
// @Success 200 {string} string "User deleted"
// @Router /api/v1/users/{id} [delete]
func deleteUser(c *fiber.Ctx) error {
    id := c.Params("id")
    var user User

    if err := db.First(&user, id).Error; err != nil {
        return c.Status(404).JSON(fiber.Map{
            "status":  "error",
            "message": "User not found",
        })
    }

    db.Delete(&user)

    return c.JSON(fiber.Map{
        "status":  "success",
        "message": "User deleted",
    })
}

func main() {
    // Load environment variables
    if err := godotenv.Load(); err != nil {
        log.Println("No .env file found")
    }

    // Setup database
    setupDatabase()

    // Create Fiber app
    app := fiber.New(fiber.Config{
        AppName: "Fiber API v1.0.0",
    })

    // Middleware
    app.Use(logger.New())
    app.Use(recover.New())
    app.Use(cors.New(cors.Config{
        AllowOrigins: "*",
        AllowMethods: "GET,POST,HEAD,PUT,DELETE,PATCH",
        AllowHeaders: "*",
    }))

    // Routes
    setupRoutes(app)

    // Start server
    port := os.Getenv("PORT")
    if port == "" {
        port = "3000"
    }

    log.Printf("🚀 Server starting on port %s", port)
    log.Fatal(app.Listen(":" + port))
}
EOF

    # Create .env file
    cat > .env << 'EOF'
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASS=password
DB_NAME=fiber_db
EOF

    # Create air configuration for live reload
    cat > .air.toml << 'EOF'
root = "."
testdata_dir = "testdata"
tmp_dir = "tmp"

[build]
  args_bin = []
  bin = "./tmp/main"
  cmd = "go build -o ./tmp/main ."
  delay = 1000
  exclude_dir = ["assets", "tmp", "vendor", "testdata"]
  exclude_file = []
  exclude_regex = ["_test.go"]
  exclude_unchanged = false
  follow_symlink = false
  full_bin = ""
  include_dir = []
  include_ext = ["go", "tpl", "tmpl", "html"]
  include_file = []
  kill_delay = "0s"
  log = "build-errors.log"
  poll = false
  poll_interval = 0
  rerun = false
  rerun_delay = 500
  send_interrupt = false
  stop_on_root = false

[color]
  app = ""
  build = "yellow"
  main = "magenta"
  runner = "green"
  watcher = "cyan"

[log]
  main_only = false
  time = false

[misc]
  clean_on_exit = false

[screen]
  clear_on_rebuild = false
  keep_scroll = true
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/

COPY --from=builder /app/main .

EXPOSE 3000

CMD ["./main"]
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - PORT=3000
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASS=password
      - DB_NAME=fiber_db
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: fiber_db
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

    # Create Makefile
    cat > Makefile << 'EOF'
.PHONY: run build clean test docker-build docker-run

run:
	air

build:
	go build -o bin/fiber-api main.go

clean:
	go clean
	rm -rf bin/

test:
	go test -v ./...

dev:
	air

docker-build:
	docker-compose build

docker-run:
	docker-compose up

docker-down:
	docker-compose down

lint:
	golangci-lint run

fmt:
	go fmt ./...
	goimports -w .

mod-tidy:
	go mod tidy

swagger:
	swag init

deps:
	go mod download
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/fiber-api

    # Build initial version
    cd /home/coder/fiber-api
    go mod tidy
    go build -o bin/fiber-api main.go

    echo "✅ Go Fiber development environment ready!"

  EOT

}

# Metadata
resource "coder_metadata" "go_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "go_version"
    value = data.coder_parameter.go_version.value
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
resource "coder_app" "fiber_api" {
  agent_id     = coder_agent.main.id
  slug         = "fiber-api"
  display_name = "Fiber API"
  url          = "http://localhost:3000"
  icon         = "/icon/go.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:3000/api/v1/health"
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
  command      = "code /home/coder/fiber-api"
  share        = "owner"
}

resource "coder_app" "goland" {
  count        = data.coder_parameter.ide.value == "goland" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "goland"
  display_name = "GoLand"
  icon         = "/icon/goland.svg"
  command      = "goland /home/coder/fiber-api"
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
