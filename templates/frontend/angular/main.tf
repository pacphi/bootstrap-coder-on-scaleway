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

data "coder_parameter" "angular_version" {
  name         = "angular_version"
  display_name = "Angular Version"
  description  = "Angular version to use"
  default      = "17"
  icon         = "/icon/angular.svg"
  mutable      = false
  option {
    name  = "Angular 16"
    value = "16"
  }
  option {
    name  = "Angular 17"
    value = "17"
  }
  option {
    name  = "Angular 18"
    value = "18"
  }
}

data "coder_parameter" "ui_framework" {
  name         = "ui_framework"
  display_name = "UI Framework"
  description  = "Choose UI framework"
  default      = "material"
  icon         = "/icon/design.svg"
  mutable      = false
  option {
    name  = "Angular Material"
    value = "material"
  }
  option {
    name  = "PrimeNG"
    value = "primeng"
  }
  option {
    name  = "Ng-Bootstrap"
    value = "bootstrap"
  }
  option {
    name  = "Tailwind CSS"
    value = "tailwind"
  }
}

data "coder_parameter" "state_management" {
  name         = "state_management"
  display_name = "State Management"
  description  = "Choose state management solution"
  default      = "services"
  icon         = "/icon/state.svg"
  mutable      = false
  option {
    name  = "Angular Services"
    value = "services"
  }
  option {
    name  = "NgRx"
    value = "ngrx"
  }
  option {
    name  = "Akita"
    value = "akita"
  }
}

data "coder_parameter" "enable_pwa" {
  name         = "enable_pwa"
  display_name = "Enable PWA Features"
  description  = "Enable Progressive Web App features"
  default      = "true"
  type         = "bool"
  icon         = "/icon/pwa.svg"
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

    echo "🅰️ Setting up Angular development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential

    # Install Node.js ${data.coder_parameter.node_version.value}
    echo "📦 Installing Node.js ${data.coder_parameter.node_version.value}..."
    curl -fsSL https://deb.nodesource.com/setup_${data.coder_parameter.node_version.value}.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # Install global packages
    npm install -g @angular/cli@${data.coder_parameter.angular_version.value} yarn pnpm

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

    # Install VS Code extensions for Angular
    code --install-extension Angular.ng-template
    code --install-extension ms-vscode.vscode-typescript-next
    code --install-extension johnpapa.Angular2
    code --install-extension cyrilletuzi.angular-schematics
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension esbenp.prettier-vscode
    code --install-extension dbaeumer.vscode-eslint
    code --install-extension ms-vscode.vscode-json
    code --install-extension formulahendry.auto-rename-tag
    code --install-extension GitHub.copilot
    code --install-extension ms-playwright.playwright
    code --install-extension Angular.ng-template

    # Create Angular project
    echo "🅰️ Creating Angular ${data.coder_parameter.angular_version.value} project..."
    cd /home/coder

    # Create new Angular project with routing and styling
    ng new angular-app --routing --style=scss --package-manager=npm --skip-git=true
    cd angular-app

    # Install UI framework
    case "${data.coder_parameter.ui_framework.value}" in
      "material")
        echo "🎨 Installing Angular Material..."
        ng add @angular/material --theme=indigo-pink --typography=true --animations=true --interactive=false
        npm install @angular/flex-layout @angular/cdk
        ;;
      "primeng")
        echo "🎨 Installing PrimeNG..."
        npm install primeng primeicons primeflex
        npm install @angular/animations
        ;;
      "bootstrap")
        echo "🎨 Installing Ng-Bootstrap..."
        ng add @ng-bootstrap/ng-bootstrap --interactive=false
        npm install bootstrap
        ;;
      "tailwind")
        echo "🎨 Installing Tailwind CSS..."
        npm install -D tailwindcss postcss autoprefixer
        npx tailwindcss init -p

        # Update tailwind.config.js
        cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{html,ts}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOF

        # Update styles.scss
        cat > src/styles.scss << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

/* Custom styles */
@layer components {
  .btn-primary {
    @apply bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded;
  }

  .card {
    @apply bg-white shadow-md rounded-lg p-6;
  }

  .container-custom {
    @apply max-w-7xl mx-auto px-4 sm:px-6 lg:px-8;
  }
}
EOF
        ;;
    esac

    # Install state management
    case "${data.coder_parameter.state_management.value}" in
      "ngrx")
        echo "🏪 Installing NgRx..."
        ng add @ngrx/store@latest --interactive=false
        ng add @ngrx/effects@latest --interactive=false
        ng add @ngrx/store-devtools@latest --interactive=false
        ng add @ngrx/router-store@latest --interactive=false
        ;;
      "akita")
        echo "🏪 Installing Akita..."
        npm install @datorama/akita
        npm install -D @datorama/akita-cli
        ;;
    esac

    # Install PWA if enabled
    if [[ "${data.coder_parameter.enable_pwa.value}" == "true" ]]; then
      echo "📱 Adding PWA support..."
      ng add @angular/pwa --interactive=false
    fi

    # Install additional packages
    npm install \
      @angular/common@latest \
      @angular/forms@latest \
      rxjs \
      zone.js \
      tslib

    # Install development packages
    npm install -D \
      @angular-devkit/build-angular \
      @types/jasmine \
      @types/node \
      eslint \
      prettier \
      karma \
      karma-chrome-headless \
      karma-coverage \
      jasmine-core \
      @angular-eslint/eslint-plugin \
      @angular-eslint/eslint-plugin-template \
      @angular-eslint/template-parser \
      @typescript-eslint/eslint-plugin \
      @typescript-eslint/parser \
      cypress \
      @cypress/schematic

    # Add Cypress for e2e testing
    ng add @cypress/schematic --interactive=false

    # Configure ESLint
    ng add @angular-eslint/schematics --interactive=false

    # Create sample components and services
    echo "🏗️ Creating sample components and services..."

    # Generate core components
    ng generate component shared/header --module=app
    ng generate component shared/footer --module=app
    ng generate component shared/sidebar --module=app
    ng generate component pages/home --module=app
    ng generate component pages/about --module=app
    ng generate component pages/contact --module=app

    # Generate services
    ng generate service core/services/data
    ng generate service core/services/auth
    ng generate service shared/services/theme

    # Generate guards and interceptors
    ng generate guard core/guards/auth
    ng generate interceptor core/interceptors/http-error

    # Create core and shared modules
    ng generate module core --module=app
    ng generate module shared --module=app

    # Create feature modules
    ng generate module features/dashboard --routing
    ng generate component features/dashboard/dashboard --module=features/dashboard
    ng generate component features/dashboard/components/stats-card --module=features/dashboard

    # Update app.component.html
    cat > src/app/app.component.html << 'EOF'
<div class="app-container">
  <app-header></app-header>

  <div class="main-content">
    <app-sidebar *ngIf="showSidebar"></app-sidebar>

    <main class="content" [class.with-sidebar]="showSidebar">
      <router-outlet></router-outlet>
    </main>
  </div>

  <app-footer></app-footer>
</div>
EOF

    # Update app.component.scss
    cat > src/app/app.component.scss << 'EOF'
.app-container {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.main-content {
  flex: 1;
  display: flex;
}

.content {
  flex: 1;
  padding: 1rem;
  transition: margin-left 0.3s ease;

  &.with-sidebar {
    margin-left: 250px;
  }
}

@media (max-width: 768px) {
  .content.with-sidebar {
    margin-left: 0;
  }
}
EOF

    # Update app.component.ts
    cat > src/app/app.component.ts << 'EOF'
import { Component } from '@angular/core';
import { ThemeService } from './shared/services/theme.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss']
})
export class AppComponent {
  title = 'angular-app';
  showSidebar = true;

  constructor(private themeService: ThemeService) {}

  toggleSidebar() {
    this.showSidebar = !this.showSidebar;
  }
}
EOF

    # Create header component
    cat > src/app/shared/header/header.component.html << 'EOF'
<header class="header">
  <div class="container">
    <div class="nav-brand">
      <h1>Angular App</h1>
    </div>

    <nav class="nav-menu">
      <a routerLink="/" routerLinkActive="active" [routerLinkActiveOptions]="{exact: true}">Home</a>
      <a routerLink="/about" routerLinkActive="active">About</a>
      <a routerLink="/contact" routerLinkActive="active">Contact</a>
      <a routerLink="/dashboard" routerLinkActive="active">Dashboard</a>
    </nav>

    <div class="nav-actions">
      <button class="theme-toggle" (click)="toggleTheme()">
        {{ isDarkMode ? '☀️' : '🌙' }}
      </button>
    </div>
  </div>
</header>
EOF

    cat > src/app/shared/header/header.component.scss << 'EOF'
.header {
  background: #1976d2;
  color: white;
  padding: 1rem 0;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1rem;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.nav-brand h1 {
  margin: 0;
  font-size: 1.5rem;
}

.nav-menu {
  display: flex;
  gap: 2rem;

  a {
    color: white;
    text-decoration: none;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    transition: background-color 0.2s;

    &:hover, &.active {
      background-color: rgba(255, 255, 255, 0.1);
    }
  }
}

.nav-actions {
  .theme-toggle {
    background: none;
    border: 1px solid rgba(255, 255, 255, 0.3);
    color: white;
    padding: 0.5rem 1rem;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s;

    &:hover {
      background-color: rgba(255, 255, 255, 0.1);
    }
  }
}

@media (max-width: 768px) {
  .container {
    flex-direction: column;
    gap: 1rem;
  }

  .nav-menu {
    gap: 1rem;
  }
}
EOF

    cat > src/app/shared/header/header.component.ts << 'EOF'
import { Component } from '@angular/core';
import { ThemeService } from '../services/theme.service';

@Component({
  selector: 'app-header',
  templateUrl: './header.component.html',
  styleUrls: ['./header.component.scss']
})
export class HeaderComponent {
  isDarkMode = false;

  constructor(private themeService: ThemeService) {
    this.themeService.isDarkMode$.subscribe(isDark => {
      this.isDarkMode = isDark;
    });
  }

  toggleTheme() {
    this.themeService.toggleTheme();
  }
}
EOF

    # Create home component
    cat > src/app/pages/home/home.component.html << 'EOF'
<div class="hero-section">
  <div class="container">
    <h1>Welcome to Angular ${data.coder_parameter.angular_version.value}</h1>
    <p class="lead">
      A modern, scalable web application built with Angular and ${data.coder_parameter.ui_framework.value}.
    </p>
    <div class="cta-buttons">
      <button class="btn btn-primary" routerLink="/dashboard">Get Started</button>
      <button class="btn btn-outline" routerLink="/about">Learn More</button>
    </div>
  </div>
</div>

<div class="features-section">
  <div class="container">
    <h2>Features</h2>
    <div class="features-grid">
      <div class="feature-card">
        <div class="icon">⚡</div>
        <h3>Fast & Modern</h3>
        <p>Built with Angular ${data.coder_parameter.angular_version.value} and the latest web standards.</p>
      </div>

      <div class="feature-card">
        <div class="icon">🎨</div>
        <h3>${data.coder_parameter.ui_framework.value == "material" ? "Material Design" : "Beautiful UI"}</h3>
        <p>Styled with ${data.coder_parameter.ui_framework.value} for a consistent user experience.</p>
      </div>

      <div class="feature-card">
        <div class="icon">🔧</div>
        <h3>Developer Ready</h3>
        <p>TypeScript, testing, and modern development tools included.</p>
      </div>

      <div class="feature-card">
        <div class="icon">📱</div>
        <h3>${data.coder_parameter.enable_pwa.value ? "PWA Ready" : "Responsive"}</h3>
        <p>${data.coder_parameter.enable_pwa.value ? "Progressive Web App features enabled" : "Responsive design for all devices"}.</p>
      </div>
    </div>
  </div>
</div>
EOF

    # Create theme service
    cat > src/app/shared/services/theme.service.ts << 'EOF'
import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  private isDarkModeSubject = new BehaviorSubject<boolean>(false);
  public isDarkMode$ = this.isDarkModeSubject.asObservable();

  constructor() {
    // Check for saved theme preference or default to light mode
    const savedTheme = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

    const isDarkMode = savedTheme === 'dark' || (!savedTheme && prefersDark);
    this.setTheme(isDarkMode);
  }

  toggleTheme(): void {
    const currentTheme = this.isDarkModeSubject.value;
    this.setTheme(!currentTheme);
  }

  private setTheme(isDarkMode: boolean): void {
    this.isDarkModeSubject.next(isDarkMode);

    if (isDarkMode) {
      document.body.classList.add('dark-theme');
      localStorage.setItem('theme', 'dark');
    } else {
      document.body.classList.remove('dark-theme');
      localStorage.setItem('theme', 'light');
    }
  }
}
EOF

    # Create data service
    cat > src/app/core/services/data.service.ts << 'EOF'
import { Injectable } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError } from 'rxjs';
import { catchError, retry } from 'rxjs/operators';

export interface User {
  id: number;
  name: string;
  email: string;
  avatar?: string;
}

export interface ApiResponse<T> {
  data: T;
  message?: string;
  status: 'success' | 'error';
}

@Injectable({
  providedIn: 'root'
})
export class DataService {
  private apiUrl = 'http://localhost:3000/api';

  constructor(private http: HttpClient) {}

  getUsers(): Observable<ApiResponse<User[]>> {
    return this.http.get<ApiResponse<User[]>>(`$${this.apiUrl}/users`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  getUser(id: number): Observable<ApiResponse<User>> {
    return this.http.get<ApiResponse<User>>(`$${this.apiUrl}/users/$${id}`)
      .pipe(
        retry(2),
        catchError(this.handleError)
      );
  }

  createUser(user: Omit<User, 'id'>): Observable<ApiResponse<User>> {
    return this.http.post<ApiResponse<User>>(`$${this.apiUrl}/users`, user)
      .pipe(
        catchError(this.handleError)
      );
  }

  updateUser(id: number, user: Partial<User>): Observable<ApiResponse<User>> {
    return this.http.put<ApiResponse<User>>(`$${this.apiUrl}/users/$${id}`, user)
      .pipe(
        catchError(this.handleError)
      );
  }

  deleteUser(id: number): Observable<ApiResponse<void>> {
    return this.http.delete<ApiResponse<void>>(`$${this.apiUrl}/users/$${id}`)
      .pipe(
        catchError(this.handleError)
      );
  }

  private handleError(error: HttpErrorResponse): Observable<never> {
    let errorMessage = 'An unknown error occurred';

    if (error.error instanceof ErrorEvent) {
      // Client-side error
      errorMessage = `Error: $${error.error.message}`;
    } else {
      // Server-side error
      errorMessage = `Error Code: $${error.status}\nMessage: $${error.message}`;
    }

    console.error('DataService Error:', errorMessage);
    return throwError(() => errorMessage);
  }
}
EOF

    # Update app-routing.module.ts
    cat > src/app/app-routing.module.ts << 'EOF'
import { NgModule } from '@angular/core';
import { RouterModule, Routes } from '@angular/router';
import { HomeComponent } from './pages/home/home.component';
import { AboutComponent } from './pages/about/about.component';
import { ContactComponent } from './pages/contact/contact.component';

const routes: Routes = [
  { path: '', component: HomeComponent },
  { path: 'about', component: AboutComponent },
  { path: 'contact', component: ContactComponent },
  {
    path: 'dashboard',
    loadChildren: () => import('./features/dashboard/dashboard.module').then(m => m.DashboardModule)
  },
  { path: '**', redirectTo: '' }
];

@NgModule({
  imports: [RouterModule.forRoot(routes)],
  exports: [RouterModule]
})
export class AppRoutingModule { }
EOF

    # Create global styles
    cat > src/styles.scss << 'EOF'
/* Import framework styles */
@import '~@angular/material/prebuilt-themes/indigo-pink.css';

/* Base styles */
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: 'Roboto', sans-serif;
  line-height: 1.6;
  color: #333;
  transition: background-color 0.3s ease, color 0.3s ease;
}

/* Dark theme */
body.dark-theme {
  background-color: #121212;
  color: #ffffff;
}

/* Common components */
.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1rem;
}

.btn {
  display: inline-block;
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 4px;
  font-size: 1rem;
  font-weight: 500;
  text-decoration: none;
  text-align: center;
  cursor: pointer;
  transition: all 0.2s ease;

  &.btn-primary {
    background-color: #1976d2;
    color: white;

    &:hover {
      background-color: #1565c0;
    }
  }

  &.btn-outline {
    background-color: transparent;
    color: #1976d2;
    border: 1px solid #1976d2;

    &:hover {
      background-color: #1976d2;
      color: white;
    }
  }
}

.hero-section {
  background: linear-gradient(135deg, #1976d2, #42a5f5);
  color: white;
  padding: 4rem 0;
  text-align: center;

  h1 {
    font-size: 3rem;
    margin-bottom: 1rem;
  }

  .lead {
    font-size: 1.2rem;
    margin-bottom: 2rem;
    opacity: 0.9;
  }

  .cta-buttons {
    display: flex;
    gap: 1rem;
    justify-content: center;
    flex-wrap: wrap;
  }
}

.features-section {
  padding: 4rem 0;

  h2 {
    text-align: center;
    margin-bottom: 3rem;
    font-size: 2.5rem;
  }
}

.features-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 2rem;
  margin-top: 2rem;
}

.feature-card {
  text-align: center;
  padding: 2rem;
  border-radius: 8px;
  box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  background: white;
  transition: transform 0.2s ease;

  &:hover {
    transform: translateY(-5px);
  }

  .icon {
    font-size: 3rem;
    margin-bottom: 1rem;
  }

  h3 {
    margin-bottom: 1rem;
    color: #1976d2;
  }
}

/* Dark theme feature cards */
body.dark-theme .feature-card {
  background: #1e1e1e;
  color: #ffffff;
}

/* Responsive design */
@media (max-width: 768px) {
  .hero-section h1 {
    font-size: 2rem;
  }

  .cta-buttons {
    flex-direction: column;
    align-items: center;
  }

  .features-grid {
    grid-template-columns: 1fr;
  }
}
EOF

    # Create environment files
    cat > src/environments/environment.ts << 'EOF'
export const environment = {
  production: false,
  apiUrl: 'http://localhost:3000/api',
  appName: 'Angular Development App'
};
EOF

    cat > src/environments/environment.prod.ts << 'EOF'
export const environment = {
  production: true,
  apiUrl: '/api',
  appName: 'Angular Production App'
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
RUN npm run build --prod

# Runtime stage
FROM nginx:alpine

COPY --from=build /app/dist/angular-app /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

    # Create nginx configuration
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

        # Angular routes
        location / {
            try_files $uri $uri/ /index.html;
        }

        # API proxy (if needed)
        location /api/ {
            proxy_pass http://backend:3000/api/;
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
    }
}
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  angular-app:
    build: .
    ports:
      - "4200:80"
    environment:
      - NODE_ENV=production
    depends_on:
      - backend
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro

  backend:
    image: node:${data.coder_parameter.node_version.value}-alpine
    working_dir: /app
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=development
      - PORT=3000
    command: sh -c "npm init -y && npm install express cors && node -e 'const express = require(\"express\"); const cors = require(\"cors\"); const app = express(); app.use(cors()); app.use(express.json()); app.get(\"/api/health\", (req, res) => res.json({status: \"ok\"})); app.listen(3000, () => console.log(\"Backend running on port 3000\"));'"

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - angular-app
EOF

    # Configure package.json scripts
    npm pkg set scripts.start="ng serve --host 0.0.0.0 --port 4200"
    npm pkg set scripts.build="ng build"
    npm pkg set scripts.build:prod="ng build --configuration production"
    npm pkg set scripts.test="ng test --watch=false --browsers=ChromeHeadless"
    npm pkg set scripts.test:watch="ng test"
    npm pkg set scripts.e2e="cypress run"
    npm pkg set scripts.e2e:open="cypress open"
    npm pkg set scripts.lint="ng lint"
    npm pkg set scripts.lint:fix="ng lint --fix"
    npm pkg set scripts.format="prettier --write \"src/**/*.{ts,html,scss}\""

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/angular-app

    # Install dependencies and run initial build
    cd /home/coder/angular-app
    npm install

    echo "✅ Angular development environment ready!"
    echo "🅰️ Angular ${data.coder_parameter.angular_version.value} with ${data.coder_parameter.ui_framework.value}"
    echo "🏪 State Management: ${data.coder_parameter.state_management.value}"
    echo "📱 PWA Enabled: ${data.coder_parameter.enable_pwa.value}"
    echo "Run 'ng serve' to start the development server"

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

resource "coder_metadata" "angular_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "angular_version"
    value = data.coder_parameter.angular_version.value
  }
}

resource "coder_metadata" "ui_framework" {
  resource_id = coder_agent.main.id
  item {
    key   = "ui_framework"
    value = data.coder_parameter.ui_framework.value
  }
}

resource "coder_metadata" "state_management" {
  resource_id = coder_agent.main.id
  item {
    key   = "state_management"
    value = data.coder_parameter.state_management.value
  }
}

resource "coder_metadata" "pwa_enabled" {
  resource_id = coder_agent.main.id
  item {
    key   = "pwa_enabled"
    value = data.coder_parameter.enable_pwa.value ? "enabled" : "disabled"
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
resource "coder_app" "angular_dev" {
  agent_id     = coder_agent.main.id
  slug         = "angular-dev"
  display_name = "Angular Dev Server"
  url          = "http://localhost:4200"
  icon         = "/icon/angular.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:4200"
    interval  = 10
    threshold = 20
  }
}

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/angular-app"
  share        = "owner"
}

resource "coder_app" "cypress" {
  agent_id     = coder_agent.main.id
  slug         = "cypress"
  display_name = "Cypress Tests"
  url          = "http://localhost:8080"
  icon         = "/icon/cypress.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8080"
    interval  = 15
    threshold = 30
  }
}

# Kubernetes resources
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "home-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
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
    name      = "coder-workspace-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
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
