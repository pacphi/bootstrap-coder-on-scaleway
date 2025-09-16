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

data "coder_parameter" "docker_version" {
  name         = "docker_version"
  display_name = "Docker Version"
  description  = "Docker version to install"
  default      = "24.0"
  icon         = "/icon/docker.svg"
  mutable      = false
  option {
    name  = "Docker 23.0"
    value = "23.0"
  }
  option {
    name  = "Docker 24.0"
    value = "24.0"
  }
  option {
    name  = "Docker 25.0"
    value = "25.0"
  }
}

data "coder_parameter" "compose_version" {
  name         = "compose_version"
  display_name = "Docker Compose Version"
  description  = "Docker Compose version to install"
  default      = "2.23"
  icon         = "/icon/docker-compose.svg"
  mutable      = false
  option {
    name  = "Compose 2.21"
    value = "2.21"
  }
  option {
    name  = "Compose 2.23"
    value = "2.23"
  }
  option {
    name  = "Latest"
    value = "latest"
  }
}

data "coder_parameter" "stack_template" {
  name         = "stack_template"
  display_name = "Stack Template"
  description  = "Pre-configured stack template"
  default      = "fullstack"
  icon         = "/icon/stack.svg"
  mutable      = false
  option {
    name  = "Full Stack (Web + DB + Cache)"
    value = "fullstack"
  }
  option {
    name  = "LAMP Stack"
    value = "lamp"
  }
  option {
    name  = "MEAN Stack"
    value = "mean"
  }
  option {
    name  = "Microservices"
    value = "microservices"
  }
  option {
    name  = "Data Pipeline"
    value = "data"
  }
}

data "coder_parameter" "enable_monitoring" {
  name         = "enable_monitoring"
  display_name = "Enable Monitoring Stack"
  description  = "Include Prometheus, Grafana, and logging"
  default      = "true"
  type         = "bool"
  icon         = "/icon/monitor.svg"
  mutable      = false
}

# Providers
provider "kubernetes" {
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

# Workspace
resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  startup_script = <<-EOT
    #!/bin/bash

    echo "🐳 Setting up Docker Compose DevOps environment..."

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
      lsb-release

    # Install Docker ${data.coder_parameter.docker_version.value}
    echo "🐳 Installing Docker ${data.coder_parameter.docker_version.value}..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now
    rm get-docker.sh

    # Install Docker Compose ${data.coder_parameter.compose_version.value}
    echo "🐙 Installing Docker Compose ${data.coder_parameter.compose_version.value}..."
    if [[ "${data.coder_parameter.compose_version.value}" == "latest" ]]; then
      COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
    else
      COMPOSE_VERSION="v${data.coder_parameter.compose_version.value}.0"
    fi

    sudo curl -L "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Install additional Docker tools
    echo "🛠️ Installing additional Docker tools..."

    # Docker BuildKit
    docker buildx install

    # Dive (Docker image analyzer)
    DIVE_VERSION=$(curl -s https://api.github.com/repos/wagoodman/dive/releases/latest | jq -r .tag_name)
    wget -O dive.deb "https://github.com/wagoodman/dive/releases/download/$${DIVE_VERSION}/dive_$${DIVE_VERSION#v}_linux_amd64.deb"
    sudo dpkg -i dive.deb
    rm dive.deb

    # Ctop (container monitoring)
    sudo curl -L https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 -o /usr/local/bin/ctop
    sudo chmod +x /usr/local/bin/ctop

    # Lazydocker (Docker TUI)
    LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
    curl -Lo lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/latest/download/lazydocker_$${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz"
    tar xf lazydocker.tar.gz lazydocker
    sudo install lazydocker /usr/local/bin
    rm lazydocker*

    # Install VS Code
    echo "💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install VS Code extensions
    code --install-extension ms-azuretools.vscode-docker
    code --install-extension ms-vscode-remote.remote-containers
    code --install-extension redhat.vscode-yaml
    code --install-extension ms-vscode.vscode-json
    code --install-extension GitHub.copilot
    code --install-extension ms-python.python
    code --install-extension ms-vscode.vscode-node-debug2
    code --install-extension bradlc.vscode-tailwindcss

    # Create project structure
    cd /home/coder
    mkdir -p {stacks,templates,scripts,docs,data,logs,configs}

    # Create stack based on template selection
    cd stacks
    case "${data.coder_parameter.stack_template.value}" in
      "fullstack")
        echo "🚀 Creating Full Stack template..."
        mkdir -p fullstack/{frontend,backend,database,cache,proxy}
        cd fullstack

        # Create main docker-compose.yml
        cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Frontend (React/Vue/Angular)
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - REACT_APP_API_URL=http://backend:5000
      - NODE_ENV=development
    volumes:
      - ./frontend:/app
      - /app/node_modules
    depends_on:
      - backend
    networks:
      - app-network
    restart: unless-stopped

  # Backend API (Node.js/Express)
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "5000:5000"
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/appdb
      - REDIS_URL=redis://redis:6379
      - JWT_SECRET=your-jwt-secret-change-in-production
    volumes:
      - ./backend:/app
      - /app/node_modules
    depends_on:
      - postgres
      - redis
    networks:
      - app-network
    restart: unless-stopped

  # PostgreSQL Database
  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=appdb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/init:/docker-entrypoint-initdb.d
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Redis Cache
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
      - ./cache/redis.conf:/usr/local/etc/redis/redis.conf
    command: redis-server /usr/local/etc/redis/redis.conf
    networks:
      - app-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 5

  # Nginx Reverse Proxy
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./proxy/nginx.conf:/etc/nginx/nginx.conf
      - ./proxy/ssl:/etc/nginx/ssl
    depends_on:
      - frontend
      - backend
    networks:
      - app-network
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:

networks:
  app-network:
    driver: bridge
EOF

        # Create frontend Dockerfile
        mkdir -p frontend
        cat > frontend/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

EXPOSE 3000

# Start the application
CMD ["npm", "start"]
EOF

        cat > frontend/package.json << 'EOF'
{
  "name": "fullstack-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "axios": "^1.6.0",
    "react-router-dom": "^6.8.0"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "proxy": "http://backend:5000"
}
EOF

        # Create backend Dockerfile
        mkdir -p backend
        cat > backend/Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci --only=production

# Copy source code
COPY . .

EXPOSE 5000

# Start the application
CMD ["npm", "start"]
EOF

        cat > backend/package.json << 'EOF'
{
  "name": "fullstack-backend",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.1.0",
    "morgan": "^1.10.0",
    "dotenv": "^16.3.1",
    "pg": "^8.11.3",
    "redis": "^4.6.10",
    "jsonwebtoken": "^9.0.2",
    "bcryptjs": "^2.4.3",
    "joi": "^17.11.0"
  },
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  }
}
EOF

        # Create sample backend server
        cat > backend/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(morgan('combined'));
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// API routes
app.get('/api', (req, res) => {
  res.json({
    message: 'Full Stack API is running!',
    version: '1.0.0',
    environment: process.env.NODE_ENV || 'development'
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log("🚀 Backend server running on port $${PORT}");
});
EOF

        # Create nginx configuration
        mkdir -p proxy
        cat > proxy/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream frontend {
        server frontend:3000;
    }

    upstream backend {
        server backend:5000;
    }

    server {
        listen 80;
        server_name localhost;

        # Frontend
        location / {
            proxy_pass http://frontend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Backend API
        location /api/ {
            proxy_pass http://backend/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Health checks
        location /health {
            proxy_pass http://backend/health;
        }
    }
}
EOF

        # Create database init script
        mkdir -p database/init
        cat > database/init/01-init.sql << 'EOF'
-- Create application database
CREATE DATABASE IF NOT EXISTS appdb;

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create posts table
CREATE TABLE IF NOT EXISTS posts (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    content TEXT,
    author_id INTEGER REFERENCES users(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email, password_hash) VALUES
    ('admin', 'admin@example.com', '$2a$10$hash'),
    ('user1', 'user1@example.com', '$2a$10$hash');

INSERT INTO posts (title, content, author_id) VALUES
    ('Welcome Post', 'Welcome to the full stack application!', 1),
    ('Sample Post', 'This is a sample post content.', 2);
EOF

        # Create Redis configuration
        mkdir -p cache
        cat > cache/redis.conf << 'EOF'
# Redis configuration
port 6379
bind 0.0.0.0
protected-mode no
save 900 1
save 300 10
save 60 10000
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF
        ;;

      "lamp")
        echo "🏛️ Creating LAMP Stack template..."
        mkdir -p lamp/{web,database,php}
        cd lamp

        cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Apache Web Server with PHP
  web:
    build:
      context: ./php
      dockerfile: Dockerfile
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./web:/var/www/html
      - ./php/php.ini:/usr/local/etc/php/php.ini
    depends_on:
      - mysql
    networks:
      - lamp-network
    restart: unless-stopped

  # MySQL Database
  mysql:
    image: mysql:8.0
    environment:
      - MYSQL_ROOT_PASSWORD=rootpassword
      - MYSQL_DATABASE=lampdb
      - MYSQL_USER=lampuser
      - MYSQL_PASSWORD=lamppass
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
      - ./database/init:/docker-entrypoint-initdb.d
    networks:
      - lamp-network
    restart: unless-stopped
    command: --default-authentication-plugin=mysql_native_password

  # phpMyAdmin
  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    environment:
      - PMA_HOST=mysql
      - PMA_USER=root
      - PMA_PASSWORD=rootpassword
    ports:
      - "8080:80"
    depends_on:
      - mysql
    networks:
      - lamp-network
    restart: unless-stopped

volumes:
  mysql_data:

networks:
  lamp-network:
    driver: bridge
EOF

        # Create PHP Dockerfile
        cat > php/Dockerfile << 'EOF'
FROM php:8.2-apache

# Install PHP extensions
RUN docker-php-ext-install mysqli pdo pdo_mysql

# Enable Apache modules
RUN a2enmod rewrite

# Copy custom PHP configuration
COPY php.ini /usr/local/etc/php/

# Set working directory
WORKDIR /var/www/html
EOF

        cat > php/php.ini << 'EOF'
[PHP]
post_max_size = 100M
upload_max_filesize = 100M
max_execution_time = 300
memory_limit = 256M
display_errors = On
log_errors = On
error_log = /var/log/php_errors.log
EOF

        # Create sample PHP application
        mkdir -p web
        cat > web/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>LAMP Stack Application</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .card { border: 1px solid #ddd; padding: 20px; margin: 20px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏛️ LAMP Stack Application</h1>

        <div class="card">
            <h2>Environment Info</h2>
            <p><strong>PHP Version:</strong> <?php echo PHP_VERSION; ?></p>
            <p><strong>Apache Version:</strong> <?php echo apache_get_version(); ?></p>
            <p><strong>Server Time:</strong> <?php echo date('Y-m-d H:i:s'); ?></p>
        </div>

        <div class="card">
            <h2>Database Connection Test</h2>
            <?php
            $servername = "mysql";
            $username = "lampuser";
            $password = "lamppass";
            $dbname = "lampdb";

            try {
                $pdo = new PDO("mysql:host=$servername;dbname=$dbname", $username, $password);
                $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
                echo "<p style='color: green;'>✅ Database connection successful!</p>";

                // Sample query
                $stmt = $pdo->query("SELECT COUNT(*) as count FROM users");
                $result = $stmt->fetch();
                echo "<p>Users in database: " . $result['count'] . "</p>";

            } catch(PDOException $e) {
                echo "<p style='color: red;'>❌ Connection failed: " . $e->getMessage() . "</p>";
            }
            ?>
        </div>

        <div class="card">
            <h2>Quick Links</h2>
            <ul>
                <li><a href="info.php">PHP Info</a></li>
                <li><a href="http://localhost:8080" target="_blank">phpMyAdmin</a></li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

        cat > web/info.php << 'EOF'
<?php
phpinfo();
?>
EOF

        # Create database initialization
        mkdir -p database/init
        cat > database/init/01-init.sql << 'EOF'
-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (username, email, password_hash) VALUES
    ('admin', 'admin@example.com', '$2y$10$hash'),
    ('user1', 'user1@example.com', '$2y$10$hash');
EOF
        ;;

      "mean")
        echo "📊 Creating MEAN Stack template..."
        mkdir -p mean/{frontend,backend,database}
        cd mean

        cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Angular Frontend
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "4200:4200"
    volumes:
      - ./frontend:/app
      - /app/node_modules
    networks:
      - mean-network
    restart: unless-stopped

  # Express Backend
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - MONGODB_URI=mongodb://mongo:27017/meandb
    volumes:
      - ./backend:/app
      - /app/node_modules
    depends_on:
      - mongo
    networks:
      - mean-network
    restart: unless-stopped

  # MongoDB Database
  mongo:
    image: mongo:7
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db
      - ./database/init:/docker-entrypoint-initdb.d
    networks:
      - mean-network
    restart: unless-stopped

  # Mongo Express (Web UI)
  mongo-express:
    image: mongo-express
    ports:
      - "8081:8081"
    environment:
      - ME_CONFIG_MONGODB_SERVER=mongo
      - ME_CONFIG_MONGODB_PORT=27017
      - ME_CONFIG_MONGODB_ENABLE_ADMIN=true
    depends_on:
      - mongo
    networks:
      - mean-network
    restart: unless-stopped

volumes:
  mongo_data:

networks:
  mean-network:
    driver: bridge
EOF
        ;;
    esac

    # Create monitoring stack if enabled
    if [[ "${data.coder_parameter.enable_monitoring.value}" == "true" ]]; then
      echo "📊 Creating monitoring stack..."
      cd /home/coder/stacks
      mkdir -p monitoring/{prometheus,grafana,alertmanager}
      cd monitoring

      cat > docker-compose.monitoring.yml << 'EOF'
version: '3.8'

services:
  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/rules:/etc/prometheus/rules
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    networks:
      - monitoring
    restart: unless-stopped

  # Grafana
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
      - ./grafana/dashboards:/etc/grafana/dashboards
    networks:
      - monitoring
    restart: unless-stopped

  # Node Exporter
  node-exporter:
    image: prom/node-exporter:latest
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring
    restart: unless-stopped

  # cAdvisor
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.47.0
    ports:
      - "8082:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    privileged: true
    devices:
      - /dev/kmsg
    networks:
      - monitoring
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:

networks:
  monitoring:
    driver: bridge
EOF

      # Create Prometheus configuration
      cat > prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'docker-containers'
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: [__meta_docker_container_label_com_docker_compose_service]
        target_label: service
EOF

      # Create Grafana provisioning
      mkdir -p grafana/provisioning/{datasources,dashboards}
      cat > grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

      cat > grafana/provisioning/dashboards/dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
EOF
    fi

    # Create utility scripts
    cd /home/coder/scripts

    cat > start-stack.sh << 'EOF'
#!/bin/bash
# Start Docker Compose stack

set -e

STACK=$${1:-${data.coder_parameter.stack_template.value}}
STACK_PATH="../stacks/$STACK"

if [[ ! -d "$STACK_PATH" ]]; then
  echo "❌ Stack '$STACK' not found in $STACK_PATH"
  echo "Available stacks:"
  ls ../stacks/
  exit 1
fi

echo "🚀 Starting $STACK stack..."

cd "$STACK_PATH"

# Start the main stack
docker-compose up -d

# Start monitoring if enabled
if [[ "${data.coder_parameter.enable_monitoring.value}" == "true" && -f "../monitoring/docker-compose.monitoring.yml" ]]; then
  echo "📊 Starting monitoring stack..."
  docker-compose -f ../monitoring/docker-compose.monitoring.yml up -d
fi

echo "✅ Stack started successfully!"
echo "🔗 Service URLs:"
docker-compose ps --format "table {{.Name}}\t{{.Ports}}"

if [[ "${data.coder_parameter.enable_monitoring.value}" == "true" ]]; then
  echo ""
  echo "📊 Monitoring URLs:"
  echo "  Prometheus: http://localhost:9090"
  echo "  Grafana: http://localhost:3001 (admin/admin123)"
fi
EOF

    cat > stop-stack.sh << 'EOF'
#!/bin/bash
# Stop Docker Compose stack

set -e

STACK=$${1:-${data.coder_parameter.stack_template.value}}
STACK_PATH="../stacks/$STACK"

echo "🛑 Stopping $STACK stack..."

cd "$STACK_PATH"

# Stop the main stack
docker-compose down

# Stop monitoring if enabled
if [[ "${data.coder_parameter.enable_monitoring.value}" == "true" && -f "../monitoring/docker-compose.monitoring.yml" ]]; then
  echo "📊 Stopping monitoring stack..."
  docker-compose -f ../monitoring/docker-compose.monitoring.yml down
fi

echo "✅ Stack stopped successfully!"
EOF

    cat > logs.sh << 'EOF'
#!/bin/bash
# View logs from Docker Compose services

STACK=$${1:-${data.coder_parameter.stack_template.value}}
SERVICE=${2}
STACK_PATH="../stacks/$STACK"

cd "$STACK_PATH"

if [[ -n "$SERVICE" ]]; then
  echo "📋 Viewing logs for service: $SERVICE"
  docker-compose logs -f "$SERVICE"
else
  echo "📋 Viewing logs for all services in $STACK stack"
  docker-compose logs -f
fi
EOF

    cat > rebuild.sh << 'EOF'
#!/bin/bash
# Rebuild and restart Docker Compose stack

set -e

STACK=$${1:-${data.coder_parameter.stack_template.value}}
STACK_PATH="../stacks/$STACK"

echo "🔄 Rebuilding $STACK stack..."

cd "$STACK_PATH"

# Stop, rebuild, and start
docker-compose down
docker-compose build --no-cache
docker-compose up -d

echo "✅ Stack rebuilt and restarted successfully!"
EOF

    cat > cleanup.sh << 'EOF'
#!/bin/bash
# Cleanup Docker resources

echo "🧹 Cleaning up Docker resources..."

# Stop all containers
docker stop $(docker ps -aq) 2>/dev/null || true

# Remove containers
docker container prune -f

# Remove unused images
docker image prune -f

# Remove unused volumes
docker volume prune -f

# Remove unused networks
docker network prune -f

# Show disk usage
echo "💾 Current Docker disk usage:"
docker system df

echo "✅ Cleanup complete!"
EOF

    # Make scripts executable
    chmod +x *.sh

    # Create development templates
    cd /home/coder/templates

    cat > docker-compose.template.yml << 'EOF'
version: '3.8'

services:
  # Application service
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
    volumes:
      - .:/app
      - /app/node_modules
    restart: unless-stopped
    networks:
      - app-network

  # Database service
  database:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=appuser
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=appdb
    ports:
      - "5432:5432"
    volumes:
      - db_data:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - app-network

  # Cache service
  cache:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    restart: unless-stopped
    networks:
      - app-network

volumes:
  db_data:

networks:
  app-network:
    driver: bridge
EOF

    cat > Dockerfile.template << 'EOF'
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Start application
CMD ["npm", "start"]
EOF

    # Create documentation
    cat > /home/coder/docs/README.md << 'EOF'
# Docker Compose DevOps Environment

This environment provides comprehensive Docker and Docker Compose tools for containerized application development and deployment.

## Tools Installed

### Container Tools
- Docker ${data.coder_parameter.docker_version.value}
- Docker Compose ${data.coder_parameter.compose_version.value}
- Docker BuildX (multi-platform builds)
- Dive (image analysis)
- Ctop (container monitoring)
- Lazydocker (Docker TUI)

### Stack Templates
- **${data.coder_parameter.stack_template.value}** (Selected template)
- Full Stack (React + Express + PostgreSQL + Redis)
- LAMP Stack (Apache + PHP + MySQL)
- MEAN Stack (Angular + Express + MongoDB)
- Microservices architecture
- Data pipeline setup

### Monitoring Stack
${data.coder_parameter.enable_monitoring.value ? "✅ Prometheus, Grafana, Node Exporter, cAdvisor" : "❌ Monitoring disabled"}

## Project Structure

```
├── stacks/               # Pre-configured application stacks
│   ├── ${data.coder_parameter.stack_template.value}/           # Selected stack template
│   └── monitoring/       # Monitoring stack
├── templates/            # Docker Compose templates
├── scripts/              # Utility scripts
├── data/                # Persistent data
├── logs/                # Application logs
├── configs/             # Configuration files
└── docs/                # Documentation
```

## Quick Start

### Using Pre-configured Stacks

1. **Start the ${data.coder_parameter.stack_template.value} stack:**
   ```bash
   ./scripts/start-stack.sh ${data.coder_parameter.stack_template.value}
   ```

2. **View running services:**
   ```bash
   docker-compose ps
   ```

3. **View logs:**
   ```bash
   ./scripts/logs.sh ${data.coder_parameter.stack_template.value}
   ```

4. **Stop the stack:**
   ```bash
   ./scripts/stop-stack.sh ${data.coder_parameter.stack_template.value}
   ```

### Custom Development

1. **Use templates to create new projects:**
   ```bash
   cp templates/docker-compose.template.yml my-project/docker-compose.yml
   cp templates/Dockerfile.template my-project/Dockerfile
   ```

2. **Build and run custom project:**
   ```bash
   cd my-project
   docker-compose up -d
   ```

## Common Commands

### Docker Commands
```bash
# List running containers
docker ps

# View container logs
docker logs <container-name> -f

# Execute command in container
docker exec -it <container-name> bash

# Build image
docker build -t myapp .

# Run container
docker run -d -p 3000:3000 myapp
```

### Docker Compose Commands
```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Rebuild services
docker-compose build

# Scale services
docker-compose up -d --scale web=3
```

### Container Monitoring
```bash
# Launch Lazydocker TUI
lazydocker

# Monitor containers with ctop
ctop

# Analyze image layers
dive <image-name>
```

## Stack Details

### ${data.coder_parameter.stack_template.value} Stack

${data.coder_parameter.stack_template.value == "fullstack" ?
  "- **Frontend:** React application (port 3000)\n- **Backend:** Express.js API (port 5000)\n- **Database:** PostgreSQL (port 5432)\n- **Cache:** Redis (port 6379)\n- **Proxy:** Nginx (port 80)" :
  data.coder_parameter.stack_template.value == "lamp" ?
  "- **Web Server:** Apache with PHP (port 80)\n- **Database:** MySQL (port 3306)\n- **Admin:** phpMyAdmin (port 8080)" :
  data.coder_parameter.stack_template.value == "mean" ?
  "- **Frontend:** Angular (port 4200)\n- **Backend:** Express.js (port 3000)\n- **Database:** MongoDB (port 27017)\n- **Admin:** Mongo Express (port 8081)" :
  "Custom microservices architecture with multiple services"
  }

### Monitoring Stack (if enabled)

${data.coder_parameter.enable_monitoring.value ?
  "- **Prometheus:** Metrics collection (port 9090)\n- **Grafana:** Dashboards (port 3001) - admin/admin123\n- **Node Exporter:** System metrics (port 9100)\n- **cAdvisor:** Container metrics (port 8082)" :
"Monitoring is disabled for this environment"}

## Development Workflow

1. **Choose or create a stack**
2. **Customize docker-compose.yml**
3. **Build and test locally**
4. **Use monitoring tools**
5. **Deploy to production**

## Best Practices

### Container Development
- Use multi-stage builds for production
- Implement proper health checks
- Use .dockerignore files
- Keep images small and secure
- Use specific version tags

### Docker Compose
- Use environment-specific compose files
- Implement proper networking
- Use volumes for persistent data
- Set resource limits
- Implement proper logging

### Security
- Use non-root users in containers
- Scan images for vulnerabilities
- Use secrets management
- Implement proper network isolation
- Keep base images updated

## Troubleshooting

### Common Issues

1. **Port already in use:**
   ```bash
   # Find process using port
   lsof -i :3000
   # Or change port in docker-compose.yml
   ```

2. **Container won't start:**
   ```bash
   # Check logs
   docker-compose logs <service-name>
   # Check container status
   docker-compose ps
   ```

3. **Volume issues:**
   ```bash
   # Remove volumes
   docker-compose down -v
   # Recreate volumes
   docker-compose up -d
   ```

4. **Memory issues:**
   ```bash
   # Check Docker resource usage
   docker stats
   # Clean up unused resources
   ./scripts/cleanup.sh
   ```

This environment provides everything you need for professional Docker-based development!
EOF

    # Create VS Code workspace settings
    mkdir -p .vscode
    cat > .vscode/settings.json << 'EOF'
{
    "docker.showStartPage": false,
    "docker.defaultRegistryPath": "docker.io",
    "files.associations": {
        "docker-compose*.yml": "dockercompose",
        "docker-compose*.yaml": "dockercompose",
        "Dockerfile*": "dockerfile"
    },
    "editor.formatOnSave": true,
    "[dockercompose]": {
        "editor.insertSpaces": true,
        "editor.tabSize": 2
    },
    "[dockerfile]": {
        "editor.insertSpaces": true,
        "editor.tabSize": 2
    }
}
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Docker
.docker/
*.log

# Data directories
data/
logs/

# Environment files
.env
.env.local
.env.production

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Temporary files
*.tmp
*.temp

# Docker Compose overrides
docker-compose.override.yml
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder

    echo "✅ Docker Compose DevOps environment ready!"
    echo "🐳 Docker ${data.coder_parameter.docker_version.value} and Compose ${data.coder_parameter.compose_version.value} installed"
    echo "📦 Stack template: ${data.coder_parameter.stack_template.value}"
    echo "📊 Monitoring: ${data.coder_parameter.enable_monitoring.value ? "enabled" : "disabled"}"
    echo ""
    echo "🚀 Quick start:"
    echo "  cd /home/coder && ./scripts/start-stack.sh"
    echo "  lazydocker  # Launch Docker TUI"
    echo "  docker-compose ps  # View running services"

  EOT

}

# Metadata
resource "coder_metadata" "docker_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "docker_version"
    value = data.coder_parameter.docker_version.value
  }
}

resource "coder_metadata" "compose_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "compose_version"
    value = data.coder_parameter.compose_version.value
  }
}

resource "coder_metadata" "stack_template" {
  resource_id = coder_agent.main.id
  item {
    key   = "stack_template"
    value = data.coder_parameter.stack_template.value
  }
}

resource "coder_metadata" "monitoring_enabled" {
  resource_id = coder_agent.main.id
  item {
    key   = "monitoring_enabled"
    value = tostring(data.coder_parameter.enable_monitoring.value)
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
resource "coder_app" "lazydocker" {
  agent_id     = coder_agent.main.id
  slug         = "lazydocker"
  display_name = "Lazydocker"
  icon         = "/icon/docker.svg"
  command      = "lazydocker"
  share        = "owner"
}

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder"
  share        = "owner"
}

resource "coder_app" "stack_app" {
  agent_id     = coder_agent.main.id
  slug         = "stack-app"
  display_name = data.coder_parameter.stack_template.value == "fullstack" ? "Full Stack App" : data.coder_parameter.stack_template.value == "lamp" ? "LAMP App" : data.coder_parameter.stack_template.value == "mean" ? "MEAN App" : "Stack App"
  url          = data.coder_parameter.stack_template.value == "fullstack" ? "http://localhost:80" : data.coder_parameter.stack_template.value == "lamp" ? "http://localhost:80" : data.coder_parameter.stack_template.value == "mean" ? "http://localhost:4200" : "http://localhost:3000"
  icon         = "/icon/app.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = data.coder_parameter.stack_template.value == "fullstack" ? "http://localhost:80" : data.coder_parameter.stack_template.value == "lamp" ? "http://localhost:80" : data.coder_parameter.stack_template.value == "mean" ? "http://localhost:4200" : "http://localhost:3000"
    interval  = 15
    threshold = 30
  }
}

resource "coder_app" "prometheus" {
  count        = data.coder_parameter.enable_monitoring.value ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "prometheus"
  display_name = "Prometheus"
  url          = "http://localhost:9090"
  icon         = "/icon/prometheus.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:9090"
    interval  = 15
    threshold = 30
  }
}

resource "coder_app" "grafana" {
  count        = data.coder_parameter.enable_monitoring.value ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "grafana"
  display_name = "Grafana"
  url          = "http://localhost:3001"
  icon         = "/icon/grafana.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:3001"
    interval  = 15
    threshold = 30
  }
}

# Kubernetes resources
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace

    labels = {
      "docker-workspace" = "true"
      "compose-enabled"  = "true"
    }
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "fast-ssd" # Use fast storage for container workloads

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
      "docker-workspace"           = "true"
      "compose-enabled"            = "true"
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
          "docker-workspace"            = "true"
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
          image             = "ubuntu@sha256:2e863c44b718727c860746568e1d54afd13b2fa71b160f5cd9058fc436217b30"
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
            name  = "DOCKER_HOST"
            value = "tcp://localhost:2376"
          }

          env {
            name  = "DOCKER_TLS_CERTDIR"
            value = ""
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

        # Docker-in-Docker sidecar container for secure Docker access
        container {
          name              = "docker-daemon"
          image             = "docker@sha256:af96c680a7e1f853ebdd50c1e95469820e921b7e4bf089ac81b5103cb2987456"
          image_pull_policy = "Always"

          security_context {
            privileged                = true # Required for DinD, but isolated to sidecar
            read_only_root_filesystem = true
          }

          args = ["--host=tcp://0.0.0.0:2376", "--tls=false"]

          resources {
            requests = {
              "cpu"    = "100m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "500m"
              "memory" = "1Gi"
            }
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
            size_limit = "30Gi"
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

        # Toleration for Docker workloads
        toleration {
          key      = "docker-workloads"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.home]
}
