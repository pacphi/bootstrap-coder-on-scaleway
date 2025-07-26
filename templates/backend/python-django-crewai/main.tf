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
    name  = "6 GB"
    value = "6"
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

data "coder_parameter" "python_version" {
  name         = "python_version"
  display_name = "Python Version"
  description  = "Python version to install"
  default      = "3.12"
  icon         = "/icon/python.svg"
  mutable      = false
  option {
    name  = "Python 3.11"
    value = "3.11"
  }
  option {
    name  = "Python 3.12"
    value = "3.12"
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
    name  = "PyCharm Community"
    value = "pycharm"
  }
  option {
    name  = "Terminal Only"
    value = "terminal"
  }
}

data "coder_parameter" "enable_crewai" {
  name         = "enable_crewai"
  display_name = "Enable CrewAI"
  description  = "Install and configure CrewAI for multi-agent workflows"
  default      = "true"
  type         = "bool"
  icon         = "/icon/ai.svg"
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

    # Update system
    sudo apt-get update
    sudo apt-get install -y software-properties-common

    # Install Python ${data.coder_parameter.python_version.value}
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt-get update
    sudo apt-get install -y python${data.coder_parameter.python_version.value} python${data.coder_parameter.python_version.value}-dev python${data.coder_parameter.python_version.value}-venv python3-pip

    # Set Python ${data.coder_parameter.python_version.value} as default
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${data.coder_parameter.python_version.value} 1
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python${data.coder_parameter.python_version.value} 1

    # Install Poetry for dependency management
    curl -sSL https://install.python-poetry.org | python3 -
    export PATH="/home/coder/.local/bin:$PATH"
    echo 'export PATH="/home/coder/.local/bin:$PATH"' >> /home/coder/.bashrc

    # Install system dependencies
    sudo apt-get install -y \
      build-essential \
      libssl-dev \
      libffi-dev \
      python3-dev \
      pkg-config \
      default-libmysqlclient-dev \
      postgresql-client \
      redis-tools \
      git \
      curl \
      wget \
      unzip \
      htop \
      tree \
      jq \
      sqlite3

    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker

    # Install Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Install Node.js (for frontend tooling)
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # IDE-specific installations
    case "${data.coder_parameter.ide.value}" in
      "vscode")
        # Install VS Code
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        sudo apt update
        sudo apt install -y code

        # Install useful VS Code extensions
        code --install-extension ms-python.python
        code --install-extension ms-python.black-formatter
        code --install-extension ms-python.isort
        code --install-extension ms-python.pylint
        code --install-extension batisteo.vscode-django
        code --install-extension ms-vscode.vscode-json
        ;;
      "pycharm")
        # Download and install PyCharm Community
        wget -q https://download.jetbrains.com/python/pycharm-community-2023.3.2.tar.gz -O /tmp/pycharm.tar.gz
        sudo tar -xzf /tmp/pycharm.tar.gz -C /opt
        sudo ln -sf /opt/pycharm-community-*/bin/pycharm.sh /usr/local/bin/pycharm
        ;;
    esac

    # Create Django project with CrewAI
    cd /home/coder

    # Initialize Poetry project
    poetry new django-crewai-project
    cd django-crewai-project

    # Configure Poetry
    cat > pyproject.toml << 'EOF'
[tool.poetry]
name = "django-crewai-project"
version = "0.1.0"
description = "Django project with CrewAI multi-agent workflows"
authors = ["Coder <coder@example.com>"]
readme = "README.md"

[tool.poetry.dependencies]
python = "^${data.coder_parameter.python_version.value}"
django = "^5.0.0"
djangorestframework = "^3.14.0"
celery = "^5.3.0"
redis = "^5.0.0"
psycopg2-binary = "^2.9.0"
django-cors-headers = "^4.3.0"
python-decouple = "^3.8"
crewai = {version = "^0.22.0", optional = ${data.coder_parameter.enable_crewai.value}}
crewai-tools = {version = "^0.1.0", optional = ${data.coder_parameter.enable_crewai.value}}
langchain = {version = "^0.1.0", optional = ${data.coder_parameter.enable_crewai.value}}
langchain-openai = {version = "^0.0.5", optional = ${data.coder_parameter.enable_crewai.value}}

[tool.poetry.extras]
ai = ["crewai", "crewai-tools", "langchain", "langchain-openai"]

[tool.poetry.group.dev.dependencies]
pytest = "^7.4.0"
pytest-django = "^4.7.0"
black = "^23.12.0"
isort = "^5.13.0"
flake8 = "^7.0.0"
mypy = "^1.8.0"
django-debug-toolbar = "^4.2.0"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"

[tool.black]
line-length = 88
target-version = ['py311']
include = '\.pyi?$'

[tool.isort]
profile = "black"
multi_line_output = 3
line_length = 88
EOF

    # Install dependencies
    export PATH="/home/coder/.local/bin:$PATH"
    poetry install ${data.coder_parameter.enable_crewai.value == "true" ? "--extras ai" : ""}

    # Create Django project structure
    poetry run django-admin startproject config .
    poetry run python manage.py startapp api
    ${data.coder_parameter.enable_crewai.value == "true" ? "poetry run python manage.py startapp agents" : ""}

    # Configure Django settings
    cat > config/settings.py << 'EOF'
import os
from pathlib import Path
from decouple import config

BASE_DIR = Path(__file__).resolve().parent.parent

SECRET_KEY = config('SECRET_KEY', default='django-insecure-development-key-change-in-production')
DEBUG = config('DEBUG', default=True, cast=bool)
ALLOWED_HOSTS = ['*']

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'api',
EOF

    if [[ "${data.coder_parameter.enable_crewai.value}" == "true" ]]; then
      echo "    'agents'," >> config/settings.py
    fi

    cat >> config/settings.py << 'EOF'
]

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

if DEBUG:
    MIDDLEWARE.append('debug_toolbar.middleware.DebugToolbarMiddleware')
    INSTALLED_APPS.append('debug_toolbar')
    INTERNAL_IPS = ['127.0.0.1', 'localhost']

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'config.wsgi.application'

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

# Internationalization
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'UTC'
USE_I18N = True
USE_TZ = True

# Static files
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# REST Framework
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework.authentication.SessionAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticatedOrReadOnly',
    ],
}

# CORS
CORS_ALLOW_ALL_ORIGINS = DEBUG
CORS_ALLOWED_ORIGINS = []

# Celery Configuration
CELERY_BROKER_URL = config('REDIS_URL', default='redis://localhost:6379/0')
CELERY_RESULT_BACKEND = config('REDIS_URL', default='redis://localhost:6379/0')
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = TIME_ZONE
EOF

    # Create sample API views
    cat > api/views.py << 'EOF'
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response
from django.http import JsonResponse

@api_view(['GET'])
def health_check(request):
    return Response({'status': 'healthy', 'message': 'Django + CrewAI API is running'})

@api_view(['GET'])
def api_info(request):
    return Response({
        'name': 'Django CrewAI API',
        'version': '1.0.0',
        'description': 'Django REST API with CrewAI multi-agent capabilities'
    })
EOF

    # Configure URLs
    cat > config/urls.py << 'EOF'
from django.contrib import admin
from django.urls import path, include
from api.views import health_check, api_info

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/health/', health_check, name='health_check'),
    path('api/info/', api_info, name='api_info'),
    path('api/', include('api.urls')),
]

if settings.DEBUG:
    import debug_toolbar
    urlpatterns = [
        path('__debug__/', include(debug_toolbar.urls)),
    ] + urlpatterns
EOF

    cat > api/urls.py << 'EOF'
from django.urls import path
from . import views

urlpatterns = [
    path('health/', views.health_check, name='health_check'),
    path('info/', views.api_info, name='api_info'),
]
EOF

    # Create CrewAI agents if enabled
    if [[ "${data.coder_parameter.enable_crewai.value}" == "true" ]]; then
      cat > agents/crew.py << 'EOF'
from crewai import Agent, Task, Crew, Process
from crewai_tools import SerperDevTool, WebsiteSearchTool
import os

# Initialize tools
search_tool = SerperDevTool()
web_search_tool = WebsiteSearchTool()

class ContentCrewAI:
    def __init__(self):
        self.researcher = Agent(
            role='Senior Research Analyst',
            goal='Uncover cutting-edge developments in AI and technology',
            backstory='You work at a leading tech think tank. Your expertise lies in identifying emerging trends and technologies that could reshape industries.',
            verbose=True,
            allow_delegation=False,
            tools=[search_tool, web_search_tool]
        )

        self.writer = Agent(
            role='Tech Content Writer',
            goal='Craft compelling content about technology trends',
            backstory='You are a renowned tech writer, known for your ability to simplify complex topics and make them engaging for a broad audience.',
            verbose=True,
            allow_delegation=True
        )

    def create_content(self, topic):
        research_task = Task(
            description=f'Conduct a comprehensive analysis of {topic}. Identify key trends, major players, and potential impact on various industries.',
            agent=self.researcher,
            expected_output='A detailed research report with key findings and insights'
        )

        write_task = Task(
            description=f'Create an engaging blog post about {topic} based on the research findings. The post should be informative yet accessible to a general audience.',
            agent=self.writer,
            expected_output='A well-structured blog post with clear headings and engaging content',
            context=[research_task]
        )

        crew = Crew(
            agents=[self.researcher, self.writer],
            tasks=[research_task, write_task],
            verbose=2,
            process=Process.sequential
        )

        return crew.kickoff()
EOF

      cat > agents/views.py << 'EOF'
from rest_framework import status
from rest_framework.decorators import api_view
from rest_framework.response import Response
from .crew import ContentCrewAI

@api_view(['POST'])
def create_content(request):
    topic = request.data.get('topic')
    if not topic:
        return Response({'error': 'Topic is required'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        crew = ContentCrewAI()
        result = crew.create_content(topic)
        return Response({'content': result}, status=status.HTTP_200_OK)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

@api_view(['GET'])
def agents_status(request):
    return Response({
        'status': 'active',
        'available_agents': ['researcher', 'writer'],
        'description': 'CrewAI multi-agent system for content creation'
    })
EOF

      cat > agents/urls.py << 'EOF'
from django.urls import path
from . import views

urlpatterns = [
    path('create-content/', views.create_content, name='create_content'),
    path('status/', views.agents_status, name='agents_status'),
]
EOF

      # Add agents URLs to main config
      sed -i "/path('api\/', include('api.urls')),/a\\    path('agents/', include('agents.urls'))," config/urls.py
    fi

    # Create environment file
    cat > .env << 'EOF'
DEBUG=True
SECRET_KEY=django-insecure-development-key-change-in-production
REDIS_URL=redis://localhost:6379/0
# Add your AI API keys here
# OPENAI_API_KEY=your_openai_api_key
# SERPER_API_KEY=your_serper_api_key
EOF

    # Run migrations
    poetry run python manage.py makemigrations
    poetry run python manage.py migrate

    # Create superuser
    echo "from django.contrib.auth import get_user_model; User = get_user_model(); User.objects.create_superuser('admin', 'admin@example.com', 'admin123')" | poetry run python manage.py shell

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/django-crewai-project

    # Create startup scripts
    cat > /home/coder/start-django.sh << 'EOF'
#!/bin/bash
cd /home/coder/django-crewai-project
poetry run python manage.py runserver 0.0.0.0:8000
EOF
    chmod +x /home/coder/start-django.sh

    cat > /home/coder/start-celery.sh << 'EOF'
#!/bin/bash
cd /home/coder/django-crewai-project
poetry run celery -A config worker -l info
EOF
    chmod +x /home/coder/start-celery.sh

  EOT

}

# Metadata
resource "coder_metadata" "python_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "python_version"
    value = data.coder_parameter.python_version.value
  }
}

resource "coder_metadata" "crewai_enabled" {
  resource_id = coder_agent.main.id
  item {
    key   = "crewai_enabled"
    value = data.coder_parameter.enable_crewai.value ? "enabled" : "disabled"
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
resource "coder_app" "django" {
  agent_id     = coder_agent.main.id
  slug         = "django"
  display_name = "Django Server"
  url          = "http://localhost:8000"
  icon         = "/icon/django.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8000/api/health/"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "django_admin" {
  agent_id     = coder_agent.main.id
  slug         = "django-admin"
  display_name = "Django Admin"
  url          = "http://localhost:8000/admin/"
  icon         = "/icon/django.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "vscode" {
  count        = data.coder_parameter.ide.value == "vscode" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/django-crewai-project"
  share        = "owner"
}

resource "coder_app" "pycharm" {
  count        = data.coder_parameter.ide.value == "pycharm" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "pycharm"
  display_name = "PyCharm"
  icon         = "/icon/pycharm.svg"
  command      = "pycharm /home/coder/django-crewai-project"
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
