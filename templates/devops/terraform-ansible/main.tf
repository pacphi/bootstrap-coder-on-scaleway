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
  default      = "50"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = false
  validation {
    min = 20
    max = 200
  }
}

data "coder_parameter" "terraform_version" {
  name         = "terraform_version"
  display_name = "Terraform Version"
  description  = "Terraform version to install"
  default      = "1.12"
  icon         = "/icon/terraform.svg"
  mutable      = false
  option {
    name  = "Terraform 1.12"
    value = "1.12"
  }
  option {
    name  = "Terraform 1.13"
    value = "1.13"
  }
  option {
    name  = "Terraform 1.14"
    value = "1.14"
  }
}

data "coder_parameter" "ansible_version" {
  name         = "ansible_version"
  display_name = "Ansible Version"
  description  = "Ansible version to install"
  default      = "latest"
  icon         = "/icon/ansible.svg"
  mutable      = false
  option {
    name  = "Ansible 7.x"
    value = "7"
  }
  option {
    name  = "Ansible 8.x"
    value = "8"
  }
  option {
    name  = "Latest"
    value = "latest"
  }
}

data "coder_parameter" "cloud_providers" {
  name         = "cloud_providers"
  display_name = "Cloud Provider Tools"
  description  = "Cloud provider CLI tools to install"
  default      = "aws,gcp,azure"
  icon         = "/icon/cloud.svg"
  mutable      = false
  option {
    name  = "AWS + GCP + Azure"
    value = "aws,gcp,azure"
  }
  option {
    name  = "AWS Only"
    value = "aws"
  }
  option {
    name  = "GCP Only"
    value = "gcp"
  }
  option {
    name  = "Azure Only"
    value = "azure"
  }
  option {
    name  = "All + DigitalOcean"
    value = "aws,gcp,azure,do"
  }
}

data "coder_parameter" "container_tools" {
  name         = "container_tools"
  display_name = "Container Tools"
  description  = "Container and orchestration tools"
  default      = "docker,kubernetes"
  icon         = "/icon/container.svg"
  mutable      = false
  option {
    name  = "Docker + Kubernetes"
    value = "docker,kubernetes"
  }
  option {
    name  = "Docker + K8s + Helm"
    value = "docker,kubernetes,helm"
  }
  option {
    name  = "All Tools"
    value = "docker,kubernetes,helm,istio"
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

    echo "🔧 Setting up Terraform + Ansible DevOps environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y \
      curl \
      wget \
      git \
      unzip \
      jq \
      yq \
      tree \
      htop \
      vim \
      nano \
      build-essential \
      software-properties-common \
      apt-transport-https \
      ca-certificates \
      gnupg \
      lsb-release \
      python3 \
      python3-pip \
      python3-venv \
      sshpass \
      rsync

    # Install Python packages for Ansible
    echo "🐍 Installing Python dependencies..."
    python3 -m pip install --user --upgrade pip
    python3 -m pip install --user \
      requests \
      boto3 \
      botocore \
      google-auth \
      google-cloud-storage \
      azure-identity \
      azure-mgmt-resource \
      azure-mgmt-compute \
      netaddr \
      jinja2 \
      paramiko \
      cryptography \
      pyyaml

    # Install Terraform ${data.coder_parameter.terraform_version.value}
    echo "🏗️ Installing Terraform ${data.coder_parameter.terraform_version.value}..."
    TERRAFORM_VERSION="${data.coder_parameter.terraform_version.value}"
    if [[ "$TERRAFORM_VERSION" != "latest" ]]; then
      TERRAFORM_VERSION="${data.coder_parameter.terraform_version.value}.6"
    fi

    wget -O terraform.zip "https://releases.hashicorp.com/terraform/$${TERRAFORM_VERSION}/terraform_$${TERRAFORM_VERSION}_linux_amd64.zip"
    sudo unzip terraform.zip -d /usr/local/bin/
    rm terraform.zip
    sudo chmod +x /usr/local/bin/terraform

    # Install Ansible ${data.coder_parameter.ansible_version.value}
    echo "📚 Installing Ansible ${data.coder_parameter.ansible_version.value}..."
    if [[ "${data.coder_parameter.ansible_version.value}" == "latest" ]]; then
      python3 -m pip install --user ansible
    else
      python3 -m pip install --user "ansible==${data.coder_parameter.ansible_version.value}.*"
    fi

    # Add user bin to PATH
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"

    # Install Ansible collections
    ansible-galaxy collection install \
      community.general \
      community.crypto \
      community.docker \
      kubernetes.core \
      amazon.aws \
      google.cloud \
      azure.azcollection

    # Install cloud provider tools based on selection
    IFS=',' read -ra PROVIDERS <<< "${data.coder_parameter.cloud_providers.value}"
    for provider in "$${PROVIDERS[@]}"; do
      case "$provider" in
        "aws")
          echo "☁️ Installing AWS CLI..."
          curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
          unzip awscliv2.zip
          sudo ./aws/install
          rm -rf aws awscliv2.zip

          # Install Terragrunt
          TERRAGRUNT_VERSION=$(curl -s https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest | jq -r .tag_name)
          wget -O terragrunt "https://github.com/gruntwork-io/terragrunt/releases/download/$${TERRAGRUNT_VERSION}/terragrunt_linux_amd64"
          sudo mv terragrunt /usr/local/bin/
          sudo chmod +x /usr/local/bin/terragrunt
          ;;
        "gcp")
          echo "☁️ Installing Google Cloud SDK..."
          echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
          curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
          sudo apt-get update && sudo apt-get install -y google-cloud-cli
          ;;
        "azure")
          echo "☁️ Installing Azure CLI..."
          curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
          ;;
        "do")
          echo "☁️ Installing DigitalOcean CLI..."
          DOCTL_VERSION=$(curl -s https://api.github.com/repos/digitalocean/doctl/releases/latest | jq -r .tag_name)
          wget -O doctl.tar.gz "https://github.com/digitalocean/doctl/releases/download/$${DOCTL_VERSION}/doctl-$${DOCTL_VERSION#v}-linux-amd64.tar.gz"
          tar xf doctl.tar.gz
          sudo mv doctl /usr/local/bin
          rm doctl.tar.gz
          ;;
      esac
    done

    # Install container tools
    IFS=',' read -ra TOOLS <<< "${data.coder_parameter.container_tools.value}"
    for tool in "$${TOOLS[@]}"; do
      case "$tool" in
        "docker")
          echo "🐳 Installing Docker..."
          curl -fsSL https://get.docker.com -o get-docker.sh
          sudo sh get-docker.sh
          sudo usermod -aG docker coder
          sudo systemctl enable docker --now
          rm get-docker.sh

          # Install Docker Compose
          COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
          sudo curl -L "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
          sudo chmod +x /usr/local/bin/docker-compose
          ;;
        "kubernetes")
          echo "☸️ Installing Kubernetes tools..."
          # kubectl
          KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
          curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
          sudo install kubectl /usr/local/bin/
          rm kubectl

          # kubectx and kubens
          sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
          sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
          sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

          # k9s
          K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
          wget -O k9s.tar.gz "https://github.com/derailed/k9s/releases/download/$${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
          tar xf k9s.tar.gz k9s
          sudo mv k9s /usr/local/bin/
          rm k9s.tar.gz
          ;;
        "helm")
          echo "⛵ Installing Helm..."
          curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
          echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
          sudo apt-get update
          sudo apt-get install -y helm
          ;;
        "istio")
          echo "🕸️ Installing Istio..."
          ISTIO_VERSION=$(curl -s https://api.github.com/repos/istio/istio/releases/latest | jq -r .tag_name)
          curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$${ISTIO_VERSION} TARGET_ARCH=x86_64 sh -
          sudo mv istio-$${ISTIO_VERSION}/bin/istioctl /usr/local/bin/
          rm -rf istio-$${ISTIO_VERSION}
          ;;
      esac
    done

    # Install additional DevOps tools
    echo "🛠️ Installing additional DevOps tools..."

    # Packer
    PACKER_VERSION=$(curl -s https://api.github.com/repos/hashicorp/packer/releases/latest | jq -r .tag_name | cut -c 2-)
    wget -O packer.zip "https://releases.hashicorp.com/packer/$${PACKER_VERSION}/packer_$${PACKER_VERSION}_linux_amd64.zip"
    sudo unzip packer.zip -d /usr/local/bin/
    rm packer.zip

    # Vault
    VAULT_VERSION=$(curl -s https://api.github.com/repos/hashicorp/vault/releases/latest | jq -r .tag_name | cut -c 2-)
    wget -O vault.zip "https://releases.hashicorp.com/vault/$${VAULT_VERSION}/vault_$${VAULT_VERSION}_linux_amd64.zip"
    sudo unzip vault.zip -d /usr/local/bin/
    rm vault.zip

    # Consul
    CONSUL_VERSION=$(curl -s https://api.github.com/repos/hashicorp/consul/releases/latest | jq -r .tag_name | cut -c 2-)
    wget -O consul.zip "https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip"
    sudo unzip consul.zip -d /usr/local/bin/
    rm consul.zip

    # Install VS Code
    echo "💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install VS Code extensions
    code --install-extension HashiCorp.terraform
    code --install-extension ms-vscode.ansible
    code --install-extension ms-python.python
    code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
    code --install-extension ms-azuretools.vscode-docker
    code --install-extension redhat.vscode-yaml
    code --install-extension ms-vscode.vscode-json
    code --install-extension GitHub.copilot
    code --install-extension ms-vscode-remote.remote-containers
    code --install-extension hashicorp.hcl

    # Create project structure
    cd /home/coder
    mkdir -p {terraform/{modules,environments/{dev,staging,prod},providers},ansible/{playbooks,roles,inventories,group_vars,host_vars},scripts,docs}

    # Create sample Terraform configuration
    cat > terraform/main.tf << 'EOF'
# Example Terraform configuration
terraform {
  required_version = ">= ${data.coder_parameter.terraform_version.value}"

  required_providers {
    # Add providers as needed
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Example provider configuration
provider "local" {}

# Example resource
resource "local_file" "example" {
  filename = "$${path.module}/example.txt"
  content  = "Hello from Terraform!"
}

# Output example
output "example_file_path" {
  description = "Path to the example file"
  value       = local_file.example.filename
}
EOF

    # Create sample Terraform module
    mkdir -p terraform/modules/example-module
    cat > terraform/modules/example-module/main.tf << 'EOF'
# Example Terraform module
variable "name" {
  description = "Name for the resource"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

resource "local_file" "module_example" {
  filename = "$${path.module}/example-$${var.name}.txt"
  content  = "Module example for $${var.name} in $${var.environment}"
}

output "file_path" {
  description = "Path to the generated file"
  value       = local_file.module_example.filename
}
EOF

    cat > terraform/modules/example-module/variables.tf << 'EOF'
variable "name" {
  description = "Name for the resource"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
EOF

    cat > terraform/modules/example-module/outputs.tf << 'EOF'
output "file_path" {
  description = "Path to the generated file"
  value       = local_file.module_example.filename
}

output "resource_name" {
  description = "Name of the resource"
  value       = var.name
}
EOF

    # Create environment-specific configurations
    cat > terraform/environments/dev/main.tf << 'EOF'
terraform {
  required_version = ">= ${data.coder_parameter.terraform_version.value}"
}

module "example" {
  source = "../../modules/example-module"

  name        = "dev-example"
  environment = "development"

  tags = {
    Environment = "dev"
    Project     = "example"
    ManagedBy   = "terraform"
  }
}
EOF

    # Create sample Ansible inventory
    cat > ansible/inventories/hosts.yml << 'EOF'
---
all:
  children:
    web:
      hosts:
        web1:
          ansible_host: 10.0.1.10
        web2:
          ansible_host: 10.0.1.11
      vars:
        http_port: 80
        max_clients: 200

    db:
      hosts:
        db1:
          ansible_host: 10.0.2.10
        db2:
          ansible_host: 10.0.2.11
      vars:
        db_port: 5432

    development:
      children:
        web:
        db:
      vars:
        environment: dev

    production:
      children:
        web:
        db:
      vars:
        environment: prod
EOF

    # Create sample Ansible playbook
    cat > ansible/playbooks/site.yml << 'EOF'
---
- name: Configure web servers
  hosts: web
  become: yes
  roles:
    - common
    - nginx

  tasks:
    - name: Ensure nginx is running
      systemd:
        name: nginx
        state: started
        enabled: yes

- name: Configure database servers
  hosts: db
  become: yes
  roles:
    - common
    - postgresql

  tasks:
    - name: Ensure postgresql is running
      systemd:
        name: postgresql
        state: started
        enabled: yes
EOF

    # Create sample Ansible role
    mkdir -p ansible/roles/common/{tasks,handlers,templates,files,vars,defaults,meta}

    cat > ansible/roles/common/tasks/main.yml << 'EOF'
---
- name: Update package cache
  apt:
    update_cache: yes
    cache_valid_time: 86400
  when: ansible_os_family == "Debian"

- name: Install common packages
  package:
    name:
      - curl
      - wget
      - git
      - htop
      - tree
      - vim
    state: present

- name: Create common directories
  file:
    path: "{{ item }}"
    state: directory
    mode: '0755'
  loop:
    - /opt/scripts
    - /var/log/applications

- name: Copy common configuration
  template:
    src: common.conf.j2
    dest: /etc/common.conf
    mode: '0644'
  notify: restart common service

- name: Ensure common services are configured
  systemd:
    daemon_reload: yes
EOF

    cat > ansible/roles/common/handlers/main.yml << 'EOF'
---
- name: restart common service
  systemd:
    name: "{{ item }}"
    state: restarted
  loop:
    - rsyslog
    - cron
EOF

    cat > ansible/roles/common/defaults/main.yml << 'EOF'
---
common_packages:
  - curl
  - wget
  - git
  - htop
  - tree
  - vim

common_user: appuser
common_group: appgroup
common_log_level: info
EOF

    cat > ansible/roles/common/templates/common.conf.j2 << 'EOF'
# Common configuration file
# Generated by Ansible

[logging]
level = {{ common_log_level }}
path = /var/log/applications

[user]
default_user = {{ common_user }}
default_group = {{ common_group }}

[environment]
name = {{ environment | default('development') }}
managed_by = ansible
EOF

    # Create group_vars
    cat > ansible/group_vars/all.yml << 'EOF'
---
# Global variables for all hosts
timezone: "UTC"
ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org
  - 2.pool.ntp.org

# Security settings
ssh_port: 22
allow_password_auth: false
allow_root_login: false

# Application settings
app_user: appuser
app_group: appgroup
app_home: /opt/app
EOF

    cat > ansible/group_vars/web.yml << 'EOF'
---
# Variables specific to web servers
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65

# SSL configuration
ssl_certificate: /etc/ssl/certs/server.crt
ssl_certificate_key: /etc/ssl/private/server.key
EOF

    # Create ansible.cfg
    cat > ansible/ansible.cfg << 'EOF'
[defaults]
inventory = inventories/hosts.yml
roles_path = roles
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
gathering = smart
fact_caching = memory

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
control_path = ~/.ansible/cp/ansible-ssh-%%h-%%p-%%r
EOF

    # Create utility scripts
    cat > scripts/terraform-init-all.sh << 'EOF'
#!/bin/bash
# Initialize all Terraform environments

set -e

ENVIRONMENTS=("dev" "staging" "prod")

for env in "$${ENVIRONMENTS[@]}"; do
  echo "Initializing Terraform for $env environment..."
  cd "/home/coder/terraform/environments/$env"
  terraform init
  echo "✅ $env environment initialized"
done

echo "🎉 All Terraform environments initialized successfully!"
EOF

    cat > scripts/ansible-syntax-check.sh << 'EOF'
#!/bin/bash
# Check Ansible playbook syntax

set -e

cd /home/coder/ansible

echo "🔍 Checking Ansible playbook syntax..."

# Check main playbook
ansible-playbook --syntax-check playbooks/site.yml

# Check all playbooks in the directory
for playbook in playbooks/*.yml; do
  if [[ -f "$playbook" ]]; then
    echo "Checking $playbook..."
    ansible-playbook --syntax-check "$playbook"
  fi
done

echo "✅ All playbooks syntax check passed!"
EOF

    cat > scripts/infrastructure-plan.sh << 'EOF'
#!/bin/bash
# Generate Terraform plan for all environments

set -e

ENVIRONMENTS=("dev" "staging" "prod")

for env in "$${ENVIRONMENTS[@]}"; do
  echo "🔍 Generating Terraform plan for $env..."
  cd "/home/coder/terraform/environments/$env"

  if [[ -f "terraform.tfstate" ]] || terraform state list > /dev/null 2>&1; then
    terraform plan -out="$env.tfplan"
    echo "✅ Plan generated for $env: $env.tfplan"
  else
    echo "⚠️ No state found for $env, skipping plan"
  fi
done

echo "🎉 Infrastructure planning complete!"
EOF

    # Make scripts executable
    chmod +x scripts/*.sh

    # Create documentation
    cat > docs/README.md << 'EOF'
# DevOps Infrastructure as Code

This project contains Terraform configurations and Ansible playbooks for managing infrastructure and deployments.

## Project Structure

```
├── terraform/
│   ├── modules/          # Reusable Terraform modules
│   ├── environments/     # Environment-specific configurations
│   └── providers/        # Provider configurations
├── ansible/
│   ├── playbooks/        # Ansible playbooks
│   ├── roles/            # Ansible roles
│   ├── inventories/      # Inventory files
│   └── group_vars/       # Group variables
├── scripts/              # Utility scripts
└── docs/                 # Documentation
```

## Getting Started

### Terraform

1. Initialize environments:
   ```bash
   ./scripts/terraform-init-all.sh
   ```

2. Plan infrastructure changes:
   ```bash
   ./scripts/infrastructure-plan.sh
   ```

3. Apply changes (example for dev):
   ```bash
   cd terraform/environments/dev
   terraform apply
   ```

### Ansible

1. Check playbook syntax:
   ```bash
   ./scripts/ansible-syntax-check.sh
   ```

2. Run a playbook:
   ```bash
   cd ansible
   ansible-playbook -i inventories/hosts.yml playbooks/site.yml
   ```

3. Run for specific environment:
   ```bash
   ansible-playbook -i inventories/hosts.yml playbooks/site.yml --limit development
   ```

## Tools Installed

- Terraform ${data.coder_parameter.terraform_version.value}
- Ansible ${data.coder_parameter.ansible_version.value}
- Cloud CLIs: ${data.coder_parameter.cloud_providers.value}
- Container tools: ${data.coder_parameter.container_tools.value}
- HashiCorp suite (Vault, Consul, Packer)
- Kubernetes tools (kubectl, k9s, kubectx)

## Best Practices

1. **State Management**: Use remote state for Terraform
2. **Environment Isolation**: Keep environments completely separate
3. **Module Reusability**: Create reusable modules for common patterns
4. **Secret Management**: Use Vault or cloud-native secret managers
5. **Code Quality**: Run terraform fmt, terraform validate, and ansible-lint
6. **Documentation**: Keep documentation up to date

## Security

- Store secrets in dedicated secret management systems
- Use least privilege access principles
- Enable audit logging for all infrastructure changes
- Regularly rotate credentials and keys
EOF

    # Create workspace configuration
    cat > .vscode/settings.json << 'EOF'
{
    "terraform.experimentalFeatures.validateOnSave": true,
    "terraform.experimentalFeatures.prefillRequiredFields": true,
    "ansible.python.interpreterPath": "/usr/bin/python3",
    "ansible.ansibleLint.enabled": true,
    "files.associations": {
        "*.tf": "terraform",
        "*.tfvars": "terraform",
        "*.yml": "yaml",
        "*.yaml": "yaml"
    },
    "editor.formatOnSave": true,
    "[terraform]": {
        "editor.formatOnSave": true,
        "editor.codeActionsOnSave": {
            "source.organizeImports": true
        }
    },
    "[yaml]": {
        "editor.insertSpaces": true,
        "editor.tabSize": 2,
        "editor.autoIndent": "advanced"
    }
}
EOF

    mkdir -p .vscode

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Terraform
*.tfstate
*.tfstate.*
*.tfplan
.terraform/
.terraform.lock.hcl
*.tfvars
!terraform.tfvars.example

# Ansible
*.retry
.vault_pass.txt
host_vars/secrets.yml
group_vars/secrets.yml

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Logs
*.log

# Environment
.env
.env.local

# Credentials
credentials.json
service-account.json
*.pem
*.key
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder

    # Reload bash to get new PATH
    source ~/.bashrc

    echo "✅ Terraform + Ansible DevOps environment ready!"
    echo "🏗️ Terraform ${data.coder_parameter.terraform_version.value} installed"
    echo "📚 Ansible ${data.coder_parameter.ansible_version.value} installed"
    echo "☁️ Cloud providers: ${data.coder_parameter.cloud_providers.value}"
    echo "🐳 Container tools: ${data.coder_parameter.container_tools.value}"
    echo ""
    echo "📂 Project structure created with sample configurations"
    echo "🚀 Run './scripts/terraform-init-all.sh' to initialize Terraform"
    echo "🔍 Run './scripts/ansible-syntax-check.sh' to validate Ansible"

  EOT

}

# Metadata
resource "coder_metadata" "terraform_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "terraform_version"
    value = data.coder_parameter.terraform_version.value
  }
}

resource "coder_metadata" "ansible_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "ansible_version"
    value = data.coder_parameter.ansible_version.value
  }
}

resource "coder_metadata" "cloud_providers" {
  resource_id = coder_agent.main.id
  item {
    key   = "cloud_providers"
    value = data.coder_parameter.cloud_providers.value
  }
}

resource "coder_metadata" "container_tools" {
  resource_id = coder_agent.main.id
  item {
    key   = "container_tools"
    value = data.coder_parameter.container_tools.value
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

# Applications
resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder"
  share        = "owner"
}

resource "coder_app" "terraform_docs" {
  agent_id     = coder_agent.main.id
  slug         = "terraform-docs"
  display_name = "Terraform Docs"
  url          = "http://localhost:8080"
  icon         = "/icon/terraform.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080"
    interval  = 15
    threshold = 30
  }
}

resource "coder_app" "k9s" {
  agent_id     = coder_agent.main.id
  slug         = "k9s"
  display_name = "k9s"
  icon         = "/icon/kubernetes.svg"
  command      = "k9s"
  share        = "owner"
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

    labels = {
      "devops-workspace" = "true"
    }
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "fast-ssd" # Use fast storage for DevOps workloads

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
      "devops-workspace"           = "true"
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
          "devops-workspace"            = "true"
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

          volume_mount {
            mount_path = "/var/lib/docker"
            name       = "docker-storage"
            read_only  = false
          }

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
          name = "docker-storage"
          empty_dir {
            size_limit = "20Gi"
          }
        }

        volume {
          name = "tmp-volume"
          empty_dir {}
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

        # Toleration for DevOps workloads
        toleration {
          key      = "devops-workloads"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.home]
}
