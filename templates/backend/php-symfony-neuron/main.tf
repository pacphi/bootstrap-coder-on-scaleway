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

data "coder_parameter" "php_version" {
  name         = "php_version"
  display_name = "PHP Version"
  description  = "PHP version to install"
  default      = "8.3"
  icon         = "/icon/php.svg"
  mutable      = false
  option {
    name  = "PHP 8.2"
    value = "8.2"
  }
  option {
    name  = "PHP 8.3"
    value = "8.3"
  }
}

data "coder_parameter" "symfony_version" {
  name         = "symfony_version"
  display_name = "Symfony Version"
  description  = "Symfony version to install"
  default      = "7.0"
  icon         = "/icon/symfony.svg"
  mutable      = false
  option {
    name  = "Symfony 6.4 LTS"
    value = "6.4"
  }
  option {
    name  = "Symfony 7.0"
    value = "7.0"
  }
}

data "coder_parameter" "neuron_features" {
  name         = "neuron_features"
  display_name = "Neuron AI Features"
  description  = "Enable Neuron AI framework features"
  default      = "true"
  type         = "bool"
  icon         = "/icon/ai.svg"
  mutable      = false
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
    name  = "PhpStorm"
    value = "phpstorm"
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

    echo "🐘 Setting up PHP Symfony + Neuron AI development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential unzip

    # Install PHP ${data.coder_parameter.php_version.value} and extensions
    echo "📦 Installing PHP ${data.coder_parameter.php_version.value}..."
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt-get update

    sudo apt-get install -y \
      php${data.coder_parameter.php_version.value} \
      php${data.coder_parameter.php_version.value}-cli \
      php${data.coder_parameter.php_version.value}-fpm \
      php${data.coder_parameter.php_version.value}-mysql \
      php${data.coder_parameter.php_version.value}-pgsql \
      php${data.coder_parameter.php_version.value}-sqlite3 \
      php${data.coder_parameter.php_version.value}-redis \
      php${data.coder_parameter.php_version.value}-curl \
      php${data.coder_parameter.php_version.value}-json \
      php${data.coder_parameter.php_version.value}-mbstring \
      php${data.coder_parameter.php_version.value}-xml \
      php${data.coder_parameter.php_version.value}-zip \
      php${data.coder_parameter.php_version.value}-bcmath \
      php${data.coder_parameter.php_version.value}-soap \
      php${data.coder_parameter.php_version.value}-intl \
      php${data.coder_parameter.php_version.value}-readline \
      php${data.coder_parameter.php_version.value}-ldap \
      php${data.coder_parameter.php_version.value}-msgpack \
      php${data.coder_parameter.php_version.value}-igbinary \
      php${data.coder_parameter.php_version.value}-redis \
      php${data.coder_parameter.php_version.value}-memcached \
      php${data.coder_parameter.php_version.value}-pcov \
      php${data.coder_parameter.php_version.value}-xdebug

    # Install Composer
    echo "🎵 Installing Composer..."
    curl -sS https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer
    sudo chmod +x /usr/local/bin/composer

    # Install Symfony CLI
    echo "🎼 Installing Symfony CLI..."
    curl -1sLf 'https://dl.cloudsmith.io/public/symfony/stable/setup.deb.sh' | sudo -E bash
    sudo apt update
    sudo apt install -y symfony-cli

    # Install Node.js for asset management
    echo "📦 Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    npm install -g yarn

    # Install useful development tools
    sudo apt-get install -y \
      postgresql-client \
      redis-tools \
      htop \
      tree \
      jq \
      nginx \
      supervisor

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

        # Install PHP extensions
        code --install-extension bmewburn.vscode-intelephense-client
        code --install-extension ms-vscode.vscode-json
        code --install-extension bradlc.vscode-tailwindcss
        code --install-extension esbenp.prettier-vscode
        code --install-extension xdebug.php-debug
        code --install-extension zobo.php-intellisense
        ;;
      "phpstorm")
        echo "🧠 Installing PhpStorm..."
        wget -q https://download.jetbrains.com/webide/PhpStorm-2023.3.2.tar.gz -O /tmp/phpstorm.tar.gz
        sudo tar -xzf /tmp/phpstorm.tar.gz -C /opt
        sudo ln -sf /opt/PhpStorm-*/bin/phpstorm.sh /usr/local/bin/phpstorm
        rm /tmp/phpstorm.tar.gz
        ;;
    esac

    # Create Symfony project
    echo "🎼 Creating Symfony ${data.coder_parameter.symfony_version.value} project..."
    cd /home/coder

    # Create new Symfony project
    symfony new symfony-neuron-app --version="${data.coder_parameter.symfony_version.value}.*" --webapp
    cd symfony-neuron-app

    # Install additional Symfony packages
    composer require \
      doctrine/doctrine-bundle \
      doctrine/doctrine-migrations-bundle \
      doctrine/orm \
      symfony/serializer \
      symfony/validator \
      symfony/form \
      symfony/security-bundle \
      symfony/monolog-bundle \
      symfony/mailer \
      symfony/notifier \
      symfony/workflow \
      symfony/messenger \
      symfony/cache \
      symfony/http-client \
      api-platform/core \
      nelmio/cors-bundle \
      lexik/jwt-authentication-bundle

    # Install dev dependencies
    composer require --dev \
      symfony/debug-bundle \
      symfony/web-profiler-bundle \
      symfony/var-dumper \
      symfony/maker-bundle \
      phpunit/phpunit \
      doctrine/doctrine-fixtures-bundle \
      zenstruck/foundry

    # Install Neuron AI framework if enabled
    if [[ "${data.coder_parameter.neuron_features.value}" == "true" ]]; then
      echo "🧠 Installing Neuron AI framework..."

      # Create Neuron AI service structure
      mkdir -p src/Neuron/{AI,ML,NLP,Vision}

      # Install AI/ML related packages
      composer require \
        phpml/phpml \
        rubix/ml \
        phpstan/phpstan

      # Create Neuron AI base service
      cat > src/Neuron/AI/NeuronService.php << 'EOF'
<?php

namespace App\Neuron\AI;

use Symfony\Component\DependencyInjection\Attribute\AsAlias;

#[AsAlias('neuron.ai.service')]
class NeuronService
{
    private array $models = [];
    private array $processors = [];

    public function __construct()
    {
        $this->initializeNeuralNetwork();
    }

    public function predict(array $input): array
    {
        // Neural network prediction logic
        return [
            'prediction' => $this->processInput($input),
            'confidence' => $this->calculateConfidence($input),
            'metadata' => [
                'model' => 'neuron-v1',
                'timestamp' => new \DateTime(),
            ]
        ];
    }

    public function train(array $dataset): bool
    {
        // Training logic for the neural network
        foreach ($dataset as $sample) {
            $this->processSample($sample);
        }

        return true;
    }

    public function addProcessor(string $name, callable $processor): self
    {
        $this->processors[$name] = $processor;
        return $this;
    }

    private function initializeNeuralNetwork(): void
    {
        // Initialize neural network components
        $this->models['default'] = [
            'layers' => 3,
            'neurons' => [128, 64, 32],
            'activation' => 'relu',
        ];
    }

    private function processInput(array $input): mixed
    {
        // Process input through neural network
        $processed = $input;

        foreach ($this->processors as $processor) {
            $processed = $processor($processed);
        }

        return $processed;
    }

    private function calculateConfidence(array $input): float
    {
        // Calculate prediction confidence
        return min(1.0, max(0.0, count($input) * 0.1));
    }

    private function processSample(array $sample): void
    {
        // Process training sample
        // This would contain actual ML training logic
    }
}
EOF

      # Create Neuron NLP service
      cat > src/Neuron/NLP/TextAnalyzer.php << 'EOF'
<?php

namespace App\Neuron\NLP;

use Symfony\Component\DependencyInjection\Attribute\AsAlias;

#[AsAlias('neuron.nlp.analyzer')]
class TextAnalyzer
{
    public function analyzeSentiment(string $text): array
    {
        $words = str_word_count(strtolower($text), 1);
        $positiveWords = ['good', 'great', 'excellent', 'amazing', 'wonderful', 'fantastic'];
        $negativeWords = ['bad', 'terrible', 'awful', 'horrible', 'disappointing', 'poor'];

        $positiveCount = count(array_intersect($words, $positiveWords));
        $negativeCount = count(array_intersect($words, $negativeWords));
        $totalWords = count($words);

        if ($positiveCount > $negativeCount) {
            $sentiment = 'positive';
            $score = $positiveCount / $totalWords;
        } elseif ($negativeCount > $positiveCount) {
            $sentiment = 'negative';
            $score = -($negativeCount / $totalWords);
        } else {
            $sentiment = 'neutral';
            $score = 0;
        }

        return [
            'sentiment' => $sentiment,
            'score' => round($score, 3),
            'confidence' => abs($score),
            'word_count' => $totalWords,
            'positive_words' => $positiveCount,
            'negative_words' => $negativeCount,
        ];
    }

    public function extractKeywords(string $text, int $limit = 10): array
    {
        $words = str_word_count(strtolower($text), 1);
        $stopWords = ['the', 'is', 'at', 'which', 'on', 'and', 'a', 'to', 'are', 'as', 'was', 'were', 'been', 'be'];

        $filteredWords = array_diff($words, $stopWords);
        $wordFreq = array_count_values($filteredWords);
        arsort($wordFreq);

        return array_slice(array_keys($wordFreq), 0, $limit);
    }

    public function summarize(string $text, int $sentences = 3): string
    {
        $sentences_array = preg_split('/[.!?]+/', $text, -1, PREG_SPLIT_NO_EMPTY);

        if (count($sentences_array) <= $sentences) {
            return $text;
        }

        // Simple extractive summarization
        $keywords = $this->extractKeywords($text);
        $scored_sentences = [];

        foreach ($sentences_array as $index => $sentence) {
            $score = 0;
            foreach ($keywords as $keyword) {
                if (stripos($sentence, $keyword) !== false) {
                    $score++;
                }
            }
            $scored_sentences[$index] = ['sentence' => trim($sentence), 'score' => $score];
        }

        usort($scored_sentences, fn($a, $b) => $b['score'] <=> $a['score']);

        $top_sentences = array_slice($scored_sentences, 0, $sentences);
        usort($top_sentences, fn($a, $b) => $a['sentence'] <=> $b['sentence']);

        return implode('. ', array_column($top_sentences, 'sentence')) . '.';
    }
}
EOF

      # Create API controller for Neuron services
      cat > src/Controller/NeuronController.php << 'EOF'
<?php

namespace App\Controller;

use App\Neuron\AI\NeuronService;
use App\Neuron\NLP\TextAnalyzer;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Annotation\Route;

#[Route('/api/neuron', name: 'neuron_')]
class NeuronController extends AbstractController
{
    public function __construct(
        private NeuronService $neuronService,
        private TextAnalyzer $textAnalyzer
    ) {}

    #[Route('/predict', name: 'predict', methods: ['POST'])]
    public function predict(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        if (!isset($data['input'])) {
            return $this->json(['error' => 'Input data required'], 400);
        }

        $result = $this->neuronService->predict($data['input']);

        return $this->json([
            'status' => 'success',
            'data' => $result
        ]);
    }

    #[Route('/analyze/sentiment', name: 'sentiment', methods: ['POST'])]
    public function analyzeSentiment(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        if (!isset($data['text'])) {
            return $this->json(['error' => 'Text required'], 400);
        }

        $result = $this->textAnalyzer->analyzeSentiment($data['text']);

        return $this->json([
            'status' => 'success',
            'data' => $result
        ]);
    }

    #[Route('/analyze/keywords', name: 'keywords', methods: ['POST'])]
    public function extractKeywords(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        if (!isset($data['text'])) {
            return $this->json(['error' => 'Text required'], 400);
        }

        $limit = $data['limit'] ?? 10;
        $keywords = $this->textAnalyzer->extractKeywords($data['text'], $limit);

        return $this->json([
            'status' => 'success',
            'data' => ['keywords' => $keywords]
        ]);
    }

    #[Route('/analyze/summarize', name: 'summarize', methods: ['POST'])]
    public function summarize(Request $request): JsonResponse
    {
        $data = json_decode($request->getContent(), true);

        if (!isset($data['text'])) {
            return $this->json(['error' => 'Text required'], 400);
        }

        $sentences = $data['sentences'] ?? 3;
        $summary = $this->textAnalyzer->summarize($data['text'], $sentences);

        return $this->json([
            'status' => 'success',
            'data' => ['summary' => $summary]
        ]);
    }

    #[Route('/health', name: 'health', methods: ['GET'])]
    public function health(): JsonResponse
    {
        return $this->json([
            'status' => 'success',
            'message' => 'Neuron AI services are running',
            'services' => [
                'neural_network' => 'active',
                'nlp_analyzer' => 'active',
                'text_processing' => 'active'
            ],
            'timestamp' => new \DateTime()
        ]);
    }
}
EOF
    fi

    # Create sample entity
    php bin/console make:entity Post --no-interaction

    # Create API controller
    cat > src/Controller/ApiController.php << 'EOF'
<?php

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Annotation\Route;

#[Route('/api', name: 'api_')]
class ApiController extends AbstractController
{
    #[Route('/health', name: 'health')]
    public function health(): JsonResponse
    {
        return $this->json([
            'status' => 'success',
            'message' => 'Symfony API is running!',
            'symfony_version' => \Symfony\Component\HttpKernel\Kernel::VERSION,
            'php_version' => PHP_VERSION,
            'neuron_enabled' => ${data.coder_parameter.neuron_features.value ? 'true' : 'false'},
            'timestamp' => new \DateTime()
        ]);
    }
}
EOF

    # Configure database
    cat > .env.local << 'EOF'
DATABASE_URL="postgresql://postgres:password@localhost:5432/symfony_neuron?serverVersion=15&charset=utf8"
REDIS_URL=redis://localhost:6379
APP_ENV=dev
APP_SECRET=$(php -r "echo bin2hex(random_bytes(32));")
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "8000:8000"
    environment:
      - APP_ENV=dev
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/symfony_neuron?serverVersion=15&charset=utf8
      - REDIS_URL=redis://redis:6379
    depends_on:
      - postgres
      - redis
    volumes:
      - .:/app
    command: symfony serve --host=0.0.0.0 --port=8000

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: symfony_neuron
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./docker/nginx/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - app

volumes:
  postgres_data:
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
    git \
    curl \
    libpng-dev \
    oniguruma-dev \
    libxml2-dev \
    zip \
    unzip \
    postgresql-dev \
    icu-dev \
    freetype-dev \
    libjpeg-turbo-dev \
    libzip-dev

RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install \
    pdo_pgsql \
    mbstring \
    xml \
    gd \
    zip \
    intl \
    opcache \
    bcmath

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install --no-dev --optimize-autoloader

COPY . .

RUN chown -R www-data:www-data /app

EXPOSE 8000

CMD ["php", "-S", "0.0.0.0:8000", "-t", "public"]
EOF

    # Create nginx configuration
    mkdir -p docker/nginx
    cat > docker/nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream app {
        server app:8000;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://app;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

    # Install JavaScript dependencies
    yarn install

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/symfony-neuron-app

    # Run initial setup
    cd /home/coder/symfony-neuron-app

    echo "✅ PHP Symfony + Neuron AI development environment ready!"
    echo "Run 'symfony serve' to start the development server"

  EOT

  # Metadata
  metadata {
    display_name = "PHP Version"
    key          = "php_version"
    value        = data.coder_parameter.php_version.value
  }

  metadata {
    display_name = "Symfony Version"
    key          = "symfony_version"
    value        = data.coder_parameter.symfony_version.value
  }

  metadata {
    display_name = "Neuron AI Enabled"
    key          = "neuron_features"
    value        = data.coder_parameter.neuron_features.value
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

  metadata {
    display_name = "IDE"
    key          = "ide"
    value        = data.coder_parameter.ide.value
  }
}

# Applications
resource "coder_app" "symfony_app" {
  agent_id     = coder_agent.main.id
  slug         = "symfony-app"
  display_name = "Symfony Application"
  url          = "http://localhost:8000"
  icon         = "/icon/symfony.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8000/api/health"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "neuron_api" {
  count        = data.coder_parameter.neuron_features.value ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "neuron-api"
  display_name = "Neuron AI API"
  url          = "http://localhost:8000/api/neuron/health"
  icon         = "/icon/ai.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "vscode" {
  count        = data.coder_parameter.ide.value == "vscode" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/symfony-neuron-app"
  share        = "owner"
}

resource "coder_app" "phpstorm" {
  count        = data.coder_parameter.ide.value == "phpstorm" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "phpstorm"
  display_name = "PhpStorm"
  icon         = "/icon/phpstorm.svg"
  command      = "phpstorm /home/coder/symfony-neuron-app"
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