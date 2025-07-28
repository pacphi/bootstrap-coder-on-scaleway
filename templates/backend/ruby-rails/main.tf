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

data "coder_parameter" "ruby_version" {
  name         = "ruby_version"
  display_name = "Ruby Version"
  description  = "Ruby version to install"
  default      = "3.3.0"
  icon         = "/icon/ruby.svg"
  mutable      = false
  option {
    name  = "Ruby 3.2.0"
    value = "3.2.0"
  }
  option {
    name  = "Ruby 3.3.0"
    value = "3.3.0"
  }
}

data "coder_parameter" "rails_version" {
  name         = "rails_version"
  display_name = "Rails Version"
  description  = "Rails version to install"
  default      = "7.1"
  icon         = "/icon/rails.svg"
  mutable      = false
  option {
    name  = "Rails 7.0"
    value = "7.0"
  }
  option {
    name  = "Rails 7.1"
    value = "7.1"
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
    name  = "RubyMine"
    value = "rubymine"
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

    echo "💎 Setting up Ruby on Rails development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential libssl-dev libreadline-dev zlib1g-dev

    # Install dependencies for Ruby and Rails
    sudo apt-get install -y \
      autoconf \
      bison \
      build-essential \
      libssl-dev \
      libyaml-dev \
      libreadline6-dev \
      zlib1g-dev \
      libncurses5-dev \
      libffi-dev \
      libgdbm6 \
      libgdbm-dev \
      libdb-dev \
      uuid-dev \
      nodejs \
      npm \
      postgresql-client \
      libpq-dev \
      redis-tools \
      imagemagick \
      libmagickwand-dev

    # Install rbenv
    echo "📦 Installing rbenv..."
    git clone https://github.com/rbenv/rbenv.git ~/.rbenv
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(rbenv init -)"' >> ~/.bashrc
    export PATH="$HOME/.rbenv/bin:$PATH"
    eval "$(rbenv init -)"

    # Install ruby-build
    git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

    # Install Ruby ${data.coder_parameter.ruby_version.value}
    echo "💎 Installing Ruby ${data.coder_parameter.ruby_version.value}..."
    rbenv install ${data.coder_parameter.ruby_version.value}
    rbenv global ${data.coder_parameter.ruby_version.value}
    rbenv rehash

    # Install bundler and rails
    gem install bundler
    gem install rails -v "~> ${data.coder_parameter.rails_version.value}"
    rbenv rehash

    # Install Node.js and Yarn (for Rails asset pipeline)
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    npm install -g yarn

    # Install Docker
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Install useful development tools
    sudo apt-get install -y htop tree jq unzip

    # IDE-specific installations
    case "${data.coder_parameter.ide.value}" in
      "vscode")
        echo "💻 Installing VS Code..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        sudo apt update
        sudo apt install -y code

        # Install Ruby extensions
        code --install-extension rebornix.ruby
        code --install-extension castwide.solargraph
        code --install-extension kaiwood.endwise
        code --install-extension ninoseki.vscode-rails-schema
        code --install-extension aki77.rails-routes
        code --install-extension ms-vscode.vscode-json
        ;;
      "rubymine")
        echo "🧠 Installing RubyMine..."
        wget -q https://download.jetbrains.com/ruby/RubyMine-2023.3.2.tar.gz -O /tmp/rubymine.tar.gz
        sudo tar -xzf /tmp/rubymine.tar.gz -C /opt
        sudo ln -sf /opt/RubyMine-*/bin/rubymine.sh /usr/local/bin/rubymine
        rm /tmp/rubymine.tar.gz
        ;;
    esac

    # Create Rails application
    echo "🚂 Creating Rails application..."
    cd /home/coder

    # Initialize Rails app with modern stack
    rails new rails-app \
      --database=postgresql \
      --css=tailwind \
      --javascript=esbuild \
      --skip-test \
      --api=false

    cd rails-app

    # Add useful gems to Gemfile
    cat >> Gemfile << 'EOF'

# Development gems
group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'pry-rails'
  gem 'debug'
end

group :development do
  gem 'annotate'
  gem 'brakeman'
  gem 'rubocop-rails', require: false
  gem 'rubocop-rspec', require: false
  gem 'solargraph'
end

# Production gems
gem 'bootsnap', '>= 1.4.4', require: false
gem 'image_processing', '~> 1.2'
gem 'redis', '~> 4.0'
gem 'sidekiq'
gem 'rack-cors'
gem 'jbuilder'
EOF

    # Install gems
    bundle install

    # Setup RSpec
    rails generate rspec:install

    # Create sample model and controller
    rails generate model Post title:string content:text published:boolean
    rails generate controller Api::Posts --api

    # Update the Posts controller
    cat > app/controllers/api/posts_controller.rb << 'EOF'
class Api::PostsController < ApplicationController
  before_action :set_post, only: [:show, :update, :destroy]

  # GET /api/posts
  def index
    @posts = Post.all
    render json: {
      status: 'success',
      data: @posts
    }
  end

  # GET /api/posts/1
  def show
    render json: {
      status: 'success',
      data: @post
    }
  end

  # POST /api/posts
  def create
    @post = Post.new(post_params)

    if @post.save
      render json: {
        status: 'success',
        data: @post
      }, status: :created
    else
      render json: {
        status: 'error',
        errors: @post.errors
      }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/posts/1
  def update
    if @post.update(post_params)
      render json: {
        status: 'success',
        data: @post
      }
    else
      render json: {
        status: 'error',
        errors: @post.errors
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/posts/1
  def destroy
    @post.destroy
    render json: {
      status: 'success',
      message: 'Post deleted'
    }
  end

  # Health check
  def health
    render json: {
      status: 'success',
      message: 'Rails API is running!',
      timestamp: Time.current
    }
  end

  private

  def set_post
    @post = Post.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      status: 'error',
      message: 'Post not found'
    }, status: :not_found
  end

  def post_params
    params.require(:post).permit(:title, :content, :published)
  end
end
EOF

    # Update routes
    cat > config/routes.rb << 'EOF'
Rails.application.routes.draw do
  root 'application#health'

  namespace :api do
    resources :posts
    get 'health', to: 'posts#health'
  end

  # Health check route
  get 'health', to: 'application#health'
end
EOF

    # Add health check to ApplicationController
    cat > app/controllers/application_controller.rb << 'EOF'
class ApplicationController < ActionController::Base
  protect_from_forgery with: :null_session

  def health
    render json: {
      status: 'success',
      message: 'Rails application is running!',
      rails_version: Rails.version,
      ruby_version: RUBY_VERSION
    }
  end
end
EOF

    # Configure database
    cat > config/database.yml << 'EOF'
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  <<: *default
  database: rails_app_development
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  username: <%= ENV.fetch("DB_USER", "postgres") %>
  password: <%= ENV.fetch("DB_PASS", "password") %>
  port: <%= ENV.fetch("DB_PORT", "5432") %>

test:
  <<: *default
  database: rails_app_test
  host: <%= ENV.fetch("DB_HOST", "localhost") %>
  username: <%= ENV.fetch("DB_USER", "postgres") %>
  password: <%= ENV.fetch("DB_PASS", "password") %>
  port: <%= ENV.fetch("DB_PORT", "5432") %>

production:
  <<: *default
  url: <%= ENV['DATABASE_URL'] %>
EOF

    # Create .env file
    cat > .env << 'EOF'
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASS=password
REDIS_URL=redis://localhost:6379/0
RAILS_ENV=development
EOF

    # Create docker-compose.yml for local development
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - RAILS_ENV=development
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASS=password
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      - postgres
      - redis
    volumes:
      - .:/app
    command: bundle exec rails server -b 0.0.0.0

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: rails_app_development
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  sidekiq:
    build: .
    environment:
      - RAILS_ENV=development
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASS=password
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      - postgres
      - redis
    volumes:
      - .:/app
    command: bundle exec sidekiq

volumes:
  postgres_data:
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM ruby:3.3.0-alpine

RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    nodejs \
    npm \
    yarn \
    git \
    imagemagick

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY package.json yarn.lock ./
RUN yarn install

COPY . .

RUN bundle exec rails assets:precompile

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
EOF

    # Create useful scripts
    cat > bin/dev << 'EOF'
#!/usr/bin/env sh

if ! gem list foreman -i --silent; then
  echo "Installing foreman..."
  gem install foreman
fi

# Default to port 3000 if not specified
export PORT="$${PORT:-3000}"

exec foreman start -f Procfile.dev "$@"
EOF
    chmod +x bin/dev

    cat > Procfile.dev << 'EOF'
web: bin/rails server -p 3000
js: yarn build --watch
css: yarn build:css --watch
worker: bundle exec sidekiq
EOF

    # Create sample seeds
    cat > db/seeds.rb << 'EOF'
# Create sample posts
Post.create!([
  {
    title: "Welcome to Rails!",
    content: "This is your first blog post created automatically.",
    published: true
  },
  {
    title: "Getting Started with Rails",
    content: "Rails is a web application framework running on the Ruby programming language.",
    published: true
  },
  {
    title: "Draft Post",
    content: "This is a draft post that hasn't been published yet.",
    published: false
  }
])

puts "Created #{Post.count} posts"
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/rails-app

    # Run initial setup (if database is available)
    # Note: This would typically require a database connection
    echo "Rails application created! Run 'rails db:setup' when database is available."

    echo "✅ Ruby on Rails development environment ready!"

  EOT

}

# Metadata
resource "coder_metadata" "ruby_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "ruby_version"
    value = data.coder_parameter.ruby_version.value
  }
}

resource "coder_metadata" "rails_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "rails_version"
    value = data.coder_parameter.rails_version.value
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
resource "coder_app" "rails_server" {
  agent_id     = coder_agent.main.id
  slug         = "rails-server"
  display_name = "Rails Server"
  url          = "http://localhost:3000"
  icon         = "/icon/rails.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:3000/health"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "rails_api" {
  agent_id     = coder_agent.main.id
  slug         = "rails-api"
  display_name = "Rails API"
  url          = "http://localhost:3000/api/health"
  icon         = "/icon/api.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "vscode" {
  count        = data.coder_parameter.ide.value == "vscode" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/rails-app"
  share        = "owner"
}

resource "coder_app" "rubymine" {
  count        = data.coder_parameter.ide.value == "rubymine" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "rubymine"
  display_name = "RubyMine"
  icon         = "/icon/rubymine.svg"
  command      = "rubymine /home/coder/rails-app"
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
