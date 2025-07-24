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
    name  = "12 GB"
    value = "12"
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
    min = 15
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

data "coder_parameter" "ionic_version" {
  name         = "ionic_version"
  display_name = "Ionic Version"
  description  = "Ionic version to use"
  default      = "8"
  icon         = "/icon/ionic.svg"
  mutable      = false
  option {
    name  = "Ionic 7"
    value = "7"
  }
  option {
    name  = "Ionic 8"
    value = "8"
  }
}

data "coder_parameter" "framework" {
  name         = "framework"
  display_name = "Framework Choice"
  description  = "Frontend framework for Ionic"
  default      = "angular"
  icon         = "/icon/framework.svg"
  mutable      = false
  option {
    name  = "Angular"
    value = "angular"
  }
  option {
    name  = "React"
    value = "react"
  }
  option {
    name  = "Vue"
    value = "vue"
  }
}

data "coder_parameter" "target_platform" {
  name         = "target_platform"
  display_name = "Target Platform"
  description  = "Target platforms for development"
  default      = "all"
  icon         = "/icon/mobile.svg"
  mutable      = false
  option {
    name  = "iOS Only"
    value = "ios"
  }
  option {
    name  = "Android Only"
    value = "android"
  }
  option {
    name  = "Web Only"
    value = "web"
  }
  option {
    name  = "PWA Only"
    value = "pwa"
  }
  option {
    name  = "All Platforms"
    value = "all"
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

    echo "⚡ Setting up Ionic development environment..."

    # Update system and install essential packages
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential python3 python3-pip \
      unzip zip file pkg-config libnss3-dev libatk-bridge2.0-dev \
      libdrm2 libxkbcommon-dev libxss1 libasound2-dev libgtk-3-dev \
      libgbm-dev xvfb

    # Create coder user if it doesn't exist
    if ! id -u coder &>/dev/null; then
        sudo useradd -m -s /bin/bash coder
        echo "coder ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/coder
    fi

    # Set ownership for home directory
    sudo chown -R coder:coder /home/coder
    cd /home/coder

    # Install Java 17 for Android development
    echo "☕ Installing Java 17..."
    sudo apt-get install -y openjdk-17-jdk
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> ~/.bashrc

    # Install Node.js ${data.coder_parameter.node_version.value} via NVM
    echo "📦 Installing Node.js ${data.coder_parameter.node_version.value}..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install ${data.coder_parameter.node_version.value}
    nvm use ${data.coder_parameter.node_version.value}
    nvm alias default ${data.coder_parameter.node_version.value}

    # Update PATH and environment
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc

    # Install global Node.js packages
    npm install -g yarn pnpm @ionic/cli@${data.coder_parameter.ionic_version.value}

    # Install Capacitor CLI
    echo "⚡ Installing Capacitor..."
    npm install -g @capacitor/cli @capacitor/core

    # Install Cordova for legacy support
    echo "📱 Installing Cordova..."
    npm install -g cordova

    # Install Android SDK and tools if Android development is enabled
    if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      echo "🤖 Setting up Android development environment..."

      # Install Android Command Line Tools
      mkdir -p /home/coder/Android/cmdline-tools
      cd /home/coder/Android/cmdline-tools
      wget -q https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip
      unzip -q commandlinetools-linux-10406996_latest.zip
      mv cmdline-tools latest
      rm commandlinetools-linux-10406996_latest.zip

      # Set Android environment variables
      export ANDROID_HOME=/home/coder/Android
      export ANDROID_SDK_ROOT=/home/coder/Android
      export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator

      echo 'export ANDROID_HOME=/home/coder/Android' >> ~/.bashrc
      echo 'export ANDROID_SDK_ROOT=/home/coder/Android' >> ~/.bashrc
      echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator' >> ~/.bashrc

      # Accept Android SDK licenses
      yes | sdkmanager --licenses

      # Install Android SDK platforms and tools
      sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
      sdkmanager "system-images;android-34;google_apis_playstore;x86_64"
      sdkmanager "emulator"

      # Create Android Virtual Device
      echo "📱 Creating Android Virtual Device..."
      echo "no" | avdmanager create avd -n IonicAVD -k "system-images;android-34;google_apis_playstore;x86_64" --force

      # Configure AVD for better performance
      echo "hw.gpu.enabled=yes" >> ~/.android/avd/IonicAVD.avd/config.ini
      echo "hw.gpu.mode=host" >> ~/.android/avd/IonicAVD.avd/config.ini
    fi

    # Install Chrome for web/PWA development
    if [[ "${data.coder_parameter.target_platform.value}" == "web" || "${data.coder_parameter.target_platform.value}" == "pwa" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      echo "🌐 Setting up Web development environment..."
      wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
      echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
      sudo apt-get update
      sudo apt-get install -y google-chrome-stable
    fi

    # Install Docker for containerized builds
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

    # Install VS Code extensions based on framework choice
    echo "🔌 Installing VS Code extensions..."
    code --install-extension Ionic.ionic
    code --install-extension ms-vscode.vscode-typescript-next
    code --install-extension ms-vscode.vscode-json
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension esbenp.prettier-vscode
    code --install-extension dbaeumer.vscode-eslint
    code --install-extension formulahendry.auto-rename-tag
    code --install-extension GitHub.copilot
    code --install-extension ms-vscode.hexeditor

    # Framework-specific extensions
    case "${data.coder_parameter.framework.value}" in
      "angular")
        code --install-extension Angular.ng-template
        code --install-extension johnpapa.Angular2
        code --install-extension cyrilletuzi.angular-schematics
        ;;
      "react")
        code --install-extension ms-vscode.vscode-react-native
        code --install-extension dsznajder.es7-react-js-snippets
        ;;
      "vue")
        code --install-extension Vue.volar
        code --install-extension Vue.vscode-typescript-vue-plugin
        ;;
    esac

    # Install additional useful tools
    sudo apt-get install -y htop tree jq imagemagick ffmpeg

    # Create Ionic project
    cd /home/coder
    echo "⚡ Creating Ionic project..."

    # Create Ionic app with specified framework
    ionic start ionic-app ${data.coder_parameter.framework.value == "angular" ? "tabs" : data.coder_parameter.framework.value == "react" ? "tabs" : "tabs"} --type=${data.coder_parameter.framework.value} --capacitor --package-id=com.example.ionic --no-git --no-link

    cd ionic-app

    # Install Capacitor platforms based on target
    if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      echo "📱 Adding Android platform..."
      ionic capacitor add android
    fi

    if [[ "${data.coder_parameter.target_platform.value}" == "ios" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      echo "🍎 Adding iOS platform..."
      ionic capacitor add ios
    fi

    # Add commonly used Ionic packages
    npm install --save @ionic/storage-angular @capacitor/storage @capacitor/camera
    npm install --save @capacitor/geolocation @capacitor/device @capacitor/network
    npm install --save @capacitor/haptics @capacitor/status-bar @capacitor/keyboard
    npm install --save @capacitor/app @capacitor/splash-screen

    # Add development dependencies
    npm install --save-dev @ionic/lab @capacitor/cli
    npm install --save-dev cypress @cypress/angular @cypress/react @cypress/vue

    # Create project structure
    mkdir -p src/app/{components,pages,services,guards,interceptors}
    mkdir -p src/app/shared/{models,interfaces,utils,constants}
    mkdir -p src/assets/{images,icons,fonts}
    mkdir -p src/environments

    # Create sample service
    case "${data.coder_parameter.framework.value}" in
      "angular")
        cat > src/app/services/data.service.ts << 'EOF'
import { Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError, BehaviorSubject } from 'rxjs';
import { catchError, retry, tap } from 'rxjs/operators';
import { Storage } from '@ionic/storage-angular';

export interface User {
  id: string;
  name: string;
  email: string;
  avatar?: string;
}

@Injectable({
  providedIn: 'root'
})
export class DataService {
  private apiUrl = 'http://localhost:8000/api';
  private userSubject = new BehaviorSubject<User | null>(null);
  public user$ = this.userSubject.asObservable();

  constructor(
    private http: HttpClient,
    private storage: Storage
  ) {
    this.init();
  }

  async init() {
    await this.storage.create();
    const user = await this.storage.get('user');
    if (user) {
      this.userSubject.next(user);
    }
  }

  getUsers(): Observable<User[]> {
    return this.http.get<User[]>(`${this.apiUrl}/users`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  getUser(id: string): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/users/${id}`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  async saveUser(user: User): Promise<void> {
    await this.storage.set('user', user);
    this.userSubject.next(user);
  }

  async removeUser(): Promise<void> {
    await this.storage.remove('user');
    this.userSubject.next(null);
  }

  private handleError(error: HttpErrorResponse): Observable<never> {
    let errorMessage = 'An unknown error occurred';

    if (error.error instanceof ErrorEvent) {
      errorMessage = `Error: ${error.error.message}`;
    } else {
      errorMessage = `Error Code: ${error.status}\nMessage: ${error.message}`;
    }

    console.error('DataService Error:', errorMessage);
    return throwError(() => errorMessage);
  }
}
EOF
        ;;
      "react")
        mkdir -p src/hooks src/context
        cat > src/hooks/useApi.ts << 'EOF'
import { useState, useEffect, useCallback } from 'react';
import { Storage } from '@ionic/storage';

interface UseApiResult<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
}

export function useApi<T>(url: string, dependencies: any[] = []): UseApiResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const result = await response.json();
      setData(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An unknown error occurred');
    } finally {
      setLoading(false);
    }
  }, [url]);

  useEffect(() => {
    fetchData();
  }, [fetchData, ...dependencies]);

  return { data, loading, error, refetch: fetchData };
}

export async function initStorage() {
  const storage = new Storage();
  await storage.create();
  return storage;
}
EOF
        ;;
      "vue")
        mkdir -p src/composables src/stores
        cat > src/composables/useApi.ts << 'EOF'
import { ref, reactive, computed } from 'vue';
import { Storage } from '@ionic/storage';

interface ApiState<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
}

export function useApi<T>(url: string) {
  const state = reactive<ApiState<T>>({
    data: null,
    loading: false,
    error: null
  });

  const fetch = async () => {
    state.loading = true;
    state.error = null;

    try {
      const response = await window.fetch(url);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      state.data = await response.json();
    } catch (err) {
      state.error = err instanceof Error ? err.message : 'An unknown error occurred';
    } finally {
      state.loading = false;
    }
  };

  return {
    ...state,
    fetch,
    isLoading: computed(() => state.loading),
    hasError: computed(() => !!state.error)
  };
}

export async function initStorage() {
  const storage = new Storage();
  await storage.create();
  return storage;
}
EOF
        ;;
    esac

    # Create sample component based on framework
    case "${data.coder_parameter.framework.value}" in
      "angular")
        # Create welcome component
        ionic generate component components/Welcome
        cat > src/app/components/welcome/welcome.component.html << 'EOF'
<ion-card>
  <ion-card-header>
    <ion-card-title>
      <ion-icon name="flash" color="primary"></ion-icon>
      Welcome to Ionic!
    </ion-card-title>
    <ion-card-subtitle>
      Your Ionic ${data.coder_parameter.ionic_version.value} development environment is ready
    </ion-card-subtitle>
  </ion-card-header>

  <ion-card-content>
    <ion-list>
      <ion-item>
        <ion-icon name="checkmark-circle" color="success" slot="start"></ion-icon>
        <ion-label>
          <h3>Framework: ${data.coder_parameter.framework.value}</h3>
          <p>Running on Node.js ${data.coder_parameter.node_version.value}</p>
        </ion-label>
      </ion-item>

      <ion-item>
        <ion-icon name="phone-portrait" color="primary" slot="start"></ion-icon>
        <ion-label>
          <h3>Target Platforms</h3>
          <p>${data.coder_parameter.target_platform.value}</p>
        </ion-label>
      </ion-item>

      <ion-item>
        <ion-icon name="settings" color="medium" slot="start"></ion-icon>
        <ion-label>
          <h3>Development Tools</h3>
          <p>Ionic CLI, Capacitor, VS Code Extensions</p>
        </ion-label>
      </ion-item>
    </ion-list>

    <ion-button expand="block" color="primary" (click)="startBuilding()">
      <ion-icon name="rocket" slot="start"></ion-icon>
      Start Building Your App
    </ion-button>
  </ion-card-content>
</ion-card>
EOF

        cat > src/app/components/welcome/welcome.component.ts << 'EOF'
import { Component } from '@angular/core';
import { AlertController } from '@ionic/angular';

@Component({
  selector: 'app-welcome',
  templateUrl: './welcome.component.html',
  styleUrls: ['./welcome.component.scss'],
})
export class WelcomeComponent {

  constructor(private alertController: AlertController) { }

  async startBuilding() {
    const alert = await this.alertController.create({
      header: 'Ready to Build!',
      message: 'Your Ionic development environment is fully configured. Happy coding!',
      buttons: ['Awesome!']
    });

    await alert.present();
  }
}
EOF
        ;;
    esac

    # Create Capacitor configuration
    cat > capacitor.config.ts << 'EOF'
import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.example.ionic',
  appName: 'Ionic App',
  webDir: 'dist',
  server: {
    androidScheme: 'https'
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 3000,
      launchAutoHide: true,
      backgroundColor: "#ffffffff",
      androidSplashResourceName: "splash",
      androidScaleType: "CENTER_CROP",
      showSpinner: true,
      androidSpinnerStyle: "large",
      iosSpinnerStyle: "small",
      spinnerColor: "#999999"
    },
    StatusBar: {
      style: 'default'
    },
    Keyboard: {
      resize: 'body'
    }
  }
};

export default config;
EOF

    # Create environment files
    cat > src/environments/environment.ts << 'EOF'
export const environment = {
  production: false,
  apiUrl: 'http://localhost:8000/api',
  appName: 'Ionic Development App',
  version: '1.0.0'
};
EOF

    cat > src/environments/environment.prod.ts << 'EOF'
export const environment = {
  production: true,
  apiUrl: '/api',
  appName: 'Ionic Production App',
  version: '1.0.0'
};
EOF

    # Create Docker configuration
    cat > Dockerfile << 'EOF'
# Build stage
FROM node:${data.coder_parameter.node_version.value}-alpine as build

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .
RUN npm run build

# Runtime stage
FROM nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

    # Create nginx configuration for web deployment
    cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;

        # Ionic routes
        location / {
            try_files $uri $uri/ /index.html;
        }

        # PWA service worker
        location /sw.js {
            add_header Cache-Control "no-cache";
            proxy_cache_bypass $http_pragma;
            proxy_cache_revalidate on;
            expires off;
            access_log off;
        }

        # API proxy (if needed)
        location /api/ {
            proxy_pass http://backend:8000/api/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
        }

        # Security headers
        add_header X-Frame-Options DENY;
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    }
}
EOF

    # Create VS Code workspace settings
    mkdir -p .vscode
    cat > .vscode/settings.json << 'EOF'
{
  "typescript.preferences.importModuleSpecifier": "relative",
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "emmet.includeLanguages": {
    "typescript": "typescriptreact"
  },
  "files.associations": {
    "*.html": "html"
  },
  "search.exclude": {
    "node_modules": true,
    "dist": true,
    "www": true,
    "platforms": true,
    "plugins": true,
    "android/app/build": true,
    "android/.gradle": true,
    "ios/App/build": true,
    ".angular": true
  },
  "ionic.advanced": {
    "showAllConfigs": true
  }
}
EOF

    cat > .vscode/launch.json << 'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Ionic: Serve",
      "type": "node",
      "request": "launch",
      "program": "${workspaceFolder}/node_modules/@ionic/cli/bin/ionic",
      "args": ["serve"],
      "env": {
        "NODE_ENV": "development"
      },
      "console": "integratedTerminal"
    },
    {
      "name": "Ionic: Android Debug",
      "type": "node",
      "request": "launch",
      "program": "${workspaceFolder}/node_modules/@ionic/cli/bin/ionic",
      "args": ["capacitor", "run", "android", "--livereload"],
      "env": {
        "NODE_ENV": "development"
      },
      "console": "integratedTerminal"
    },
    {
      "name": "Ionic: iOS Debug",
      "type": "node",
      "request": "launch",
      "program": "${workspaceFolder}/node_modules/@ionic/cli/bin/ionic",
      "args": ["capacitor", "run", "ios", "--livereload"],
      "env": {
        "NODE_ENV": "development"
      },
      "console": "integratedTerminal"
    }
  ]
}
EOF

    # Create development scripts
    mkdir -p scripts
    cat > scripts/dev-server.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Ionic development server..."

# Start Android emulator if needed
if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
  if command -v emulator &> /dev/null; then
    echo "📱 Starting Android emulator..."
    emulator -avd IonicAVD -no-audio -no-window &

    # Wait for emulator to boot
    adb wait-for-device
    echo "📱 Android emulator ready"
  fi
fi

# Start Ionic dev server
case "${data.coder_parameter.target_platform.value}" in
  "web"|"pwa")
    ionic serve --host=0.0.0.0 --port=8100
    ;;
  "android")
    if command -v adb &> /dev/null; then
      ionic capacitor run android --livereload --external
    else
      echo "Android tools not available. Starting web server instead."
      ionic serve --host=0.0.0.0 --port=8100
    fi
    ;;
  "ios")
    echo "iOS development requires macOS. Starting web server instead."
    ionic serve --host=0.0.0.0 --port=8100
    ;;
  "all")
    echo "Starting development server for all platforms..."
    ionic serve --host=0.0.0.0 --port=8100 --lab
    ;;
esac
EOF

    chmod +x scripts/dev-server.sh

    cat > scripts/build-app.sh << 'EOF'
#!/bin/bash

echo "🏗️ Building Ionic app for ${data.coder_parameter.target_platform.value}..."

case "${data.coder_parameter.target_platform.value}" in
  "web")
    ionic build
    echo "🌐 Web app built: dist/"
    ;;
  "pwa")
    ionic build --service-worker
    echo "📱 PWA built: dist/"
    ;;
  "android")
    ionic build
    ionic capacitor sync android
    ionic capacitor build android
    echo "📱 Android APK built"
    ;;
  "ios")
    ionic build
    ionic capacitor sync ios
    echo "🍎 iOS project prepared (requires macOS to build)"
    ;;
  "all")
    ionic build --service-worker
    if [[ -d "android" ]]; then
      ionic capacitor sync android
      ionic capacitor build android
    fi
    if [[ -d "ios" ]]; then
      ionic capacitor sync ios
    fi
    echo "📦 All platforms built successfully!"
    ;;
esac
EOF

    chmod +x scripts/build-app.sh

    # Update package.json with additional scripts
    npm pkg set scripts.serve="ionic serve --host=0.0.0.0 --port=8100"
    npm pkg set scripts.serve:lab="ionic serve --host=0.0.0.0 --port=8100 --lab"
    npm pkg set scripts.build="ionic build"
    npm pkg set scripts.build:prod="ionic build --prod"
    npm pkg set scripts.test="npm run test:unit && npm run test:e2e"
    npm pkg set scripts.test:unit="jest"
    npm pkg set scripts.test:e2e="cypress run"
    npm pkg set scripts.lint="eslint . --ext .ts,.tsx,.js,.jsx"
    npm pkg set scripts.dev="./scripts/dev-server.sh"
    npm pkg set scripts.android="ionic capacitor run android --livereload"
    npm pkg set scripts.ios="ionic capacitor run ios --livereload"

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/ionic-app
    sudo chown -R coder:coder /home/coder/Android 2>/dev/null || true

    # Install dependencies and sync platforms
    cd /home/coder/ionic-app
    npm install

    # Sync Capacitor platforms
    if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      ionic capacitor sync android || true
    fi

    if [[ "${data.coder_parameter.target_platform.value}" == "ios" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      ionic capacitor sync ios || true
    fi

    echo "✅ Ionic development environment ready!"
    echo "⚡ Ionic version: ${data.coder_parameter.ionic_version.value}"
    echo "🅰️ Framework: ${data.coder_parameter.framework.value}"
    echo "📦 Node.js version: ${data.coder_parameter.node_version.value}"
    echo "🎯 Target platforms: ${data.coder_parameter.target_platform.value}"
    echo "💻 CPU: ${data.coder_parameter.cpu.value} cores"
    echo "🧠 Memory: ${data.coder_parameter.memory.value}GB"
    echo ""
    echo "🚀 To start development server: npm run serve"
    echo "📱 To test on device: npm run android (or ios)"
    echo "🏗️ To build for production: npm run build:prod"

  EOT

}

# Metadata
resource "coder_metadata" "node_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "node_version"
    value = data.coder_parameter.node_version.value
  }
}

resource "coder_metadata" "ionic_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "ionic_version"
    value = data.coder_parameter.ionic_version.value
  }
}

resource "coder_metadata" "framework" {
  resource_id = coder_agent.main.id
  item {
    key   = "framework"
    value = data.coder_parameter.framework.value
  }
}

resource "coder_metadata" "target_platform" {
  resource_id = coder_agent.main.id
  item {
    key   = "target_platform"
    value = data.coder_parameter.target_platform.value
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
resource "coder_app" "ionic_serve" {
  agent_id     = coder_agent.main.id
  slug         = "ionic-serve"
  display_name = "Ionic Dev Server"
  url          = "http://localhost:8100"
  icon         = "/icon/ionic.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8100"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "ionic_lab" {
  agent_id     = coder_agent.main.id
  slug         = "ionic-lab"
  display_name = "Ionic Lab"
  url          = "http://localhost:8200"
  icon         = "/icon/ionic.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8200"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/ionic-app"
  share        = "owner"
}

resource "coder_app" "android_emulator" {
  count        = contains(["android", "all"], data.coder_parameter.target_platform.value) ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "android-emulator"
  display_name = "Android Emulator"
  icon         = "/icon/android.svg"
  command      = "emulator -avd IonicAVD"
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
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
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
            allow_privilege_escalation = true
            capabilities {
              add = ["SYS_ADMIN"]
            }
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          env {
            name  = "ANDROID_HOME"
            value = "/home/coder/Android"
          }

          env {
            name  = "ANDROID_SDK_ROOT"
            value = "/home/coder/Android"
          }

          env {
            name  = "JAVA_HOME"
            value = "/usr/lib/jvm/java-17-openjdk-amd64"
          }

          env {
            name  = "CHROME_EXECUTABLE"
            value = "/usr/bin/google-chrome-stable"
          }

          env {
            name  = "IONIC_CLI_VERSION"
            value = data.coder_parameter.ionic_version.value
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

          # Expose Ionic development ports
          port {
            container_port = 8100
            name          = "ionic-serve"
            protocol      = "TCP"
          }

          port {
            container_port = 8200
            name          = "ionic-lab"
            protocol      = "TCP"
          }

          port {
            container_port = 35729
            name          = "livereload"
            protocol      = "TCP"
          }

          port {
            container_port = 53703
            name          = "ionic-dev"
            protocol      = "TCP"
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

# Service for Ionic development ports
resource "kubernetes_service" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
  }

  spec {
    selector = {
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    }

    port {
      name        = "ionic-serve"
      port        = 8100
      target_port = 8100
      protocol    = "TCP"
    }

    port {
      name        = "ionic-lab"
      port        = 8200
      target_port = 8200
      protocol    = "TCP"
    }

    port {
      name        = "livereload"
      port        = 35729
      target_port = 35729
      protocol    = "TCP"
    }

    port {
      name        = "ionic-dev"
      port        = 53703
      target_port = 53703
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
