# Prerequisites

Detailed setup instructions for Scaleway account, tools installation, environment variables, and GitHub Actions configuration.

Before deploying Coder on Scaleway, ensure you have the following:

## 1. Scaleway Account

- **Create an account** at [scaleway.com](https://www.scaleway.com)
- **Generate API keys** in the [Scaleway Console](https://console.scaleway.com/iam/api-keys)
- **Note your Project and Organization IDs** from the
  - [Project Dashboard](https://console.scaleway.com/project/settings)
  - [Organization Dashboard](https://console.scaleway.com/organization)

## 2. Required Tools

Install the following tools on your local machine:

### macOS (using Homebrew)

```bash
# Install all required tools
brew install terraform kubectl helm jq curl

# Alternative: Install specific versions
brew install terraform@1.12
brew install kubernetes-cli@1.32
brew install helm@3.12
```

### Ubuntu/Debian

```bash
# Update package index
sudo apt-get update

# Install basic tools
sudo apt-get install -y curl jq git

# Install Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### RHEL/CentOS/Fedora

```bash
# Install basic tools
sudo yum install -y curl jq git

# Install Terraform
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo yum -y install terraform

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Windows (using Chocolatey or Scoop)

```powershell
# Using Chocolatey
choco install terraform kubernetes-cli kubernetes-helm jq curl git

# Using Scoop
scoop install terraform kubectl helm jq curl git
```

### Verify Installation

```bash
# Check all tools are installed with correct versions
terraform version   # Must be >= 1.12.0
kubectl version --client   # Must be >= 1.32.0
helm version        # Must be >= 3.12.0
jq --version        # Any recent version
curl --version      # Any recent version
git --version       # Any recent version
```

## 3. Environment Variables

Set up your Scaleway credentials:

```bash
# Required credentials
export SCW_ACCESS_KEY="your-scaleway-access-key"
export SCW_SECRET_KEY="your-scaleway-secret-key"
export SCW_DEFAULT_PROJECT_ID="your-project-id"
export SCW_DEFAULT_ORGANIZATION_ID="your-organization-id"

# Optional: Set default region (defaults to fr-par)
export SCW_DEFAULT_REGION="fr-par"
export SCW_DEFAULT_ZONE="fr-par-1"

# Save to your shell profile for persistence
echo 'export SCW_ACCESS_KEY="your-scaleway-access-key"' >> ~/.bashrc
echo 'export SCW_SECRET_KEY="your-scaleway-secret-key"' >> ~/.bashrc
echo 'export SCW_DEFAULT_PROJECT_ID="your-project-id"' >> ~/.bashrc
echo 'export SCW_DEFAULT_ORGANIZATION_ID="your-organization-id"' >> ~/.bashrc
```

## 4. Optional Tools

### GitHub CLI (Required for GitHub Actions deployment)

If you plan to use GitHub Actions for deployment:

```bash
# macOS
brew install gh

# Ubuntu/Debian
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh

# RHEL/CentOS/Fedora
sudo dnf install 'dnf-command(config-manager)'
sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
sudo dnf install gh

# Windows
choco install gh          # Chocolatey
scoop install gh          # Scoop

# Authenticate with GitHub
gh auth login
```

## 5. Verify Prerequisites

Once everything is installed, verify your setup:

```bash
# Clone the repository
git clone https://github.com/your-org/bootstrap-coder-on-scaleway.git
cd bootstrap-coder-on-scaleway

# Run prerequisite check
./scripts/test-runner.sh --suite=prerequisites
```

## 6. GitHub Actions Configuration (Optional)

For automatic staging deployments via GitHub Actions:

**Repository Secret Configuration**:

```bash
# In your GitHub repository settings, add this secret:
ENABLE_AUTO_STAGING_DEPLOY=true  # Enables automatic staging deployment on push/PR
```

**Note**: This is a feature flag that controls continuous deployment. Set to `true` only when you want automatic deployments enabled. When not set or set to any other value, automatic deployments are disabled while manual deployments continue to work.
