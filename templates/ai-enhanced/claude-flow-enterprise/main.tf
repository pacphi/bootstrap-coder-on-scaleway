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
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "8 Cores"
    value = "8"
  }
  option {
    name  = "12 Cores"
    value = "12"
  }
  option {
    name  = "16 Cores"
    value = "16"
  }
  option {
    name  = "24 Cores"
    value = "24"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "16"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "16 GB"
    value = "16"
  }
  option {
    name  = "32 GB"
    value = "32"
  }
  option {
    name  = "64 GB"
    value = "64"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "50"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = false
  validation {
    min = 20
    max = 500
  }
}

data "coder_parameter" "claude_flow_mode" {
  name         = "claude_flow_mode"
  display_name = "Claude Flow Mode"
  description  = "Enterprise Claude Flow deployment mode"
  default      = "hive-mind-enterprise"
  icon         = "/icon/ai.svg"
  mutable      = false
  option {
    name  = "Hive-Mind Enterprise (Team orchestration)"
    value = "hive-mind-enterprise"
  }
  option {
    name  = "Neural Network Cluster (Advanced AI)"
    value = "neural-cluster"
  }
  option {
    name  = "Multi-Agent Swarm (Distributed tasks)"
    value = "multi-agent-swarm"
  }
}

data "coder_parameter" "enterprise_stack" {
  name         = "enterprise_stack"
  display_name = "Enterprise Development Stack"
  description  = "Choose enterprise development stack"
  default      = "full-enterprise"
  icon         = "/icon/enterprise.svg"
  mutable      = false
  option {
    name  = "Full Enterprise (All languages + AI/ML)"
    value = "full-enterprise"
  }
  option {
    name  = "Cloud Native (Go + K8s + Microservices)"
    value = "cloud-native"
  }
  option {
    name  = "AI/ML Research (Python + R + Julia)"
    value = "ai-research"
  }
  option {
    name  = "Enterprise Web (Java + .NET + Node.js)"
    value = "enterprise-web"
  }
}

data "coder_parameter" "enable_gpu" {
  name         = "enable_gpu"
  display_name = "Enable GPU Support"
  description  = "Enable GPU support for AI/ML workloads"
  default      = "true"
  type         = "bool"
  icon         = "/icon/gpu.svg"
  mutable      = false
}

data "coder_parameter" "monitoring_level" {
  name         = "monitoring_level"
  display_name = "Monitoring Level"
  description  = "Level of monitoring and observability"
  default      = "enterprise"
  icon         = "/icon/monitoring.svg"
  mutable      = false
  option {
    name  = "Enterprise (Full observability)"
    value = "enterprise"
  }
  option {
    name  = "Advanced (Metrics + Logs)"
    value = "advanced"
  }
  option {
    name  = "Basic (Essential metrics)"
    value = "basic"
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
    set -e

    echo "🏢 Setting up Claude Code Flow Enterprise Environment..."
    echo "This may take 10-15 minutes for complete setup..."

    # Update system with enterprise packages
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install -y \
      curl \
      wget \
      git \
      unzip \
      htop \
      tree \
      jq \
      build-essential \
      software-properties-common \
      apt-transport-https \
      ca-certificates \
      gnupg \
      lsb-release \
      vim \
      tmux \
      zsh \
      fish

    # Install Oh My Zsh for better terminal experience
    echo "🐚 Installing Oh My Zsh..."
    curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash || true

    # Install Node.js 22 LTS
    echo "📦 Installing Node.js 22 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # Install pnpm and yarn
    npm install -g pnpm yarn

    # Install Claude Code globally
    echo "🤖 Installing Claude Code..."
    sudo npm install -g @anthropic-ai/claude-code

    # Skip permissions for automated setup
    claude --dangerously-skip-permissions || true

    # Install Claude Flow v2.0.0 Alpha Enterprise
    echo "🧠 Installing Claude Flow v2.0.0 Alpha Enterprise..."
    cd /home/coder
    npx claude-flow@alpha init --force --enterprise

    # Enterprise stack specific installations
    case "${data.coder_parameter.enterprise_stack.value}" in
      "full-enterprise"|"enterprise-web")
        echo "☕ Installing Java 25 LTS..."
        # Add Bellsoft Liberica repository
        wget -qO - https://download.bell-sw.com/pki/GPG-KEY-bellsoft | sudo gpg --dearmor -o /etc/apt/keyrings/bellsoft.gpg
        echo "deb [signed-by=/etc/apt/keyrings/bellsoft.gpg] https://apt.bell-sw.com/ stable main" | sudo tee /etc/apt/sources.list.d/bellsoft.list
        sudo apt-get update
        sudo apt-get install -y bellsoft-java25-full

        # Install Maven and Gradle
        sudo apt-get install -y maven
        wget -q https://services.gradle.org/distributions/gradle-9.1-bin.zip -P /tmp
        sudo unzip -q /tmp/gradle-9.1-bin.zip -d /opt
        sudo ln -sf /opt/gradle-9.1/bin/gradle /usr/local/bin/gradle

        echo "💙 Installing .NET 8.0..."
        wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
        sudo dpkg -i packages-microsoft-prod.deb
        rm packages-microsoft-prod.deb
        sudo apt-get update
        sudo apt-get install -y dotnet-sdk-8.0
        ;;
    esac

    case "${data.coder_parameter.enterprise_stack.value}" in
      "full-enterprise"|"ai-research")
        echo "🐍 Installing Python 3.13 and AI/ML stack..."
        sudo add-apt-repository ppa:deadsnakes/ppa -y
        sudo apt-get update
        sudo apt-get install -y python3.13 python3.13-dev python3.13-venv python3-pip
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1
        sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.13 1

        # Install Poetry
        curl -sSL https://install.python-poetry.org | python3 -
        export PATH="/home/coder/.local/bin:$PATH"
        echo 'export PATH="/home/coder/.local/bin:$PATH"' >> ~/.bashrc

        # Install AI/ML libraries
        pip3 install --user torch torchvision torchaudio transformers datasets huggingface_hub
        pip3 install --user jupyter jupyterlab pandas numpy scipy matplotlib seaborn scikit-learn
        pip3 install --user openai anthropic langchain crewai
        pip3 install --user tensorflow keras
        ;;
    esac

    case "${data.coder_parameter.enterprise_stack.value}" in
      "full-enterprise"|"cloud-native")
        echo "🔧 Installing Go 1.21..."
        wget -q https://golang.org/dl/go1.21.5.linux-amd64.tar.gz -O /tmp/go.tar.gz
        sudo tar -C /usr/local -xzf /tmp/go.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/go/bin

        echo "🦀 Installing Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
        echo 'source ~/.cargo/env' >> ~/.bashrc
        rustup component add clippy rustfmt rust-analyzer
        ;;
    esac

    # Install Docker and Kubernetes tools
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Install Kubernetes tools
    echo "☸️ Installing Kubernetes tools..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Install k9s
    curl -sS https://webinstall.dev/k9s | bash

    # Install Terraform
    echo "🏗️ Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install -y terraform

    # Install Pulumi
    curl -fsSL https://get.pulumi.com | sh
    export PATH="$PATH:$HOME/.pulumi/bin"
    echo 'export PATH="$PATH:$HOME/.pulumi/bin"' >> ~/.bashrc

    # Install cloud CLIs
    echo "☁️ Installing cloud CLIs..."
    # AWS CLI
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip

    # Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

    # Google Cloud CLI
    curl https://sdk.cloud.google.com | bash

    # Install VS Code with enterprise extensions
    echo "💻 Installing VS Code with enterprise extensions..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install comprehensive VS Code extensions
    code --install-extension ms-vscode.vscode-json
    code --install-extension ms-python.python
    code --install-extension golang.go
    code --install-extension rust-lang.rust-analyzer
    code --install-extension ms-dotnettools.csharp
    code --install-extension redhat.java
    code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
    code --install-extension hashicorp.terraform
    code --install-extension ms-azuretools.vscode-docker
    code --install-extension GitHub.copilot
    code --install-extension GitHub.copilot-chat
    code --install-extension ms-playwright.playwright
    code --install-extension ms-vscode.remote-containers
    code --install-extension ms-vscode.remote-ssh

    # Configure Claude Flow Enterprise
    echo "⚙️ Configuring Claude Flow Enterprise in ${data.coder_parameter.claude_flow_mode.value} mode..."

    # Create comprehensive Claude Flow enterprise configuration
    mkdir -p ~/.claude-flow/enterprise
    cat > ~/.claude-flow/config.json << EOF
{
  "mode": "${data.coder_parameter.claude_flow_mode.value}",
  "enterprise": {
    "enabled": true,
    "team_orchestration": true,
    "neural_networking": true,
    "distributed_processing": true,
    "security": {
      "encrypted_memory": true,
      "secure_channels": true,
      "audit_logging": true
    }
  },
  "memory": {
    "type": "distributed",
    "primary": "sqlite",
    "replicas": 3,
    "persistent": true,
    "location": "/home/coder/.claude-flow/enterprise/memory.db",
    "encryption": true
  },
  "agents": {
    "enabled": true,
    "types": [
      "architect",
      "coder",
      "tester",
      "reviewer",
      "devops",
      "security",
      "performance",
      "documentation",
      "project-manager"
    ],
    "neural_network": true,
    "multi_threading": true,
    "load_balancing": true
  },
  "mcp_tools": {
    "enabled": true,
    "advanced_tools_count": 147,
    "enterprise_tools": true,
    "custom_integrations": true
  },
  "development_stack": "${data.coder_parameter.enterprise_stack.value}",
  "workspace": {
    "auto_organize": true,
    "intelligent_suggestions": true,
    "pattern_recognition": true,
    "code_generation": true,
    "architecture_analysis": true,
    "performance_optimization": true
  },
  "monitoring": {
    "level": "${data.coder_parameter.monitoring_level.value}",
    "metrics": true,
    "logging": true,
    "tracing": true,
    "alerting": true
  },
  "integrations": {
    "github": true,
    "gitlab": true,
    "jira": true,
    "slack": true,
    "teams": true,
    "jenkins": true,
    "kubernetes": true,
    "terraform": true
  }
}
EOF

    # Create enterprise project structure
    echo "📂 Creating enterprise project structure..."
    mkdir -p /home/coder/projects/{microservices,ai-research,web-applications,infrastructure,documentation}
    mkdir -p /home/coder/tools/{scripts,automation,monitoring}
    mkdir -p /home/coder/.config/{enterprise-tools,monitoring,security}

    # Set up enterprise development environment based on stack
    case "${data.coder_parameter.enterprise_stack.value}" in
      "full-enterprise")
        echo "🏢 Setting up full enterprise stack..."
        cd /home/coder/projects

        # Create microservices template
        mkdir -p microservices/user-service
        cd microservices/user-service
        # Initialize Spring Boot microservice
        curl https://start.spring.io/starter.zip \
          -d type=gradle-project \
          -d language=java \
          -d bootVersion=3.2.1 \
          -d baseDir=user-service \
          -d groupId=com.enterprise \
          -d artifactId=user-service \
          -d name=user-service \
          -d description="Enterprise User Service" \
          -d packageName=com.enterprise.userservice \
          -d packaging=jar \
          -d javaVersion=25 \
          -d dependencies=web,data-jpa,postgresql,actuator,security \
          -o user-service.zip
        unzip user-service.zip && rm user-service.zip

        # Create .NET microservice
        cd /home/coder/projects/microservices
        dotnet new webapi -n notification-service
        cd notification-service
        dotnet add package Microsoft.EntityFrameworkCore.Design
        dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
        ;;

      "cloud-native")
        echo "☁️ Setting up cloud-native stack..."
        cd /home/coder/projects

        # Create Go microservice
        mkdir -p microservices/api-gateway
        cd microservices/api-gateway
        go mod init enterprise/api-gateway

        # Create Kubernetes manifests
        mkdir -p k8s/{base,overlays/{dev,staging,prod}}

        # Create Helm chart
        helm create enterprise-app
        ;;

      "ai-research")
        echo "🧠 Setting up AI/ML research environment..."
        cd /home/coder/projects/ai-research

        # Create Python AI project
        poetry new ai-research-suite
        cd ai-research-suite
        poetry add torch transformers datasets jupyter pandas numpy scipy scikit-learn
        poetry add openai anthropic langchain crewai
        ;;
    esac

    # Set up monitoring and observability
    if [[ "${data.coder_parameter.monitoring_level.value}" == "enterprise" ]]; then
      echo "📊 Setting up enterprise monitoring..."

      # Install Prometheus node exporter
      wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
      tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
      sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
      rm -rf node_exporter-1.8.2.linux-amd64*

      # Create monitoring dashboard
      mkdir -p /home/coder/monitoring/dashboards
      cat > /home/coder/monitoring/docker-compose.yml << 'EOF'
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=enterprise123
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  grafana-data:
EOF
    fi

    # Create enterprise automation scripts
    mkdir -p /home/coder/tools/scripts
    cat > /home/coder/tools/scripts/enterprise-status.sh << 'EOF'
#!/bin/bash
echo "🏢 Enterprise Claude Flow Environment Status"
echo "==========================================="
echo "System Resources:"
echo "  CPU Cores: $(nproc)"
echo "  Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "  Disk: $(df -h /home/coder | awk 'NR==2 {print $4 " available"}')"
echo ""
echo "Development Stack:"
echo "  Node.js: $(node --version 2>/dev/null || echo 'Not installed')"
echo "  Python: $(python3 --version 2>/dev/null || echo 'Not installed')"
echo "  Java: $(java --version 2>/dev/null | head -n1 || echo 'Not installed')"
echo "  Go: $(go version 2>/dev/null || echo 'Not installed')"
echo "  Rust: $(rustc --version 2>/dev/null || echo 'Not installed')"
echo "  .NET: $(dotnet --version 2>/dev/null || echo 'Not installed')"
echo ""
echo "Claude Flow Configuration:"
echo "  Mode: ${data.coder_parameter.claude_flow_mode.value}"
echo "  Stack: ${data.coder_parameter.enterprise_stack.value}"
echo "  Monitoring: ${data.coder_parameter.monitoring_level.value}"
echo "  GPU Support: ${data.coder_parameter.enable_gpu.value}"
echo ""
echo "Enterprise Tools:"
echo "  Docker: $(docker --version 2>/dev/null || echo 'Not available')"
echo "  Kubernetes: $(kubectl version --client --short 2>/dev/null || echo 'Not available')"
echo "  Terraform: $(terraform --version 2>/dev/null | head -n1 || echo 'Not available')"
echo ""
echo "Ready for enterprise AI-powered development! 🚀"
EOF
    chmod +x /home/coder/tools/scripts/enterprise-status.sh

    # Set proper ownership
    sudo chown -R coder:coder /home/coder

    # Run enterprise status check
    /home/coder/tools/scripts/enterprise-status.sh

    echo "✅ Claude Code Flow Enterprise environment setup complete!"
    echo "Access your enterprise development environment through the applications below."

  EOT

}

# Metadata
resource "coder_metadata" "claude_flow_mode" {
  resource_id = coder_agent.main.id
  item {
    key   = "claude_flow_mode"
    value = data.coder_parameter.claude_flow_mode.value
  }
}

resource "coder_metadata" "enterprise_stack" {
  resource_id = coder_agent.main.id
  item {
    key   = "enterprise_stack"
    value = data.coder_parameter.enterprise_stack.value
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

resource "coder_metadata" "gpu_support" {
  resource_id = coder_agent.main.id
  item {
    key   = "gpu_enabled"
    value = tostring(data.coder_parameter.enable_gpu.value)
  }
}

resource "coder_metadata" "monitoring_level" {
  resource_id = coder_agent.main.id
  item {
    key   = "monitoring_level"
    value = data.coder_parameter.monitoring_level.value
  }
}

# Applications
resource "coder_app" "claude_flow_enterprise" {
  agent_id     = coder_agent.main.id
  slug         = "claude-flow-enterprise"
  display_name = "Claude Flow Enterprise"
  url          = "http://localhost:3000"
  icon         = "/icon/enterprise.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:3000"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code Enterprise"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/projects"
  share        = "owner"
}

resource "coder_app" "jupyter" {
  count        = contains(["full-enterprise", "ai-research"], data.coder_parameter.enterprise_stack.value) ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "jupyter"
  display_name = "JupyterLab Enterprise"
  url          = "http://localhost:8888"
  icon         = "/icon/jupyter.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "monitoring" {
  count        = data.coder_parameter.monitoring_level.value == "enterprise" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "monitoring"
  display_name = "Enterprise Monitoring"
  url          = "http://localhost:3001"
  icon         = "/icon/grafana.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Enterprise Terminal"
  icon         = "/icon/terminal.svg"
  command      = "zsh"
  share        = "owner"
}

# Kubernetes resources with enterprise-grade configuration
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace

    labels = {
      "enterprise" = "true"
      "tier"       = "premium"
    }
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "fast-ssd" # Use premium storage class

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
      "enterprise"                 = "true"
      "tier"                       = "premium"
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
          "enterprise"                  = "true"
        }

        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9100"
        }
      }

      spec {
        security_context {
          run_as_user     = 1000
          run_as_group    = 1000
          run_as_non_root = true
          fs_group        = 1000
        }

        # Use node with GPU if requested
        node_selector = data.coder_parameter.enable_gpu.value ? {
          accelerator = "nvidia-tesla-k80"
        } : {}

        container {
          name              = "dev"
          image             = "ubuntu:24.04"
          image_pull_policy = "Always"
          command           = ["/bin/bash", "-c", coder_agent.main.init_script]

          security_context {
            run_as_user                = 1000
            run_as_non_root            = true
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          liveness_probe {
            exec {
              command = ["pgrep", "-f", "coder"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["pgrep", "-f", "coder"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          env {
            name  = "ENTERPRISE_MODE"
            value = "true"
          }

          # GPU support (conditional)
          dynamic "env" {
            for_each = data.coder_parameter.enable_gpu.value ? [1] : []
            content {
              name  = "NVIDIA_VISIBLE_DEVICES"
              value = "all"
            }
          }

          dynamic "env" {
            for_each = data.coder_parameter.enable_gpu.value ? [1] : []
            content {
              name  = "NVIDIA_DRIVER_CAPABILITIES"
              value = "compute,utility"
            }
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

          # Additional mounts for enterprise features
          volume_mount {
            mount_path = "/tmp"
            name       = "tmp-volume"
            read_only  = false
          }

          volume_mount {
            mount_path = "/var/cache"
            name       = "cache"
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

        volume {
          name = "tmp-volume"
          empty_dir {}
        }

        volume {
          name = "cache"
          empty_dir {
            size_limit = "5Gi"
          }
        }

        # Anti-affinity for better resource distribution
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
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

        # Toleration for dedicated nodes
        toleration {
          key      = "enterprise-workloads"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.home]
}
