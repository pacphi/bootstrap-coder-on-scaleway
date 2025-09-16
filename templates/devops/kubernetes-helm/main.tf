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

data "coder_parameter" "k8s_version" {
  name         = "k8s_version"
  display_name = "Kubernetes Version"
  description  = "Kubernetes version to work with"
  default      = "1.32"
  icon         = "/icon/kubernetes.svg"
  mutable      = false
  option {
    name  = "Kubernetes 1.31"
    value = "1.31"
  }
  option {
    name  = "Kubernetes 1.32"
    value = "1.32"
  }
  option {
    name  = "Kubernetes 1.33"
    value = "1.33"
  }
}

data "coder_parameter" "helm_version" {
  name         = "helm_version"
  display_name = "Helm Version"
  description  = "Helm version to install"
  default      = "3.13"
  icon         = "/icon/helm.svg"
  mutable      = false
  option {
    name  = "Helm 3.12"
    value = "3.12"
  }
  option {
    name  = "Helm 3.13"
    value = "3.13"
  }
  option {
    name  = "Helm 3.14"
    value = "3.14"
  }
}

data "coder_parameter" "additional_tools" {
  name         = "additional_tools"
  display_name = "Additional K8s Tools"
  description  = "Additional Kubernetes tools to install"
  default      = "istio,kustomize"
  icon         = "/icon/tools.svg"
  mutable      = false
  option {
    name  = "Essential (k9s, kubectx, stern)"
    value = "essential"
  }
  option {
    name  = "Service Mesh (Istio + Linkerd)"
    value = "istio,linkerd"
  }
  option {
    name  = "GitOps (ArgoCD + Flux)"
    value = "argocd,flux"
  }
  option {
    name  = "All Tools"
    value = "istio,linkerd,argocd,flux,kustomize,skaffold"
  }
}

data "coder_parameter" "enable_monitoring" {
  name         = "enable_monitoring"
  display_name = "Enable Monitoring Stack"
  description  = "Install monitoring and observability tools"
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
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash

    echo "☸️ Setting up Kubernetes + Helm DevOps environment..."

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

    # Install Docker
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

    # Install kubectl
    echo "☸️ Installing kubectl..."
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    sudo install kubectl /usr/local/bin/
    rm kubectl

    # Install Helm ${data.coder_parameter.helm_version.value}
    echo "⛵ Installing Helm ${data.coder_parameter.helm_version.value}..."
    HELM_VERSION="${data.coder_parameter.helm_version.value}"
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    DESIRED_VERSION=v$${HELM_VERSION}.0 ./get_helm.sh
    rm get_helm.sh

    # Install essential Kubernetes tools
    echo "🛠️ Installing essential Kubernetes tools..."

    # k9s
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)
    wget -O k9s.tar.gz "https://github.com/derailed/k9s/releases/download/$${K9S_VERSION}/k9s_Linux_amd64.tar.gz"
    tar xf k9s.tar.gz k9s
    sudo mv k9s /usr/local/bin/
    rm k9s.tar.gz

    # kubectx and kubens
    sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
    sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
    sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

    # stern (log tailing)
    STERN_VERSION=$(curl -s https://api.github.com/repos/stern/stern/releases/latest | jq -r .tag_name)
    wget -O stern.tar.gz "https://github.com/stern/stern/releases/download/$${STERN_VERSION}/stern_$${STERN_VERSION#v}_linux_amd64.tar.gz"
    tar xf stern.tar.gz stern
    sudo mv stern /usr/local/bin/
    rm stern.tar.gz

    # kustomize
    KUSTOMIZE_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep kustomize/v | jq -r .tag_name | head -1)
    wget -O kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/$${KUSTOMIZE_VERSION}/kustomize_$${KUSTOMIZE_VERSION#kustomize/v}_linux_amd64.tar.gz"
    tar xf kustomize.tar.gz kustomize
    sudo mv kustomize /usr/local/bin/
    rm kustomize.tar.gz

    # Install additional tools based on selection
    IFS=',' read -ra TOOLS <<< "${data.coder_parameter.additional_tools.value}"
    for tool in "$${TOOLS[@]}"; do
      case "$tool" in
        "istio")
          echo "🕸️ Installing Istio..."
          ISTIO_VERSION=$(curl -s https://api.github.com/repos/istio/istio/releases/latest | jq -r .tag_name)
          curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$${ISTIO_VERSION} TARGET_ARCH=x86_64 sh -
          sudo mv istio-$${ISTIO_VERSION}/bin/istioctl /usr/local/bin/
          rm -rf istio-$${ISTIO_VERSION}
          ;;
        "linkerd")
          echo "🔗 Installing Linkerd..."
          curl -fsL https://run.linkerd.io/install | sh
          sudo mv ~/.linkerd2/bin/linkerd /usr/local/bin/
          ;;
        "argocd")
          echo "🚀 Installing ArgoCD CLI..."
          ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r .tag_name)
          wget -O argocd "https://github.com/argoproj/argo-cd/releases/download/$${ARGOCD_VERSION}/argocd-linux-amd64"
          sudo mv argocd /usr/local/bin/
          sudo chmod +x /usr/local/bin/argocd
          ;;
        "flux")
          echo "🌊 Installing Flux CLI..."
          curl -s https://fluxcd.io/install.sh | sudo bash
          ;;
        "skaffold")
          echo "🏗️ Installing Skaffold..."
          curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
          sudo install skaffold /usr/local/bin/
          rm skaffold
          ;;
      esac
    done

    # Install monitoring tools if enabled
    if [[ "${data.coder_parameter.enable_monitoring.value}" == "true" ]]; then
      echo "📊 Installing monitoring tools..."

      # Prometheus CLI (promtool)
      PROMETHEUS_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | jq -r .tag_name)
      wget -O prometheus.tar.gz "https://github.com/prometheus/prometheus/releases/download/$${PROMETHEUS_VERSION}/prometheus-$${PROMETHEUS_VERSION#v}.linux-amd64.tar.gz"
      tar xf prometheus.tar.gz
      sudo mv prometheus-$${PROMETHEUS_VERSION#v}.linux-amd64/promtool /usr/local/bin/
      rm -rf prometheus*

      # Grafana CLI
      curl -s https://raw.githubusercontent.com/grafana/grafana/main/scripts/grafana-cli.sh | sudo bash
    fi

    # Install VS Code
    echo "💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install VS Code extensions
    code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
    code --install-extension ms-azuretools.vscode-docker
    code --install-extension redhat.vscode-yaml
    code --install-extension ms-vscode.vscode-json
    code --install-extension GitHub.copilot
    code --install-extension Tim-Koehler.helm-intellisense
    code --install-extension ms-vscode-remote.remote-containers
    code --install-extension ms-python.python

    # Create project structure
    cd /home/coder
    mkdir -p {helm/{charts,values,releases},k8s/{manifests,kustomize/{base,overlays/{dev,staging,prod}},operators},monitoring/{prometheus,grafana,alertmanager},scripts,docs}

    # Add Helm repositories
    echo "⛵ Adding popular Helm repositories..."
    helm repo add stable https://charts.helm.sh/stable
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo add jetstack https://charts.jetstack.io
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo add elastic https://helm.elastic.co
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo add linkerd https://helm.linkerd.io/stable
    helm repo update

    # Create sample Helm chart
    cd helm/charts
    helm create sample-app

    # Customize the sample chart
    cat > sample-app/values.yaml << 'EOF'
replicaCount: 2

image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: "1.21"

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  annotations: {}
  name: ""

podAnnotations: {}
podSecurityContext: {}
securityContext: {}

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  className: "nginx"
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: sample-app.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: sample-app-tls
      hosts:
        - sample-app.example.com

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80

nodeSelector: {}
tolerations: []
affinity: {}

# Application specific configuration
config:
  environment: production
  logLevel: info
  features:
    authentication: true
    monitoring: true
    caching: true

# Database configuration
database:
  enabled: true
  type: postgresql
  host: postgresql.database.svc.cluster.local
  port: 5432
  name: sampleapp
  username: sampleapp
  existingSecret: sample-app-db-secret

# Redis configuration
redis:
  enabled: true
  host: redis.cache.svc.cluster.local
  port: 6379
EOF

    # Create environment-specific values files
    cat > sample-app/values-dev.yaml << 'EOF'
replicaCount: 1

image:
  tag: "dev"

ingress:
  hosts:
    - host: sample-app-dev.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: sample-app-dev-tls
      hosts:
        - sample-app-dev.example.com

resources:
  limits:
    cpu: 50m
    memory: 64Mi
  requests:
    cpu: 50m
    memory: 64Mi

autoscaling:
  enabled: false

config:
  environment: development
  logLevel: debug
  features:
    authentication: false
    monitoring: true
    caching: false

database:
  name: sampleapp_dev
EOF

    # Create Kubernetes manifests
    cd /home/coder/k8s/manifests

    # Create namespace manifest
    cat > namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: sample-app
  labels:
    name: sample-app
    environment: production
    managed-by: helm
---
apiVersion: v1
kind: Namespace
metadata:
  name: sample-app-dev
  labels:
    name: sample-app-dev
    environment: development
    managed-by: helm
EOF

    # Create ConfigMap example
    cat > configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: sample-app
data:
  config.yaml: |
    server:
      port: 8080
      host: 0.0.0.0
    database:
      host: postgresql.database.svc.cluster.local
      port: 5432
      name: sampleapp
    redis:
      host: redis.cache.svc.cluster.local
      port: 6379
    logging:
      level: info
      format: json
  nginx.conf: |
    upstream backend {
        server app:8080;
    }

    server {
        listen 80;
        server_name sample-app.example.com;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        location /health {
            access_log off;
            return 200 "healthy\n";
        }
    }
EOF

    # Create Secret example
    cat > secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: sample-app
type: Opaque
data:
  # These are base64 encoded values
  # Use: echo -n 'your-secret' | base64
  database-password: <BASE64_ENCODED_DB_PASSWORD>  # Replace with: echo -n 'your-db-password' | base64
  api-key: <BASE64_ENCODED_API_KEY>             # Replace with: echo -n 'your-api-key' | base64
  jwt-secret: <BASE64_ENCODED_JWT_SECRET>       # Replace with: echo -n 'your-jwt-secret' | base64
stringData:
  # These will be automatically base64 encoded
  database-url: "postgresql://user:password@postgresql.database.svc.cluster.local:5432/sampleapp"
  redis-url: "redis://redis.cache.svc.cluster.local:6379"
EOF

    # Create PersistentVolumeClaim example
    cat > pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: sample-app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 10Gi
EOF

    # Create Deployment example
    cat > deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: sample-app
  labels:
    app: sample-app
    version: v1.0.0
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
        version: v1.0.0
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: sample-app
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: app
        image: nginx:1.21
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: redis-url
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: api-key
        volumeMounts:
        - name: config
          mountPath: /etc/app
        - name: data
          mountPath: /data
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: config
        configMap:
          name: app-config
      - name: data
        persistentVolumeClaim:
          claimName: app-data
EOF

    # Create Service example
    cat > service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: sample-app
  namespace: sample-app
  labels:
    app: sample-app
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: sample-app
EOF

    # Create Ingress example
    cat > ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app
  namespace: sample-app
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - sample-app.example.com
    secretName: sample-app-tls
  rules:
  - host: sample-app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-app
            port:
              number: 80
EOF

    # Create HorizontalPodAutoscaler
    cat > hpa.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: sample-app-hpa
  namespace: sample-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
      - type: Pods
        value: 2
        periodSeconds: 60
EOF

    # Create Kustomize base
    cd /home/coder/k8s/kustomize/base

    cat > kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../manifests/namespace.yaml
- ../../manifests/configmap.yaml
- ../../manifests/secret.yaml
- ../../manifests/pvc.yaml
- ../../manifests/deployment.yaml
- ../../manifests/service.yaml
- ../../manifests/ingress.yaml
- ../../manifests/hpa.yaml

commonLabels:
  app: sample-app
  managed-by: kustomize

images:
- name: nginx
  newTag: "1.21"
EOF

    # Create development overlay
    cd /home/coder/k8s/kustomize/overlays/dev

    cat > kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

namePrefix: dev-

commonLabels:
  environment: development

replicas:
- name: sample-app
  count: 1

images:
- name: nginx
  newTag: "dev"

patchesStrategicMerge:
- resources-patch.yaml
- ingress-patch.yaml

configMapGenerator:
- name: app-config
  behavior: merge
  literals:
  - LOG_LEVEL=debug
  - ENVIRONMENT=development
EOF

    cat > resources-patch.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
EOF

    cat > ingress-patch.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app
spec:
  rules:
  - host: sample-app-dev.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-app
            port:
              number: 80
  tls:
  - hosts:
    - sample-app-dev.example.com
    secretName: sample-app-dev-tls
EOF

    # Create monitoring configuration if enabled
    if [[ "${data.coder_parameter.enable_monitoring.value}" == "true" ]]; then
      cd /home/coder/monitoring

      # Create Prometheus values
      cat > prometheus/values.yaml << 'EOF'
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: fast-ssd
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

    resources:
      requests:
        cpu: 200m
        memory: 2Gi
      limits:
        cpu: 1000m
        memory: 4Gi

    additionalScrapeConfigs:
    - job_name: 'kubernetes-pods'
      kubernetes_sd_configs:
      - role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)

grafana:
  adminPassword: admin123
  persistence:
    enabled: true
    storageClassName: fast-ssd
    size: 10Gi

  grafana.ini:
    server:
      root_url: https://grafana.example.com
    auth.anonymous:
      enabled: false

  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

  dashboards:
    default:
      kubernetes-cluster-monitoring:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      kubernetes-pod-monitoring:
        gnetId: 6417
        revision: 1
        datasource: Prometheus

alertmanager:
  config:
    global:
      smtp_smarthost: 'localhost:587'
      smtp_from: 'alerts@example.com'

    route:
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      receiver: 'webhook'

    receivers:
    - name: 'webhook'
      webhook_configs:
      - url: 'http://webhook.example.com/alerts'
        send_resolved: true
EOF

      # Create Grafana dashboard
      mkdir -p grafana/dashboards
      cat > grafana/dashboards/application-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Application Metrics",
    "tags": ["kubernetes", "application"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "HTTP Requests",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(http_requests_total[5m])",
            "legendFormat": "{{method}} {{status}}"
          }
        ]
      },
      {
        "id": 2,
        "title": "Response Time",
        "type": "graph",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))",
            "legendFormat": "95th percentile"
          }
        ]
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "5s"
  }
}
EOF
    fi

    # Create utility scripts
    cd /home/coder/scripts

    cat > deploy-with-helm.sh << 'EOF'
#!/bin/bash
# Deploy application using Helm

set -e

CHART_PATH="../helm/charts/sample-app"
RELEASE_NAME="sample-app"
NAMESPACE="sample-app"
ENVIRONMENT=$${1:-dev}

echo "🚀 Deploying $RELEASE_NAME to $ENVIRONMENT environment..."

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Install or upgrade the Helm release
if [[ "$ENVIRONMENT" == "prod" ]]; then
  helm upgrade --install $RELEASE_NAME $CHART_PATH \
    --namespace $NAMESPACE \
    --values $CHART_PATH/values.yaml \
    --wait \
    --timeout 300s
else
  helm upgrade --install $RELEASE_NAME-$ENVIRONMENT $CHART_PATH \
    --namespace $NAMESPACE-$ENVIRONMENT \
    --values $CHART_PATH/values.yaml \
    --values $CHART_PATH/values-$ENVIRONMENT.yaml \
    --wait \
    --timeout 300s
fi

echo "✅ Deployment complete!"
echo "📋 Release status:"
helm status $RELEASE_NAME-$ENVIRONMENT --namespace $NAMESPACE-$ENVIRONMENT
EOF

    cat > deploy-with-kustomize.sh << 'EOF'
#!/bin/bash
# Deploy application using Kustomize

set -e

ENVIRONMENT=$${1:-dev}
OVERLAY_PATH="../k8s/kustomize/overlays/$ENVIRONMENT"

echo "🚀 Deploying to $ENVIRONMENT environment using Kustomize..."

if [[ ! -d "$OVERLAY_PATH" ]]; then
  echo "❌ Environment '$ENVIRONMENT' not found in $OVERLAY_PATH"
  exit 1
fi

# Apply the manifests
kubectl apply -k $OVERLAY_PATH

echo "✅ Deployment complete!"
echo "📋 Checking deployment status..."
kubectl get pods -n sample-app-$ENVIRONMENT
EOF

    cat > install-monitoring.sh << 'EOF'
#!/bin/bash
# Install monitoring stack (Prometheus, Grafana, Alertmanager)

set -e

echo "📊 Installing monitoring stack..."

# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values ../monitoring/prometheus/values.yaml \
  --wait \
  --timeout 600s

echo "✅ Monitoring stack installed!"
echo "🔗 Access URLs:"
echo "  Prometheus: kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090"
echo "  Grafana: kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80"
echo "  AlertManager: kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093"
echo ""
echo "📝 Default Grafana credentials: admin / admin123"
EOF

    cat > cleanup.sh << 'EOF'
#!/bin/bash
# Cleanup all deployments

set -e

ENVIRONMENT=$${1:-dev}

echo "🧹 Cleaning up $ENVIRONMENT environment..."

# Delete Helm releases
helm uninstall sample-app-$ENVIRONMENT --namespace sample-app-$ENVIRONMENT || true

# Delete Kustomize resources
kubectl delete -k ../k8s/kustomize/overlays/$ENVIRONMENT || true

# Delete namespace
kubectl delete namespace sample-app-$ENVIRONMENT || true

echo "✅ Cleanup complete!"
EOF

    # Make scripts executable
    chmod +x *.sh

    # Create documentation
    cat > /home/coder/docs/README.md << 'EOF'
# Kubernetes + Helm DevOps Environment

This environment provides comprehensive tools for Kubernetes application development and deployment using Helm and native manifests.

## Tools Installed

### Core Kubernetes Tools
- kubectl ${data.coder_parameter.k8s_version.value}
- Helm ${data.coder_parameter.helm_version.value}
- k9s (Kubernetes TUI)
- kubectx/kubens (context switching)
- stern (log tailing)
- kustomize (manifest customization)

### Additional Tools
${data.coder_parameter.additional_tools.value}

### Monitoring Stack
${data.coder_parameter.enable_monitoring.value ? "✅ Prometheus, Grafana, AlertManager" : "❌ Monitoring disabled"}

## Project Structure

```
├── helm/
│   ├── charts/           # Helm charts
│   ├── values/           # Values files
│   └── releases/         # Release configurations
├── k8s/
│   ├── manifests/        # Kubernetes YAML manifests
│   └── kustomize/        # Kustomize configurations
├── monitoring/           # Monitoring configurations
├── scripts/              # Utility scripts
└── docs/                 # Documentation
```

## Quick Start

### Using Helm

1. **Deploy to development:**
   ```bash
   ./scripts/deploy-with-helm.sh dev
   ```

2. **Deploy to production:**
   ```bash
   ./scripts/deploy-with-helm.sh prod
   ```

3. **Check release status:**
   ```bash
   helm status sample-app-dev -n sample-app-dev
   ```

### Using Kustomize

1. **Deploy with Kustomize:**
   ```bash
   ./scripts/deploy-with-kustomize.sh dev
   ```

2. **View generated manifests:**
   ```bash
   kubectl kustomize k8s/kustomize/overlays/dev
   ```

### Monitoring

1. **Install monitoring stack:**
   ```bash
   ./scripts/install-monitoring.sh
   ```

2. **Access Grafana:**
   ```bash
   kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
   # Visit http://localhost:3000 (admin/admin123)
   ```

## Common Commands

### Helm Commands
```bash
# List releases
helm list -A

# Get release values
helm get values sample-app-dev -n sample-app-dev

# Rollback release
helm rollback sample-app-dev 1 -n sample-app-dev

# Uninstall release
helm uninstall sample-app-dev -n sample-app-dev
```

### kubectl Commands
```bash
# Get pods across all namespaces
kubectl get pods -A

# Describe deployment
kubectl describe deployment sample-app -n sample-app

# View logs
stern sample-app -n sample-app

# Port forward to service
kubectl port-forward svc/sample-app 8080:80 -n sample-app
```

### k9s Commands
```bash
# Launch k9s
k9s

# k9s shortcuts:
# :pods - view pods
# :svc - view services
# :deploy - view deployments
# :ns - switch namespace
# ? - help
```

## Best Practices

1. **Use Helm for Complex Applications**
   - Parametrize configurations
   - Use values files for environments
   - Implement proper rollback strategies

2. **Use Kustomize for Simple Overlays**
   - Base configurations with environment overlays
   - Good for configuration variations
   - Native Kubernetes approach

3. **Resource Management**
   - Always set resource requests/limits
   - Use HPA for auto-scaling
   - Implement proper health checks

4. **Security**
   - Use NetworkPolicies
   - Implement RBAC
   - Scan container images
   - Use Pod Security Standards

5. **Monitoring**
   - Expose metrics endpoints
   - Set up alerting rules
   - Monitor resource utilization
   - Implement distributed tracing

## Troubleshooting

### Common Issues

1. **Pod not starting:**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   kubectl logs <pod-name> -n <namespace>
   ```

2. **Service not accessible:**
   ```bash
   kubectl get endpoints <service-name> -n <namespace>
   kubectl port-forward svc/<service-name> <local-port>:<service-port> -n <namespace>
   ```

3. **Helm release failed:**
   ```bash
   helm status <release-name> -n <namespace>
   helm get all <release-name> -n <namespace>
   ```

## Development Workflow

1. **Create/Modify Helm Chart**
2. **Test with `helm template`**
3. **Deploy to dev environment**
4. **Validate deployment**
5. **Promote to staging/prod**
6. **Monitor and alert**

This environment provides everything you need for professional Kubernetes development and operations!
EOF

    # Create VS Code workspace settings
    mkdir -p .vscode
    cat > .vscode/settings.json << 'EOF'
{
    "yaml.schemas": {
        "https://raw.githubusercontent.com/instrumenta/kubernetes-json-schema/master/v1.18.0-standalone-strict/all.json": [
            "k8s/**/*.yaml",
            "k8s/**/*.yml"
        ]
    },
    "files.associations": {
        "*.yaml": "yaml",
        "*.yml": "yaml"
    },
    "editor.formatOnSave": true,
    "[yaml]": {
        "editor.insertSpaces": true,
        "editor.tabSize": 2,
        "editor.autoIndent": "advanced"
    },
    "kubernetes.kubeconfig": "",
    "kubernetes.outputFormat": "yaml"
}
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Kubernetes
*.kubeconfig
kubeconfig
.kube/config

# Helm
*.tgz
charts/*/charts/
charts/*/requirements.lock

# Secrets
secrets.yaml
*.secret
*.key
*.pem

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

# Temporary files
*.tmp
*.temp
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder

    echo "✅ Kubernetes + Helm DevOps environment ready!"
    echo "☸️ kubectl and Helm ${data.coder_parameter.helm_version.value} installed"
    echo "🛠️ Additional tools: ${data.coder_parameter.additional_tools.value}"
    echo "📊 Monitoring: ${data.coder_parameter.enable_monitoring.value ? "enabled" : "disabled"}"
    echo ""
    echo "🚀 Quick start:"
    echo "  cd /home/coder && ./scripts/deploy-with-helm.sh dev"
    echo "  k9s  # Launch Kubernetes TUI"
    echo "  helm list -A  # List all releases"

  EOT

}

# Metadata
resource "coder_metadata" "k8s_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "k8s_version"
    value = data.coder_parameter.k8s_version.value
  }
}

resource "coder_metadata" "helm_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "helm_version"
    value = data.coder_parameter.helm_version.value
  }
}

resource "coder_metadata" "additional_tools" {
  resource_id = coder_agent.main.id
  item {
    key   = "additional_tools"
    value = data.coder_parameter.additional_tools.value
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
resource "coder_app" "k9s" {
  agent_id     = coder_agent.main.id
  slug         = "k9s"
  display_name = "k9s"
  icon         = "/icon/kubernetes.svg"
  command      = "k9s"
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
  url          = "http://localhost:3000"
  icon         = "/icon/grafana.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:3000"
    interval  = 15
    threshold = 30
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

    labels = {
      "k8s-workspace" = "true"
      "helm-enabled"  = "true"
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
      "k8s-workspace"              = "true"
      "helm-enabled"               = "true"
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
          "k8s-workspace"               = "true"
        }
      }

      spec {
        security_context {
          run_as_user     = 1000
          run_as_group    = 1000
          run_as_non_root = true
          fs_group        = 1000
        }

        service_account_name = "default"

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

        # Toleration for Kubernetes workloads
        toleration {
          key      = "k8s-workloads"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.home]
}
