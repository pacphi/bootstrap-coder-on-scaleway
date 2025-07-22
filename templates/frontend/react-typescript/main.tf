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
  default      = "15"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = false
  validation {
    min = 10
    max = 100
  }
}

data "coder_parameter" "node_version" {
  name         = "node_version"
  display_name = "Node.js Version"
  description  = "Node.js version to install"
  default      = "20"
  icon         = "/icon/nodejs.svg"
  mutable      = false
  option {
    name  = "Node.js 18 LTS"
    value = "18"
  }
  option {
    name  = "Node.js 20 LTS"
    value = "20"
  }
  option {
    name  = "Node.js 21"
    value = "21"
  }
}

data "coder_parameter" "framework_template" {
  name         = "framework_template"
  display_name = "React Template"
  description  = "Choose React project template"
  default      = "vite-ts"
  icon         = "/icon/react.svg"
  mutable      = false
  option {
    name  = "Vite + TypeScript"
    value = "vite-ts"
  }
  option {
    name  = "Next.js App Router"
    value = "nextjs"
  }
  option {
    name  = "Create React App"
    value = "cra"
  }
}

data "coder_parameter" "ui_library" {
  name         = "ui_library"
  display_name = "UI Library"
  description  = "Choose UI component library"
  default      = "tailwind"
  icon         = "/icon/design.svg"
  mutable      = false
  option {
    name  = "Tailwind CSS"
    value = "tailwind"
  }
  option {
    name  = "Material-UI"
    value = "mui"
  }
  option {
    name  = "Ant Design"
    value = "antd"
  }
  option {
    name  = "Chakra UI"
    value = "chakra"
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

    echo "⚛️ Setting up React TypeScript development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential

    # Install Node.js ${data.coder_parameter.node_version.value}
    echo "📦 Installing Node.js ${data.coder_parameter.node_version.value}..."
    curl -fsSL https://deb.nodesource.com/setup_${data.coder_parameter.node_version.value}.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # Install pnpm and yarn
    npm install -g pnpm yarn

    # Install useful development tools
    sudo apt-get install -y htop tree jq unzip

    # Install Docker
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Install VS Code
    echo "💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install VS Code extensions
    code --install-extension ms-vscode.vscode-typescript-next
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension esbenp.prettier-vscode
    code --install-extension dbaeumer.vscode-eslint
    code --install-extension formulahendry.auto-rename-tag
    code --install-extension ms-vscode.vscode-json
    code --install-extension GitHub.copilot
    code --install-extension ms-playwright.playwright

    # Create React project based on template
    cd /home/coder

    case "${data.coder_parameter.framework_template.value}" in
      "vite-ts")
        echo "🏗️ Creating Vite + React + TypeScript project..."
        npm create vite@latest react-app -- --template react-ts
        cd react-app
        npm install
        ;;
      "nextjs")
        echo "🏗️ Creating Next.js project..."
        npx create-next-app@latest react-app --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"
        cd react-app
        ;;
      "cra")
        echo "🏗️ Creating Create React App project..."
        npx create-react-app react-app --template typescript
        cd react-app
        ;;
    esac

    # Install UI library and additional dependencies
    case "${data.coder_parameter.ui_library.value}" in
      "tailwind")
        if [[ "${data.coder_parameter.framework_template.value}" != "nextjs" ]]; then
          npm install -D tailwindcss postcss autoprefixer
          npx tailwindcss init -p

          # Configure Tailwind
          cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOF

          # Add Tailwind directives
          cat > src/index.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF
        fi
        ;;
      "mui")
        npm install @mui/material @emotion/react @emotion/styled @mui/icons-material
        npm install -D @types/mui
        ;;
      "antd")
        npm install antd
        npm install -D @types/antd
        ;;
      "chakra")
        npm install @chakra-ui/react @emotion/react @emotion/styled framer-motion
        ;;
    esac

    # Install additional useful packages
    npm install axios react-router-dom
    npm install -D @types/node

    # Install testing libraries
    case "${data.coder_parameter.framework_template.value}" in
      "vite-ts")
        npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom
        npm install -D @playwright/test
        ;;
      "nextjs")
        npm install -D @testing-library/react @testing-library/jest-dom jest jest-environment-jsdom
        npm install -D @playwright/test
        ;;
      "cra")
        npm install -D @testing-library/user-event @playwright/test
        ;;
    esac

    # Create sample components and pages
    mkdir -p src/components src/pages src/hooks src/utils src/types

    # Create a sample component
    cat > src/components/Welcome.tsx << 'EOF'
import React from 'react';

interface WelcomeProps {
  name?: string;
}

const Welcome: React.FC<WelcomeProps> = ({ name = 'Developer' }) => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center">
      <div className="bg-white rounded-lg shadow-xl p-8 max-w-md mx-4">
        <h1 className="text-3xl font-bold text-gray-800 mb-4">
          Welcome, {name}!
        </h1>
        <p className="text-gray-600 mb-6">
          Your React TypeScript development environment is ready to go.
        </p>
        <div className="space-y-2">
          <div className="flex items-center text-sm text-gray-500">
            <span className="w-2 h-2 bg-green-500 rounded-full mr-2"></span>
            TypeScript configured
          </div>
          <div className="flex items-center text-sm text-gray-500">
            <span className="w-2 h-2 bg-green-500 rounded-full mr-2"></span>
            ${data.coder_parameter.ui_library.value == "tailwind" ? "Tailwind CSS" : data.coder_parameter.ui_library.value} ready
          </div>
          <div className="flex items-center text-sm text-gray-500">
            <span className="w-2 h-2 bg-green-500 rounded-full mr-2"></span>
            Development server running
          </div>
        </div>
        <button
          onClick={() => alert('Happy coding!')}
          className="mt-6 w-full bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded transition-colors"
        >
          Start Building
        </button>
      </div>
    </div>
  );
};

export default Welcome;
EOF

    # Update main App component
    case "${data.coder_parameter.framework_template.value}" in
      "vite-ts"|"cra")
        cat > src/App.tsx << 'EOF'
import React from 'react';
import Welcome from './components/Welcome';

function App() {
  return <Welcome name="Coder" />;
}

export default App;
EOF
        ;;
      "nextjs")
        cat > src/app/page.tsx << 'EOF'
import Welcome from '@/components/Welcome';

export default function Home() {
  return <Welcome name="Coder" />;
}
EOF
        ;;
    esac

    # Create API utilities
    cat > src/utils/api.ts << 'EOF'
import axios from 'axios';

const api = axios.create({
  baseURL: process.env.REACT_APP_API_URL || 'http://localhost:8000/api',
  timeout: 10000,
});

// Request interceptor
api.interceptors.request.use(
  (config) => {
    // Add auth token if available
    const token = localStorage.getItem('token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response interceptor
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Handle unauthorized access
      localStorage.removeItem('token');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export default api;
EOF

    # Create custom hook
    cat > src/hooks/useApi.ts << 'EOF'
import { useState, useEffect } from 'react';
import api from '../utils/api';

interface UseApiResult<T> {
  data: T | null;
  loading: boolean;
  error: Error | null;
  refetch: () => void;
}

export function useApi<T>(url: string): UseApiResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchData = async () => {
    try {
      setLoading(true);
      const response = await api.get<T>(url);
      setData(response.data);
      setError(null);
    } catch (err) {
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [url]);

  return { data, loading, error, refetch: fetchData };
}
EOF

    # Create TypeScript types
    cat > src/types/index.ts << 'EOF'
export interface User {
  id: string;
  name: string;
  email: string;
  avatar?: string;
}

export interface ApiResponse<T> {
  status: 'success' | 'error';
  data: T;
  message?: string;
}

export interface Post {
  id: string;
  title: string;
  content: string;
  author: User;
  createdAt: string;
  updatedAt: string;
}
EOF

    # Create environment files
    cat > .env.local << 'EOF'
REACT_APP_API_URL=http://localhost:8000/api
REACT_APP_APP_NAME=React TypeScript App
REACT_APP_VERSION=1.0.0
EOF

    cat > .env.example << 'EOF'
REACT_APP_API_URL=http://localhost:8000/api
REACT_APP_APP_NAME=React TypeScript App
REACT_APP_VERSION=1.0.0
EOF

    # Configure package.json scripts
    if [[ "${data.coder_parameter.framework_template.value}" == "vite-ts" ]]; then
      # Add testing scripts for Vite
      npm pkg set scripts.test="vitest"
      npm pkg set scripts.test:ui="vitest --ui"
      npm pkg set scripts.test:e2e="playwright test"
      npm pkg set scripts.preview="vite preview"
    fi

    # Create Docker configuration
    cat > Dockerfile << 'EOF'
FROM node:20-alpine as builder

WORKDIR /app
COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY --from=builder /app/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

    cat > nginx.conf << 'EOF'
events {
  worker_connections 1024;
}

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    location / {
      try_files $uri $uri/ /index.html;
    }

    location /api {
      proxy_pass http://backend:8000;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
    }
  }
}
EOF

    # Create docker-compose for development
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  frontend:
    build: .
    ports:
      - "3000:80"
    environment:
      - NODE_ENV=production
    depends_on:
      - backend

  backend:
    image: node:20-alpine
    working_dir: /app
    ports:
      - "8000:8000"
    volumes:
      - ../backend:/app
    command: npm run dev
    environment:
      - NODE_ENV=development
      - PORT=8000
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/react-app

    # Install dependencies and build
    cd /home/coder/react-app
    npm install

    echo "✅ React TypeScript development environment ready!"

  EOT

  # Metadata
  metadata {
    display_name = "Node.js Version"
    key          = "node_version"
    value        = data.coder_parameter.node_version.value
  }

  metadata {
    display_name = "Framework Template"
    key          = "framework_template"
    value        = data.coder_parameter.framework_template.value
  }

  metadata {
    display_name = "UI Library"
    key          = "ui_library"
    value        = data.coder_parameter.ui_library.value
  }

  metadata {
    display_name = "CPU"
    key          = "cpu"
    value        = data.coder_parameter.cpu.value
  }

  metadata {
    display_name = "Memory"
    key          = "memory"
    value        = "${data.coder_parameter.memory.value}GB"
  }
}

# Applications
resource "coder_app" "react_dev" {
  agent_id     = coder_agent.main.id
  slug         = "react-dev"
  display_name = "React Dev Server"
  url          = "http://localhost:3000"
  icon         = "/icon/react.svg"
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
  command      = "code /home/coder/react-app"
  share        = "owner"
}

resource "coder_app" "storybook" {
  agent_id     = coder_agent.main.id
  slug         = "storybook"
  display_name = "Storybook"
  url          = "http://localhost:6006"
  icon         = "/icon/storybook.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:6006"
    interval  = 10
    threshold = 15
  }
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

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace.me.owner_id
      "com.coder.user.username"    = data.coder_workspace.me.owner
    }

    annotations = {
      "com.coder.user.email" = data.coder_workspace.me.owner_email
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
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