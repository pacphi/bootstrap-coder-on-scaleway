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
  option {
    name  = "12 Cores"
    value = "12"
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
    name  = "24 GB"
    value = "24"
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
    min = 10
    max = 200
  }
}

data "coder_parameter" "claude_flow_mode" {
  name         = "claude_flow_mode"
  display_name = "Claude Flow Mode"
  description  = "Choose the Claude Flow deployment mode"
  default      = "hive-mind"
  icon         = "/icon/ai.svg"
  mutable      = false
  option {
    name  = "Swarm Mode (Quick tasks)"
    value = "swarm"
  }
  option {
    name  = "Hive-Mind Mode (Complex projects)"
    value = "hive-mind"
  }
}

data "coder_parameter" "development_stack" {
  name         = "development_stack"
  display_name = "Development Stack"
  description  = "Choose primary development stack for Claude Flow integration"
  default      = "fullstack"
  icon         = "/icon/code.svg"
  mutable      = false
  option {
    name  = "Full Stack (Node.js + Python + Go)"
    value = "fullstack"
  }
  option {
    name  = "Python AI/ML Stack"
    value = "python-ai"
  }
  option {
    name  = "JavaScript/TypeScript Stack"
    value = "javascript"
  }
  option {
    name  = "Go + Rust Stack"
    value = "go-rust"
  }
}

data "coder_parameter" "enable_gpu" {
  name         = "enable_gpu"
  display_name = "Enable GPU Support"
  description  = "Enable GPU support for AI workloads"
  default      = "false"
  type         = "bool"
  icon         = "/icon/gpu.svg"
  mutable      = false
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

    echo "🚀 Setting up Claude Code Flow Environment..."

    # Update system
    sudo apt-get update
    sudo apt-get upgrade -y

    # Install essential tools
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
      lsb-release

    # Install Node.js 22 LTS
    echo "📦 Installing Node.js 22 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # Verify Node.js installation
    node --version
    npm --version

    # Install Claude Code globally
    echo "🤖 Installing Claude Code..."
    sudo npm install -g @anthropic-ai/claude-code

    # Skip permissions for automated setup
    echo "⚠️ Configuring Claude Code with dangerously-skip-permissions..."
    claude --dangerously-skip-permissions || true

    # Install Claude Flow v2.0.0 Alpha
    echo "🧠 Installing Claude Flow v2.0.0 Alpha..."
    cd /home/coder
    npx claude-flow@alpha init --force

    # Development stack specific installations
    case "${data.coder_parameter.development_stack.value}" in
      "fullstack"|"python-ai")
        echo "🐍 Installing Python stack..."
        sudo apt-get install -y python3.13 python3.13-dev python3.13-venv python3-pip
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 1
        sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.13 1

        # Install Poetry
        curl -sSL https://install.python-poetry.org | python3 -
        export PATH="/home/coder/.local/bin:$PATH"
        echo 'export PATH="/home/coder/.local/bin:$PATH"' >> /home/coder/.bashrc

        # Install AI/ML libraries for python-ai stack
        if [[ "${data.coder_parameter.development_stack.value}" == "python-ai" ]]; then
          pip3 install --user torch torchvision torchaudio transformers datasets huggingface_hub
          pip3 install --user jupyter jupyterlab pandas numpy scipy matplotlib seaborn scikit-learn
          pip3 install --user openai anthropic langchain crewai
        fi
        ;;
    esac

    case "${data.coder_parameter.development_stack.value}" in
      "fullstack"|"go-rust")
        echo "🔧 Installing Go..."
        wget -q https://golang.org/dl/go1.21.5.linux-amd64.tar.gz -O /tmp/go.tar.gz
        sudo tar -C /usr/local -xzf /tmp/go.tar.gz
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/coder/.bashrc
        export PATH=$PATH:/usr/local/go/bin

        if [[ "${data.coder_parameter.development_stack.value}" == "go-rust" ]]; then
          echo "🦀 Installing Rust..."
          curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
          source /home/coder/.cargo/env
          echo 'source /home/coder/.cargo/env' >> /home/coder/.bashrc
        fi
        ;;
    esac

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
    echo "☸️ Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Install Terraform
    echo "🏗️ Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install -y terraform

    # Install VS Code
    echo "💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install useful VS Code extensions for Claude Flow
    code --install-extension ms-vscode.vscode-json
    code --install-extension ms-python.python
    code --install-extension golang.go
    code --install-extension rust-lang.rust-analyzer
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension ms-vscode.vscode-typescript-next
    code --install-extension GitHub.copilot

    # Configure Claude Flow with chosen mode
    echo "⚙️ Configuring Claude Flow in ${data.coder_parameter.claude_flow_mode.value} mode..."

    # Create Claude Flow configuration
    cat > /home/coder/.claude-flow/config.json << EOF
{
  "mode": "${data.coder_parameter.claude_flow_mode.value}",
  "memory": {
    "type": "sqlite",
    "persistent": true,
    "location": "/home/coder/.claude-flow/memory.db"
  },
  "agents": {
    "enabled": true,
    "types": ["architect", "coder", "tester", "reviewer"],
    "neural_network": true
  },
  "mcp_tools": {
    "enabled": true,
    "advanced_tools_count": 87
  },
  "development_stack": "${data.coder_parameter.development_stack.value}",
  "workspace": {
    "auto_organize": true,
    "intelligent_suggestions": true,
    "pattern_recognition": true
  }
}
EOF

    # Create sample projects based on stack
    echo "📂 Creating sample projects..."
    mkdir -p /home/coder/projects
    cd /home/coder/projects

    case "${data.coder_parameter.development_stack.value}" in
      "fullstack")
        # Create a full-stack sample project
        npx create-next-app@latest claude-flow-fullstack --typescript --tailwind --app --src-dir --import-alias "@/*" --no-turbopack
        cd claude-flow-fullstack
        npm install @anthropic-ai/claude-code

        # Create a Claude Flow integration example
        cat > src/lib/claude-flow.ts << 'JSEOF'
// Claude Flow integration for Next.js
export class ClaudeFlowIntegration {
  constructor() {
    // Initialize Claude Flow connection
  }

  async executeSwarm(task: string) {
    // Execute swarm-based quick tasks
    console.log('Executing swarm task:', task);
  }

  async executeHiveMind(project: string) {
    // Execute hive-mind complex project orchestration
    console.log('Executing hive-mind project:', project);
  }
}
JSEOF
        ;;

      "python-ai")
        # Create AI/ML sample project
        mkdir -p claude-flow-ai
        cd claude-flow-ai
        /home/coder/.local/bin/poetry init --name="claude-flow-ai" --description="AI/ML project with Claude Flow" --author="Coder" --no-interaction
        /home/coder/.local/bin/poetry add jupyter pandas numpy torch transformers langchain openai anthropic

        # Create sample AI notebook
        cat > ai_workflow.py << 'PYEOF'
"""
Claude Flow AI/ML Workflow Example
Demonstrates integration between Claude Flow and AI/ML stack
"""

import pandas as pd
import numpy as np
from transformers import pipeline
import json

class ClaudeFlowAI:
    def __init__(self):
        self.sentiment_analyzer = pipeline("sentiment-analysis")
        self.text_generator = pipeline("text-generation", model="gpt2")

    def analyze_data(self, data):
        """Analyze data using AI models with Claude Flow orchestration"""
        results = []
        for item in data:
            sentiment = self.sentiment_analyzer(item['text'])[0]
            results.append({
                'text': item['text'],
                'sentiment': sentiment['label'],
                'confidence': sentiment['score']
            })
        return results

    def generate_insights(self, analysis_results):
        """Generate insights using Claude Flow agents"""
        # This would integrate with Claude Flow's hive-mind mode
        print("Generating insights with Claude Flow agents...")
        return analysis_results

if __name__ == "__main__":
    ai_flow = ClaudeFlowAI()
    sample_data = [
        {'text': 'Claude Flow is amazing for AI development!'},
        {'text': 'This integration makes development so much easier.'}
    ]
    results = ai_flow.analyze_data(sample_data)
    print(json.dumps(results, indent=2))
PYEOF
        ;;

      "javascript")
        # Create JavaScript/TypeScript sample project
        npm init -y
        npm install -D typescript @types/node ts-node
        npm install @anthropic-ai/claude-code axios dotenv

        cat > claude-flow-js.ts << 'TSEOF'
/**
 * Claude Flow JavaScript/TypeScript Integration
 * Demonstrates swarm and hive-mind mode usage
 */

class ClaudeFlowJS {
  private mode: 'swarm' | 'hive-mind';

  constructor(mode: 'swarm' | 'hive-mind' = 'hive-mind') {
    this.mode = mode;
  }

  async executeTask(task: string): Promise<void> {
    console.log(`Executing task in $${this.mode} mode: $${task}`);

    if (this.mode === 'swarm') {
      await this.swarmExecution(task);
    } else {
      await this.hiveMindExecution(task);
    }
  }

  private async swarmExecution(task: string): Promise<void> {
    // Quick task execution with swarm intelligence
    console.log('Swarm agents working on:', task);
  }

  private async hiveMindExecution(task: string): Promise<void> {
    // Complex project orchestration with hive-mind
    console.log('Hive-mind orchestrating:', task);
  }
}

export { ClaudeFlowJS };
TSEOF
        ;;
    esac

    # Set proper ownership
    sudo chown -R coder:coder /home/coder

    # Create helpful scripts
    cat > /home/coder/claude-flow-status.sh << 'EOF'
#!/bin/bash
echo "🤖 Claude Flow Environment Status"
echo "================================"
echo "Node.js: $(node --version)"
echo "npm: $(npm --version)"
echo "Claude Code: $(claude --version 2>/dev/null || echo 'Not available')"
echo "Python: $(python3 --version)"
echo "Docker: $(docker --version)"
echo "kubectl: $(kubectl version --client --short)"
echo "Terraform: $(terraform --version | head -n1)"
echo ""
echo "Claude Flow Configuration:"
echo "Mode: ${data.coder_parameter.claude_flow_mode.value}"
echo "Stack: ${data.coder_parameter.development_stack.value}"
echo "Memory: $(ls -la /home/coder/.claude-flow/ 2>/dev/null | wc -l) files in config"
echo ""
echo "Ready for AI-powered development! 🚀"
EOF
    chmod +x /home/coder/claude-flow-status.sh

    # Run status check
    /home/coder/claude-flow-status.sh

    echo "✅ Claude Code Flow environment setup complete!"

EOT

}

# Metadata
resource "coder_metadata" "claude_flow_mode" {
  resource_id = coder_agent.main.id
  item {
    key   = "mode"
    value = data.coder_parameter.claude_flow_mode.value
  }
}

resource "coder_metadata" "development_stack" {
  resource_id = coder_agent.main.id
  item {
    key   = "stack"
    value = data.coder_parameter.development_stack.value
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
    key   = "gpu"
    value = data.coder_parameter.enable_gpu.value ? "enabled" : "disabled"
  }
}

# Applications
resource "coder_app" "claude_flow_dashboard" {
  agent_id     = coder_agent.main.id
  slug         = "claude-flow"
  display_name = "Claude Flow Dashboard"
  url          = "http://localhost:3000"
  icon         = "/icon/ai.svg"
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
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/projects"
  share        = "owner"
}

resource "coder_app" "jupyter" {
  count        = contains(["fullstack", "python-ai"], data.coder_parameter.development_stack.value) ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "jupyter"
  display_name = "Jupyter Lab"
  url          = "http://localhost:8888"
  icon         = "/icon/jupyter.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8888"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "terminal" {
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Terminal"
  icon         = "/icon/terminal.svg"
  command      = "bash"
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
          run_as_user     = 1000
          run_as_group    = 1000
          run_as_non_root = true
          fs_group        = 1000
        }

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

          # GPU support (conditional)
          dynamic "env" {
            for_each = data.coder_parameter.enable_gpu.value ? [1] : []
            content {
              name  = "NVIDIA_VISIBLE_DEVICES"
              value = "all"
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

          # Additional mounts for Claude Flow
          volume_mount {
            mount_path = "/tmp"
            name       = "tmp-volume"
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