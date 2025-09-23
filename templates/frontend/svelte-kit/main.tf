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
  default      = "22"
  icon         = "/icon/nodejs.svg"
  mutable      = false
  option {
    name  = "Node.js 20 LTS"
    value = "20"
  }
  option {
    name  = "Node.js 21"
    value = "21"
  }
  option {
    name  = "Node.js 22 LTS"
    value = "22"
  }
}

data "coder_parameter" "ui_framework" {
  name         = "ui_framework"
  display_name = "UI Framework"
  description  = "Choose UI framework"
  default      = "tailwind"
  icon         = "/icon/design.svg"
  mutable      = false
  option {
    name  = "Tailwind CSS"
    value = "tailwind"
  }
  option {
    name  = "Skeleton UI"
    value = "skeleton"
  }
  option {
    name  = "Carbon Components"
    value = "carbon"
  }
  option {
    name  = "Bulma"
    value = "bulma"
  }
}

data "coder_parameter" "adapter" {
  name         = "adapter"
  display_name = "SvelteKit Adapter"
  description  = "Choose deployment adapter"
  default      = "node"
  icon         = "/icon/svelte.svg"
  mutable      = false
  option {
    name  = "Node.js"
    value = "node"
  }
  option {
    name  = "Static Site"
    value = "static"
  }
  option {
    name  = "Vercel"
    value = "vercel"
  }
  option {
    name  = "Netlify"
    value = "netlify"
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

    echo "🔥 Setting up SvelteKit development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential

    # Install Node.js ${data.coder_parameter.node_version.value}
    echo "📦 Installing Node.js ${data.coder_parameter.node_version.value}..."
    curl -fsSL https://deb.nodesource.com/setup_${data.coder_parameter.node_version.value}.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # Install pnpm and yarn
    npm install -g pnpm yarn @sveltejs/kit @sveltejs/adapter-${data.coder_parameter.adapter.value}

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

    # Install VS Code extensions for Svelte
    code --install-extension svelte.svelte-vscode
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension esbenp.prettier-vscode
    code --install-extension dbaeumer.vscode-eslint
    code --install-extension ms-vscode.vscode-typescript-next
    code --install-extension ms-vscode.vscode-json
    code --install-extension GitHub.copilot
    code --install-extension ms-playwright.playwright

    # Create SvelteKit project
    echo "🔥 Creating SvelteKit project..."
    cd /home/coder

    # Create project with TypeScript
    npm create svelte@latest sveltekit-app
    cd sveltekit-app

    # Answer prompts programmatically by creating the project structure manually
    # Initialize package.json
    cat > package.json << 'EOF'
{
  "name": "sveltekit-app",
  "version": "0.0.1",
  "private": true,
  "scripts": {
    "build": "vite build",
    "dev": "vite dev --host 0.0.0.0 --port 5173",
    "preview": "vite preview --host 0.0.0.0 --port 4173",
    "check": "svelte-kit sync && svelte-check --tsconfig ./tsconfig.json",
    "check:watch": "svelte-kit sync && svelte-check --tsconfig ./tsconfig.json --watch",
    "test": "vitest",
    "test:ui": "vitest --ui",
    "coverage": "vitest run --coverage",
    "lint": "prettier --plugin-search-dir . --check . && eslint .",
    "format": "prettier --plugin-search-dir . --write .",
    "e2e": "playwright test"
  },
  "devDependencies": {
    "@playwright/test": "^1.40.0",
    "@sveltejs/adapter-${data.coder_parameter.adapter.value}": "^3.0.0",
    "@sveltejs/kit": "^2.0.0",
    "@sveltejs/vite-plugin-svelte": "^3.0.0",
    "@types/eslint": "8.56.0",
    "@typescript-eslint/eslint-plugin": "^6.0.0",
    "@typescript-eslint/parser": "^6.0.0",
    "eslint": "^8.56.0",
    "eslint-config-prettier": "^9.1.0",
    "eslint-plugin-svelte": "^2.35.1",
    "prettier": "^3.1.1",
    "prettier-plugin-svelte": "^3.1.2",
    "svelte": "^4.2.7",
    "svelte-check": "^3.6.0",
    "tslib": "^2.4.1",
    "typescript": "^5.0.0",
    "vite": "^5.0.3",
    "vitest": "^1.2.0"
  },
  "type": "module",
  "dependencies": {}
}
EOF

    # Install base dependencies first
    npm install

    # Install UI framework
    case "${data.coder_parameter.ui_framework.value}" in
      "tailwind")
        echo "🎨 Installing Tailwind CSS..."
        npm install -D tailwindcss postcss autoprefixer @tailwindcss/forms @tailwindcss/typography
        npx tailwindcss init -p

        # Update tailwind.config.js
        cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./src/**/*.{html,js,svelte,ts}'],
  theme: {
    extend: {}
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography')
  ]
}
EOF
        ;;
      "skeleton")
        echo "🎨 Installing Skeleton UI..."
        npm install @skeletonlabs/skeleton
        npm install -D @skeletonlabs/tw-plugin tailwindcss postcss autoprefixer
        npx tailwindcss init -p

        # Update tailwind.config.js for Skeleton
        cat > tailwind.config.js << 'EOF'
import { skeleton } from '@skeletonlabs/tw-plugin';

/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: [
    './src/**/*.{html,js,svelte,ts}',
    require('path').join(require.resolve('@skeletonlabs/skeleton'), '../**/*.{html,js,svelte,ts}')
  ],
  theme: {
    extend: {}
  },
  plugins: [
    skeleton({
      themes: { preset: ["skeleton"] }
    })
  ]
}
EOF
        ;;
      "carbon")
        echo "🎨 Installing Carbon Components..."
        npm install carbon-components-svelte
        npm install -D @carbon/themes
        ;;
      "bulma")
        echo "🎨 Installing Bulma..."
        npm install bulma
        npm install -D sass
        ;;
    esac

    # Install additional packages
    npm install \
      @vite-pwa/sveltekit \
      lucide-svelte \
      clsx \
      tailwind-merge

    # Install development and testing packages
    npm install -D \
      @vitest/coverage-v8 \
      @vitest/ui \
      jsdom \
      @testing-library/svelte \
      @testing-library/jest-dom \
      msw

    # Create directory structure
    mkdir -p src/{lib/{components,stores,utils},routes/{api,app},app.html}

    # Create svelte.config.js
    cat > svelte.config.js << 'EOF'
import adapter from '@sveltejs/adapter-${data.coder_parameter.adapter.value}';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),

  kit: {
    adapter: adapter(${data.coder_parameter.adapter.value == "static" ? "{fallback: \\\"index.html\\\"}" : ""})
  }
};

export default config;
EOF

    # Create vite.config.js
    cat > vite.config.js << 'EOF'
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';
import { SvelteKitPWA } from '@vite-pwa/sveltekit';

export default defineConfig({
  plugins: [
    sveltekit()${data.coder_parameter.enable_pwa.value ? ",\n    SvelteKitPWA({\n      strategies: \\\"injectManifest\\\",\n      srcDir: \\\"src\\\",\n      filename: \\\"sw.ts\\\",\n      registerType: \\\"autoUpdate\\\",\n      manifest: {\n        name: \\\"SvelteKit App\\\",\n        short_name: \\\"SvelteKit\\\",\n        description: \\\"A SvelteKit Progressive Web App\\\",\n        theme_color: \\\"#ff3e00\\\",\n        background_color: \\\"#ffffff\\\",\n        display: \\\"standalone\\\",\n        start_url: \\\"/\\\",\n        icons: [\n          {\n            src: \\\"/icon-192.png\\\",\n            sizes: \\\"192x192\\\",\n            type: \\\"image/png\\\"\n          },\n          {\n            src: \\\"/icon-512.png\\\",\n            sizes: \\\"512x512\\\",\n            type: \\\"image/png\\\"\n          }\n        ]\n      }\n    })" : ""}
  ],

  test: {
    include: ['src/**/*.{test,spec}.{js,ts}'],
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.ts']
  },

  server: {
    host: '0.0.0.0',
    port: 5173
  },

  preview: {
    host: '0.0.0.0',
    port: 4173
  }
});
EOF

    # Create app.html
    cat > src/app.html << 'EOF'
<!DOCTYPE html>
<html lang="en" %sveltekit.theme%>
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="%sveltekit.assets%/favicon.png" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    %sveltekit.head%
  </head>
  <body data-sveltekit-preload-data="hover" class="bg-surface-50-900-token">
    <div style="display: contents" class="h-full overflow-hidden">%sveltekit.body%</div>
  </body>
</html>
EOF

    # Create main layout
    mkdir -p src/routes
    cat > src/routes/+layout.svelte << 'EOF'
<script lang="ts">
  import '../app.css';
  import { page } from '$app/stores';
  import { theme } from '$lib/stores/theme';
  import Header from '$lib/components/Header.svelte';
  import Footer from '$lib/components/Footer.svelte';
  import { onMount } from 'svelte';

  onMount(() => {
    // Initialize theme from localStorage or system preference
    const savedTheme = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;

    if (savedTheme) {
      theme.set(savedTheme);
    } else if (prefersDark) {
      theme.set('dark');
    }
  });

  $: {
    if (typeof document !== 'undefined') {
      document.documentElement.classList.toggle('dark', $theme === 'dark');
    }
  }
</script>

<div class="app">
  <Header />

  <main class="main-content">
    <slot />
  </main>

  <Footer />
</div>

<style>
  .app {
    display: flex;
    flex-direction: column;
    min-height: 100vh;
  }

  .main-content {
    flex: 1;
    width: 100%;
    margin: 0 auto;
  }

  :global(html) {
    scroll-behavior: smooth;
  }

  :global(body) {
    margin: 0;
    background-color: var(--color-surface-50);
    transition: background-color 0.2s ease-in-out;
  }

  :global(.dark body) {
    background-color: var(--color-surface-900);
  }
</style>
EOF

    # Create home page
    cat > src/routes/+page.svelte << 'EOF'
<script lang="ts">
  import { page } from '$app/stores';
  import Hero from '$lib/components/Hero.svelte';
  import Features from '$lib/components/Features.svelte';
  import TechStack from '$lib/components/TechStack.svelte';
</script>

<svelte:head>
  <title>SvelteKit App - Modern Web Development</title>
  <meta name="description" content="A modern SvelteKit application with ${data.coder_parameter.ui_framework.value} styling" />
</svelte:head>

<Hero />
<Features />
<TechStack />

<style>
  :global(.page-container) {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 1rem;
  }
</style>
EOF

    # Create components
    mkdir -p src/lib/components

    # Create Header component
    cat > src/lib/components/Header.svelte << 'EOF'
<script lang="ts">
  import { page } from '$app/stores';
  import { theme } from '$lib/stores/theme';
  import ThemeToggle from './ThemeToggle.svelte';

  let mobileMenuOpen = false;

  function toggleMobileMenu() {
    mobileMenuOpen = !mobileMenuOpen;
  }

  const navigation = [
    { name: 'Home', href: '/' },
    { name: 'About', href: '/about' },
    { name: 'Blog', href: '/blog' },
    { name: 'Contact', href: '/contact' }
  ];
</script>

<header class="header">
  <nav class="nav">
    <div class="nav-container">
      <!-- Logo -->
      <div class="nav-brand">
        <a href="/" class="brand-link">
          <span class="brand-text">SvelteKit</span>
        </a>
      </div>

      <!-- Desktop Navigation -->
      <div class="nav-links desktop-only">
        {#each navigation as item}
          <a
            href={item.href}
            class="nav-link"
            class:active={$page.url.pathname === item.href}
          >
            {item.name}
          </a>
        {/each}
      </div>

      <!-- Actions -->
      <div class="nav-actions">
        <ThemeToggle />

        <!-- Mobile menu button -->
        <button
          class="mobile-menu-btn mobile-only"
          on:click={toggleMobileMenu}
          aria-label="Toggle menu"
        >
          <span class="hamburger"></span>
        </button>
      </div>
    </div>

    <!-- Mobile Navigation -->
    {#if mobileMenuOpen}
      <div class="mobile-menu">
        {#each navigation as item}
          <a
            href={item.href}
            class="mobile-link"
            class:active={$page.url.pathname === item.href}
            on:click={() => (mobileMenuOpen = false)}
          >
            {item.name}
          </a>
        {/each}
      </div>
    {/if}
  </nav>
</header>

<style>
  .header {
    background: white;
    border-bottom: 1px solid #e5e7eb;
    position: sticky;
    top: 0;
    z-index: 50;
    transition: all 0.2s ease-in-out;
  }

  :global(.dark) .header {
    background: #1f2937;
    border-bottom-color: #374151;
  }

  .nav {
    width: 100%;
  }

  .nav-container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 1rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    height: 4rem;
  }

  .nav-brand {
    font-size: 1.5rem;
    font-weight: bold;
  }

  .brand-link {
    color: #ff3e00;
    text-decoration: none;
  }

  .nav-links {
    display: flex;
    gap: 2rem;
  }

  .nav-link {
    color: #6b7280;
    text-decoration: none;
    font-weight: 500;
    padding: 0.5rem 1rem;
    border-radius: 0.5rem;
    transition: all 0.2s ease;
  }

  .nav-link:hover,
  .nav-link.active {
    color: #ff3e00;
    background-color: rgba(255, 62, 0, 0.1);
  }

  :global(.dark) .nav-link {
    color: #d1d5db;
  }

  .nav-actions {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .mobile-menu-btn {
    background: none;
    border: none;
    cursor: pointer;
    padding: 0.5rem;
  }

  .hamburger {
    display: block;
    width: 1.5rem;
    height: 2px;
    background: #6b7280;
    position: relative;
  }

  .hamburger::before,
  .hamburger::after {
    content: '';
    position: absolute;
    width: 1.5rem;
    height: 2px;
    background: #6b7280;
    transition: all 0.2s ease;
  }

  .hamburger::before {
    top: -0.5rem;
  }

  .hamburger::after {
    bottom: -0.5rem;
  }

  .mobile-menu {
    display: flex;
    flex-direction: column;
    background: white;
    border-top: 1px solid #e5e7eb;
    padding: 1rem;
  }

  :global(.dark) .mobile-menu {
    background: #1f2937;
    border-top-color: #374151;
  }

  .mobile-link {
    color: #6b7280;
    text-decoration: none;
    font-weight: 500;
    padding: 0.75rem;
    border-radius: 0.5rem;
    transition: all 0.2s ease;
  }

  .mobile-link:hover,
  .mobile-link.active {
    color: #ff3e00;
    background-color: rgba(255, 62, 0, 0.1);
  }

  :global(.dark) .mobile-link {
    color: #d1d5db;
  }

  .desktop-only {
    display: flex;
  }

  .mobile-only {
    display: none;
  }

  @media (max-width: 768px) {
    .desktop-only {
      display: none;
    }

    .mobile-only {
      display: block;
    }
  }
</style>
EOF

    # Create Hero component
    cat > src/lib/components/Hero.svelte << 'EOF'
<script lang="ts">
  export let title = "Welcome to SvelteKit";
  export let subtitle = "A modern, fast, and developer-friendly framework for building web applications";
</script>

<section class="hero">
  <div class="hero-content">
    <h1 class="hero-title">{title}</h1>
    <p class="hero-subtitle">{subtitle}</p>
    <div class="hero-actions">
      <a href="/about" class="btn btn-primary">Get Started</a>
      <a href="/blog" class="btn btn-secondary">Learn More</a>
    </div>
  </div>

  <div class="hero-visual">
    <div class="svelte-logo">
      <svg viewBox="0 0 103 124" class="logo">
        <path d="m96.33 64.85c-4.89-15.93-19.12-27.83-35.64-29.75-16.52-1.92-33.26 6.3-42.14 20.64-8.88 14.34-8.49 32.36.97 46.26 9.46 13.9 25.34 21.76 39.78 19.67 14.44-2.09 27.26-12.47 32.15-26.05 4.89-13.58 2.99-28.19-3.12-30.77z" fill="#ff3e00"/>
        <path d="m78.5 75.3c-4.89-15.93-19.12-27.83-35.64-29.75-16.52-1.92-33.26 6.3-42.14 20.64-8.88 14.34-8.49 32.36.97 46.26 9.46 13.9 25.34 21.76 39.78 19.67 14.44-2.09 27.26-12.47 32.15-26.05 4.89-13.58 2.99-28.19-3.12-30.77z" fill="#fff"/>
      </svg>
    </div>
  </div>
</section>

<style>
  .hero {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 4rem 1rem;
    display: flex;
    align-items: center;
    min-height: 60vh;
  }

  .hero-content {
    max-width: 1200px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 4rem;
    align-items: center;
    width: 100%;
  }

  .hero-title {
    font-size: 3.5rem;
    font-weight: 900;
    line-height: 1.1;
    margin-bottom: 1.5rem;
  }

  .hero-subtitle {
    font-size: 1.25rem;
    line-height: 1.6;
    margin-bottom: 2rem;
    opacity: 0.9;
  }

  .hero-actions {
    display: flex;
    gap: 1rem;
    flex-wrap: wrap;
  }

  .btn {
    display: inline-block;
    padding: 1rem 2rem;
    border-radius: 0.5rem;
    text-decoration: none;
    font-weight: 600;
    transition: all 0.2s ease;
  }

  .btn-primary {
    background: #ff3e00;
    color: white;
  }

  .btn-primary:hover {
    background: #d63200;
    transform: translateY(-2px);
  }

  .btn-secondary {
    background: transparent;
    color: white;
    border: 2px solid white;
  }

  .btn-secondary:hover {
    background: white;
    color: #667eea;
  }

  .hero-visual {
    display: flex;
    justify-content: center;
    align-items: center;
  }

  .svelte-logo {
    width: 200px;
    height: 200px;
    animation: float 6s ease-in-out infinite;
  }

  .logo {
    width: 100%;
    height: 100%;
  }

  @keyframes float {
    0%, 100% {
      transform: translateY(0px);
    }
    50% {
      transform: translateY(-20px);
    }
  }

  @media (max-width: 768px) {
    .hero-content {
      grid-template-columns: 1fr;
      text-align: center;
      gap: 2rem;
    }

    .hero-title {
      font-size: 2.5rem;
    }

    .hero-actions {
      justify-content: center;
    }

    .svelte-logo {
      width: 150px;
      height: 150px;
    }
  }
</style>
EOF

    # Create theme store
    mkdir -p src/lib/stores
    cat > src/lib/stores/theme.ts << 'EOF'
import { writable } from 'svelte/store';
import { browser } from '$app/environment';

type Theme = 'light' | 'dark';

function createTheme() {
  const { subscribe, set, update } = writable<Theme>('light');

  return {
    subscribe,
    set: (theme: Theme) => {
      if (browser) {
        localStorage.setItem('theme', theme);
        document.documentElement.classList.toggle('dark', theme === 'dark');
      }
      set(theme);
    },
    toggle: () => update(theme => {
      const newTheme = theme === 'light' ? 'dark' : 'light';
      if (browser) {
        localStorage.setItem('theme', newTheme);
        document.documentElement.classList.toggle('dark', newTheme === 'dark');
      }
      return newTheme;
    }),
    init: () => {
      if (browser) {
        const stored = localStorage.getItem('theme') as Theme;
        const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
        const theme = stored || (prefersDark ? 'dark' : 'light');

        document.documentElement.classList.toggle('dark', theme === 'dark');
        set(theme);
      }
    }
  };
}

export const theme = createTheme();
EOF

    # Create theme toggle component
    cat > src/lib/components/ThemeToggle.svelte << 'EOF'
<script lang="ts">
  import { theme } from '$lib/stores/theme';
  import { onMount } from 'svelte';

  onMount(() => {
    theme.init();
  });

  function handleToggle() {
    theme.toggle();
  }
</script>

<button
  class="theme-toggle"
  on:click={handleToggle}
  aria-label="Toggle theme"
  title="Toggle theme"
>
  {#if $theme === 'dark'}
    <span class="icon">☀️</span>
  {:else}
    <span class="icon">🌙</span>
  {/if}
</button>

<style>
  .theme-toggle {
    background: none;
    border: 1px solid #e5e7eb;
    border-radius: 0.5rem;
    padding: 0.5rem;
    cursor: pointer;
    transition: all 0.2s ease;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .theme-toggle:hover {
    background-color: rgba(107, 114, 128, 0.1);
  }

  :global(.dark) .theme-toggle {
    border-color: #374151;
  }

  .icon {
    font-size: 1.2rem;
    line-height: 1;
  }
</style>
EOF

    # Create main CSS file
    cat > src/app.css << 'EOF'
${data.coder_parameter.ui_framework.value == "tailwind" ? "@import \"tailwindcss/base\";" : ""}
${data.coder_parameter.ui_framework.value == "tailwind" ? "@import \"tailwindcss/components\";" : ""}
${data.coder_parameter.ui_framework.value == "tailwind" ? "@import \"tailwindcss/utilities\";" : ""}

:root {
  /* Light theme colors */
  --color-primary: #ff3e00;
  --color-surface-50: #fafafa;
  --color-surface-900: #1a1a1a;
  --color-text: #333333;
  --color-text-secondary: #666666;
}

.dark {
  /* Dark theme colors */
  --color-text: #ffffff;
  --color-text-secondary: #cccccc;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  line-height: 1.6;
  color: var(--color-text);
  transition: color 0.2s ease-in-out, background-color 0.2s ease-in-out;
}

h1, h2, h3, h4, h5, h6 {
  margin: 0 0 1rem 0;
  font-weight: 600;
}

p {
  margin: 0 0 1rem 0;
}

a {
  color: var(--color-primary);
  text-decoration: none;
}

a:hover {
  text-decoration: underline;
}

.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
}

/* Component utilities */
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: 0.5rem;
  font-weight: 600;
  text-decoration: none;
  cursor: pointer;
  transition: all 0.2s ease;
  font-size: 1rem;
}

.btn:hover {
  transform: translateY(-1px);
  text-decoration: none;
}

.btn-primary {
  background: var(--color-primary);
  color: white;
}

.btn-secondary {
  background: transparent;
  color: var(--color-primary);
  border: 2px solid var(--color-primary);
}

.card {
  background: white;
  border-radius: 0.5rem;
  padding: 1.5rem;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
  transition: box-shadow 0.2s ease;
}

.dark .card {
  background: #2d2d2d;
}

.card:hover {
  box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1rem;
}

/* Responsive utilities */
@media (max-width: 768px) {
  .mobile-hidden {
    display: none;
  }
}

@media (min-width: 769px) {
  .desktop-hidden {
    display: none;
  }
}
EOF

    # Create about page
    mkdir -p src/routes/about
    cat > src/routes/about/+page.svelte << 'EOF'
<script lang="ts">
  import { page } from '$app/stores';
</script>

<svelte:head>
  <title>About - SvelteKit App</title>
  <meta name="description" content="Learn more about our SvelteKit application" />
</svelte:head>

<div class="container">
  <div class="about-content">
    <h1>About Our SvelteKit App</h1>

    <div class="intro">
      <p>
        This application demonstrates the power and simplicity of SvelteKit,
        combined with modern development practices and tools.
      </p>
    </div>

    <div class="features-grid">
      <div class="feature">
        <h3>⚡ Lightning Fast</h3>
        <p>Built with Vite for incredibly fast development and optimized production builds.</p>
      </div>

      <div class="feature">
        <h3>🎨 Beautiful UI</h3>
        <p>Styled with ${data.coder_parameter.ui_framework.value} for a modern, responsive design.</p>
      </div>

      <div class="feature">
        <h3>🔧 Developer Experience</h3>
        <p>TypeScript, ESLint, Prettier, and comprehensive testing setup included.</p>
      </div>

      <div class="feature">
        <h3>📱 ${data.coder_parameter.enable_pwa.value ? "PWA Ready" : "Mobile First"}</h3>
        <p>${data.coder_parameter.enable_pwa.value ? "Progressive Web App capabilities for native-like experience" : "Responsive design that works great on all devices"}.</p>
      </div>

      <div class="feature">
        <h3>🚀 ${data.coder_parameter.adapter.value == "static" ? "Static Site" : "Server-Side Rendering"}</h3>
        <p>Configured with @sveltejs/adapter-${data.coder_parameter.adapter.value} for optimal deployment.</p>
      </div>

      <div class="feature">
        <h3>🧪 Testing Included</h3>
        <p>Vitest for unit testing and Playwright for end-to-end testing.</p>
      </div>
    </div>

    <div class="tech-stack">
      <h2>Technology Stack</h2>
      <div class="tech-badges">
        <span class="badge">SvelteKit</span>
        <span class="badge">TypeScript</span>
        <span class="badge">${data.coder_parameter.ui_framework.value == "tailwind" ? "Tailwind CSS" : data.coder_parameter.ui_framework.value}</span>
        <span class="badge">Vite</span>
        <span class="badge">Vitest</span>
        <span class="badge">Playwright</span>
        <span class="badge">ESLint</span>
        <span class="badge">Prettier</span>
      </div>
    </div>
  </div>
</div>

<style>
  .about-content {
    max-width: 800px;
    margin: 0 auto;
    padding: 2rem 0;
  }

  h1 {
    font-size: 3rem;
    text-align: center;
    margin-bottom: 2rem;
    background: linear-gradient(45deg, #ff3e00, #ff8a00);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }

  .intro {
    text-align: center;
    font-size: 1.2rem;
    margin-bottom: 3rem;
    color: var(--color-text-secondary);
  }

  .features-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 2rem;
    margin-bottom: 3rem;
  }

  .feature {
    background: white;
    padding: 2rem;
    border-radius: 0.5rem;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    transition: transform 0.2s ease, box-shadow 0.2s ease;
  }

  .dark .feature {
    background: #2d2d2d;
  }

  .feature:hover {
    transform: translateY(-4px);
    box-shadow: 0 8px 16px rgba(0, 0, 0, 0.15);
  }

  .feature h3 {
    margin-bottom: 1rem;
    color: var(--color-primary);
  }

  .tech-stack {
    text-align: center;
  }

  .tech-stack h2 {
    margin-bottom: 2rem;
  }

  .tech-badges {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    justify-content: center;
  }

  .badge {
    background: var(--color-primary);
    color: white;
    padding: 0.5rem 1rem;
    border-radius: 9999px;
    font-size: 0.9rem;
    font-weight: 500;
  }

  @media (max-width: 768px) {
    h1 {
      font-size: 2rem;
    }

    .features-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
EOF

    # Create API route example
    mkdir -p src/routes/api
    cat > src/routes/api/health/+server.ts << 'EOF'
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async () => {
  return json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    framework: 'SvelteKit',
    adapter: '${data.coder_parameter.adapter.value}',
    ui: '${data.coder_parameter.ui_framework.value}',
    pwa: ${data.coder_parameter.enable_pwa.value}
  });
};
EOF

    # Create TypeScript config
    cat > tsconfig.json << 'EOF'
{
  "extends": "./.svelte-kit/tsconfig.json",
  "compilerOptions": {
    "allowJs": true,
    "checkJs": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "sourceMap": true,
    "strict": true,
    "moduleResolution": "bundler"
  }
}
EOF

    # Create test setup
    cat > src/setupTests.ts << 'EOF'
import '@testing-library/jest-dom';
import { vi } from 'vitest';

// Mock SvelteKit modules
vi.mock('$app/environment', () => ({
  browser: false,
  dev: true,
  building: false,
  version: ''
}));

vi.mock('$app/navigation', () => ({
  goto: vi.fn(),
  invalidate: vi.fn(),
  invalidateAll: vi.fn(),
  preloadData: vi.fn(),
  preloadCode: vi.fn(),
  beforeNavigate: vi.fn(),
  afterNavigate: vi.fn()
}));

vi.mock('$app/stores', () => ({
  page: {
    subscribe: vi.fn()
  },
  navigating: {
    subscribe: vi.fn()
  },
  updated: {
    subscribe: vi.fn()
  }
}));
EOF

    # Create sample test
    cat > src/lib/components/Header.test.ts << 'EOF'
import { render, screen } from '@testing-library/svelte';
import { describe, it, expect } from 'vitest';
import Header from './Header.svelte';

describe('Header', () => {
  it('renders the brand name', () => {
    render(Header);
    expect(screen.getByText('SvelteKit')).toBeInTheDocument();
  });

  it('renders navigation links', () => {
    render(Header);
    expect(screen.getByText('Home')).toBeInTheDocument();
    expect(screen.getByText('About')).toBeInTheDocument();
    expect(screen.getByText('Blog')).toBeInTheDocument();
    expect(screen.getByText('Contact')).toBeInTheDocument();
  });
});
EOF

    # Create PWA service worker if enabled
    if [[ "${data.coder_parameter.enable_pwa.value}" == "true" ]]; then
      cat > src/sw.ts << 'EOF'
import { build, files, version } from '$service-worker';

const CACHE = `cache-$${version}`;
const ASSETS = [...build, ...files];

self.addEventListener('install', (event) => {
  async function addFilesToCache() {
    const cache = await caches.open(CACHE);
    await cache.addAll(ASSETS);
  }

  event.waitUntil(addFilesToCache());
});

self.addEventListener('activate', (event) => {
  async function deleteOldCaches() {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
    }
  }

  event.waitUntil(deleteOldCaches());
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  async function respond() {
    const url = new URL(event.request.url);
    const cache = await caches.open(CACHE);

    if (ASSETS.includes(url.pathname)) {
      const response = await cache.match(url.pathname);
      if (response) {
        return response;
      }
    }

    try {
      const response = await fetch(event.request);
      const isNotExtension = url.protocol === 'http:' || url.protocol === 'https:';
      const isSuccess = response.status === 200;

      if (isNotExtension && isSuccess) {
        cache.put(event.request, response.clone());
      }

      return response;
    } catch {
      const response = await cache.match(url.pathname);
      if (response) {
        return response;
      }
    }

    return new Response('Not found', { status: 404 });
  }

  event.respondWith(respond());
});
EOF
    fi

    # Create Docker configuration
    cat > Dockerfile << 'EOF'
# Build stage
FROM node:${data.coder_parameter.node_version.value}-alpine as build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Runtime stage
${data.coder_parameter.adapter.value == "node" ? "FROM node:${data.coder_parameter.node_version.value}-alpine" : "FROM nginx:alpine"}

${data.coder_parameter.adapter.value == "node" ? "WORKDIR /app" : "# Using nginx"}
${data.coder_parameter.adapter.value == "node" ? "COPY --from=build /app/build ." : "COPY --from=build /app/build /usr/share/nginx/html"}
${data.coder_parameter.adapter.value == "node" ? "COPY --from=build /app/node_modules ./node_modules" : "# No node_modules needed for nginx"}
${data.coder_parameter.adapter.value == "node" ? "COPY package.json ." : "# No package.json needed for nginx"}

${data.coder_parameter.adapter.value == "node" ? "EXPOSE 3000" : "EXPOSE 80"}

${data.coder_parameter.adapter.value == "node" ? "CMD [\"node\", \"index.js\"]" : "CMD [\"nginx\", \"-g\", \"daemon off;\"]"}
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  sveltekit-app:
    build: .
    ports:
      - "${data.coder_parameter.adapter.value == "node" ? "5173:3000" : "5173:80"}"
    environment:
      - NODE_ENV=production
    restart: unless-stopped

  backend:
    image: node:${data.coder_parameter.node_version.value}-alpine
    working_dir: /app
    ports:
      - "3001:3000"
    environment:
      - NODE_ENV=development
      - PORT=3000
    command: sh -c "npm init -y && npm install express cors && node -e 'const express = require(\"express\"); const cors = require(\"cors\"); const app = express(); app.use(cors()); app.use(express.json()); app.get(\"/api/health\", (req, res) => res.json({status: \"ok\", framework: \"express\"})); app.listen(3000, () => console.log(\"Backend running on port 3000\"));'"
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
.DS_Store
node_modules
/build
/.svelte-kit
/package
.env
.env.*
!.env.example
vite.config.js.timestamp-*
vite.config.ts.timestamp-*

# Testing
/coverage
/test-results

# Playwright
/playwright-report
/playwright/.cache
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/sveltekit-app

    # Install dependencies and run initial setup
    cd /home/coder/sveltekit-app
    npm install

    echo "✅ SvelteKit development environment ready!"
    echo "🔥 SvelteKit with ${data.coder_parameter.ui_framework.value}"
    echo "📦 Adapter: ${data.coder_parameter.adapter.value}"
    echo "📱 PWA: ${data.coder_parameter.enable_pwa.value}"
    echo "Run 'npm run dev' to start the development server"

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

resource "coder_metadata" "ui_framework" {
  resource_id = coder_agent.main.id
  item {
    key   = "ui_framework"
    value = data.coder_parameter.ui_framework.value
  }
}

resource "coder_metadata" "adapter" {
  resource_id = coder_agent.main.id
  item {
    key   = "adapter"
    value = data.coder_parameter.adapter.value
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
resource "coder_app" "sveltekit_dev" {
  agent_id     = coder_agent.main.id
  slug         = "sveltekit-dev"
  display_name = "SvelteKit Dev Server"
  url          = "http://localhost:5173"
  icon         = "/icon/svelte.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:5173"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/sveltekit-app"
  share        = "owner"
}

resource "coder_app" "preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Preview Server"
  url          = "http://localhost:4173"
  icon         = "/icon/preview.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:4173"
    interval  = 15
    threshold = 30
  }
}

# Kubernetes resources
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "home-${data.coder_workspace.me.id}"
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
