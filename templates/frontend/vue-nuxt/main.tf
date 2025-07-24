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

data "coder_parameter" "nuxt_version" {
  name         = "nuxt_version"
  display_name = "Nuxt Version"
  description  = "Nuxt.js version to use"
  default      = "3"
  icon         = "/icon/nuxt.svg"
  mutable      = false
  option {
    name  = "Nuxt 3"
    value = "3"
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
    name  = "Vuetify"
    value = "vuetify"
  }
  option {
    name  = "Quasar"
    value = "quasar"
  }
  option {
    name  = "PrimeVue"
    value = "primevue"
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

    echo "💚 Setting up Vue.js + Nuxt development environment..."

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

    # Install VS Code extensions for Vue/Nuxt
    code --install-extension Vue.volar
    code --install-extension Vue.vscode-typescript-vue-plugin
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension esbenp.prettier-vscode
    code --install-extension dbaeumer.vscode-eslint
    code --install-extension ms-vscode.vscode-json
    code --install-extension formulahendry.auto-rename-tag
    code --install-extension GitHub.copilot
    code --install-extension ms-playwright.playwright

    # Create Nuxt project
    echo "🚀 Creating Nuxt ${data.coder_parameter.nuxt_version.value} project..."
    cd /home/coder

    # Create Nuxt 3 project
    npx nuxi@latest init vue-nuxt-app
    cd vue-nuxt-app

    # Install dependencies
    npm install

    # Install UI framework
    case "${data.coder_parameter.ui_framework.value}" in
      "tailwind")
        echo "🎨 Installing Tailwind CSS..."
        npm install -D @nuxtjs/tailwindcss

        # Add to nuxt.config.ts
        cat > nuxt.config.ts << 'EOF'
export default defineNuxtConfig({
  devtools: { enabled: true },
  modules: [
    '@nuxtjs/tailwindcss',
    '@pinia/nuxt',
    '@nuxtjs/color-mode'
  ],
  css: ['~/assets/css/main.css'],
  colorMode: {
    preference: 'system',
    fallback: 'light',
    hid: 'nuxt-color-mode-script',
    globalName: '__NUXT_COLOR_MODE__',
    componentName: 'ColorScheme',
    classPrefix: '',
    classSuffix: '',
    storageKey: 'nuxt-color-mode'
  },
  runtimeConfig: {
    apiSecret: '',
    public: {
      apiBase: '/api'
    }
  }
})
EOF

        mkdir -p assets/css
        cat > assets/css/main.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  html {
    @apply scroll-smooth;
  }

  body {
    @apply bg-gray-50 dark:bg-gray-900 text-gray-900 dark:text-gray-100;
  }
}

@layer components {
  .btn-primary {
    @apply bg-blue-500 hover:bg-blue-600 text-white font-medium py-2 px-4 rounded transition-colors;
  }

  .btn-secondary {
    @apply bg-gray-200 hover:bg-gray-300 dark:bg-gray-700 dark:hover:bg-gray-600 text-gray-900 dark:text-gray-100 font-medium py-2 px-4 rounded transition-colors;
  }

  .card {
    @apply bg-white dark:bg-gray-800 rounded-lg shadow-md p-6;
  }
}
EOF
        ;;
      "vuetify")
        echo "🎨 Installing Vuetify..."
        npm install vuetify @mdi/font
        npm install -D @nuxt/vite-builder
        ;;
      "quasar")
        echo "🎨 Installing Quasar..."
        npm install quasar @quasar/extras
        npm install -D @quasar/vite-plugin
        ;;
      "primevue")
        echo "🎨 Installing PrimeVue..."
        npm install primevue primeicons
        ;;
    esac

    # Install additional useful packages
    npm install @pinia/nuxt pinia
    npm install @nuxtjs/color-mode
    npm install @vueuse/nuxt @vueuse/core
    npm install axios @nuxtjs/axios

    # Install development packages
    npm install -D @nuxt/test-utils vitest jsdom
    npm install -D @playwright/test
    npm install -D eslint @nuxt/eslint-config prettier

    # Create sample pages and components
    mkdir -p pages/{about,blog}
    mkdir -p components/{UI,Layout}
    mkdir -p composables
    mkdir -p stores
    mkdir -p utils
    mkdir -p types

    # Create main layout
    mkdir -p layouts
    cat > layouts/default.vue << 'EOF'
<template>
  <div class="min-h-screen">
    <AppHeader />
    <main class="container mx-auto px-4 py-8">
      <slot />
    </main>
    <AppFooter />
  </div>
</template>

<script setup lang="ts">
useHead({
  title: 'Vue Nuxt App',
  meta: [
    { name: 'description', content: 'A modern Vue.js application built with Nuxt 3' }
  ]
})
</script>
EOF

    # Create header component
    cat > components/AppHeader.vue << 'EOF'
<template>
  <header class="bg-white dark:bg-gray-800 shadow-sm border-b border-gray-200 dark:border-gray-700">
    <nav class="container mx-auto px-4">
      <div class="flex justify-between items-center h-16">
        <div class="flex items-center space-x-8">
          <NuxtLink to="/" class="text-xl font-bold text-blue-600 dark:text-blue-400">
            Vue Nuxt App
          </NuxtLink>

          <div class="hidden md:flex space-x-6">
            <NuxtLink
              to="/"
              class="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400 transition-colors"
            >
              Home
            </NuxtLink>
            <NuxtLink
              to="/about"
              class="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400 transition-colors"
            >
              About
            </NuxtLink>
            <NuxtLink
              to="/blog"
              class="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400 transition-colors"
            >
              Blog
            </NuxtLink>
          </div>
        </div>

        <div class="flex items-center space-x-4">
          <ColorModeToggle />
          <button class="md:hidden" @click="toggleMobileMenu">
            <Icon name="mdi:menu" class="w-6 h-6" />
          </button>
        </div>
      </div>

      <!-- Mobile menu -->
      <div v-show="showMobileMenu" class="md:hidden py-4 border-t border-gray-200 dark:border-gray-700">
        <div class="flex flex-col space-y-2">
          <NuxtLink to="/" class="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400 py-2">
            Home
          </NuxtLink>
          <NuxtLink to="/about" class="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400 py-2">
            About
          </NuxtLink>
          <NuxtLink to="/blog" class="text-gray-700 dark:text-gray-300 hover:text-blue-600 dark:hover:text-blue-400 py-2">
            Blog
          </NuxtLink>
        </div>
      </div>
    </nav>
  </header>
</template>

<script setup lang="ts">
const showMobileMenu = ref(false)

const toggleMobileMenu = () => {
  showMobileMenu.value = !showMobileMenu.value
}
</script>
EOF

    # Create footer component
    cat > components/AppFooter.vue << 'EOF'
<template>
  <footer class="bg-gray-50 dark:bg-gray-900 border-t border-gray-200 dark:border-gray-700 mt-16">
    <div class="container mx-auto px-4 py-8">
      <div class="text-center text-gray-600 dark:text-gray-400">
        <p>&copy; {{ currentYear }} Vue Nuxt App. Built with Nuxt {{ nuxtVersion }} and Vue {{ vueVersion }}.</p>
      </div>
    </div>
  </footer>
</template>

<script setup lang="ts">
const currentYear = new Date().getFullYear()
const nuxtVersion = process.env.NUXT_VERSION || '3.x'
const vueVersion = process.env.VUE_VERSION || '3.x'
</script>
EOF

    # Create color mode toggle component
    cat > components/ColorModeToggle.vue << 'EOF'
<template>
  <button
    @click="toggleColorMode"
    class="p-2 rounded-md hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
    :title="'Switch to ' + (colorMode.preference === 'dark' ? 'light' : 'dark') + ' mode'"
  >
    <Icon
      :name="colorMode.preference === 'dark' ? 'mdi:weather-sunny' : 'mdi:weather-night'"
      class="w-5 h-5"
    />
  </button>
</template>

<script setup lang="ts">
const colorMode = useColorMode()

const toggleColorMode = () => {
  colorMode.preference = colorMode.preference === 'dark' ? 'light' : 'dark'
}
</script>
EOF

    # Update home page
    cat > app.vue << 'EOF'
<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>

<script setup lang="ts">
useHead({
  htmlAttrs: {
    lang: 'en'
  },
  link: [
    {
      rel: 'icon',
      type: 'image/x-icon',
      href: '/favicon.ico'
    }
  ]
})
</script>
EOF

    # Create home page
    cat > pages/index.vue << 'EOF'
<template>
  <div>
    <div class="text-center mb-16">
      <h1 class="text-4xl md:text-6xl font-bold text-gray-900 dark:text-white mb-6">
        Welcome to
        <span class="text-blue-600 dark:text-blue-400">Vue Nuxt</span>
      </h1>
      <p class="text-xl text-gray-600 dark:text-gray-300 mb-8 max-w-2xl mx-auto">
        A modern full-stack Vue.js application built with Nuxt 3, featuring server-side rendering,
        automatic code splitting, and powerful developer experience.
      </p>
      <div class="flex justify-center space-x-4">
        <NuxtLink to="/about" class="btn-primary">
          Get Started
        </NuxtLink>
        <NuxtLink to="/blog" class="btn-secondary">
          View Blog
        </NuxtLink>
      </div>
    </div>

    <div class="grid md:grid-cols-3 gap-8">
      <FeatureCard
        title="⚡️ Fast & Modern"
        description="Built with Nuxt 3 and Vue 3 Composition API for optimal performance and developer experience."
      />
      <FeatureCard
        title="🎨 Beautiful Design"
        description="${data.coder_parameter.ui_framework.value == "tailwind" ? "Styled with Tailwind CSS" : "Modern UI with " + data.coder_parameter.ui_framework.value} for a responsive and accessible interface."
      />
      <FeatureCard
        title="🚀 Production Ready"
        description="SSR, automatic code splitting, and built-in optimizations for better SEO and performance."
      />
    </div>

    <div class="mt-16 text-center">
      <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-8">
        Technology Stack
      </h2>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <TechBadge name="Vue 3" color="green" />
        <TechBadge name="Nuxt ${data.coder_parameter.nuxt_version.value}" color="green" />
        <TechBadge name="${data.coder_parameter.ui_framework.value == "tailwind" ? "Tailwind" : data.coder_parameter.ui_framework.value}" color="blue" />
        <TechBadge name="TypeScript" color="blue" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
useHead({
  title: 'Home - Vue Nuxt App',
  meta: [
    { name: 'description', content: 'Welcome to our modern Vue.js application built with Nuxt 3' }
  ]
})

// Test composable
const { data: stats } = await useFetch('/api/stats')
</script>
EOF

    # Create reusable components
    cat > components/FeatureCard.vue << 'EOF'
<template>
  <div class="card">
    <h3 class="text-xl font-semibold text-gray-900 dark:text-white mb-3">
      {{ title }}
    </h3>
    <p class="text-gray-600 dark:text-gray-300">
      {{ description }}
    </p>
  </div>
</template>

<script setup lang="ts">
interface Props {
  title: string
  description: string
}

defineProps<Props>()
</script>
EOF

    cat > components/TechBadge.vue << 'EOF'
<template>
  <span
    class="inline-block px-3 py-1 rounded-full text-sm font-medium"
    :class="badgeClasses"
  >
    {{ name }}
  </span>
</template>

<script setup lang="ts">
interface Props {
  name: string
  color: 'blue' | 'green' | 'purple' | 'red'
}

const props = defineProps<Props>()

const badgeClasses = computed(() => {
  const baseClasses = 'inline-block px-3 py-1 rounded-full text-sm font-medium'

  switch (props.color) {
    case 'blue':
      return `${baseClasses} bg-blue-100 text-blue-800 dark:bg-blue-800 dark:text-blue-100`
    case 'green':
      return `${baseClasses} bg-green-100 text-green-800 dark:bg-green-800 dark:text-green-100`
    case 'purple':
      return `${baseClasses} bg-purple-100 text-purple-800 dark:bg-purple-800 dark:text-purple-100`
    case 'red':
      return `${baseClasses} bg-red-100 text-red-800 dark:bg-red-800 dark:text-red-100`
    default:
      return `${baseClasses} bg-gray-100 text-gray-800 dark:bg-gray-800 dark:text-gray-100`
  }
})
</script>
EOF

    # Create about page
    cat > pages/about.vue << 'EOF'
<template>
  <div>
    <div class="text-center mb-16">
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-6">
        About Our App
      </h1>
      <p class="text-xl text-gray-600 dark:text-gray-300 max-w-3xl mx-auto">
        This application showcases modern Vue.js development with Nuxt 3,
        featuring server-side rendering, automatic code splitting, and a
        delightful developer experience.
      </p>
    </div>

    <div class="grid md:grid-cols-2 gap-12 items-center">
      <div>
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">
          Features & Capabilities
        </h2>
        <ul class="space-y-4">
          <li class="flex items-start">
            <Icon name="mdi:check-circle" class="w-6 h-6 text-green-500 mr-3 mt-1 flex-shrink-0" />
            <span class="text-gray-600 dark:text-gray-300">Server-side rendering for better SEO</span>
          </li>
          <li class="flex items-start">
            <Icon name="mdi:check-circle" class="w-6 h-6 text-green-500 mr-3 mt-1 flex-shrink-0" />
            <span class="text-gray-600 dark:text-gray-300">Automatic code splitting and lazy loading</span>
          </li>
          <li class="flex items-start">
            <Icon name="mdi:check-circle" class="w-6 h-6 text-green-500 mr-3 mt-1 flex-shrink-0" />
            <span class="text-gray-600 dark:text-gray-300">Dark mode support with system preference detection</span>
          </li>
          <li class="flex items-start">
            <Icon name="mdi:check-circle" class="w-6 h-6 text-green-500 mr-3 mt-1 flex-shrink-0" />
            <span class="text-gray-600 dark:text-gray-300">Responsive design with ${data.coder_parameter.ui_framework.value}</span>
          </li>
          <li class="flex items-start">
            <Icon name="mdi:check-circle" class="w-6 h-6 text-green-500 mr-3 mt-1 flex-shrink-0" />
            <span class="text-gray-600 dark:text-gray-300">TypeScript support for better development experience</span>
          </li>
        </ul>
      </div>

      <div class="card">
        <h3 class="text-xl font-semibold text-gray-900 dark:text-white mb-4">
          Project Stats
        </h3>
        <div class="space-y-3">
          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-300">Vue Version:</span>
            <span class="font-medium">{{ vueVersion }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-300">Nuxt Version:</span>
            <span class="font-medium">{{ nuxtVersion }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-300">Node.js:</span>
            <span class="font-medium">${data.coder_parameter.node_version.value}.x</span>
          </div>
          <div class="flex justify-between">
            <span class="text-gray-600 dark:text-gray-300">UI Framework:</span>
            <span class="font-medium">${data.coder_parameter.ui_framework.value}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
useHead({
  title: 'About - Vue Nuxt App',
  meta: [
    { name: 'description', content: 'Learn more about our Vue.js application built with Nuxt 3' }
  ]
})

const vueVersion = ref('3.x')
const nuxtVersion = ref('3.x')

// You could fetch these from package.json or runtime
onMounted(() => {
  // Mock values - in real app you might fetch from API
  vueVersion.value = '3.4.x'
  nuxtVersion.value = '3.8.x'
})
</script>
EOF

    # Create blog pages
    cat > pages/blog/index.vue << 'EOF'
<template>
  <div>
    <div class="text-center mb-16">
      <h1 class="text-4xl font-bold text-gray-900 dark:text-white mb-6">
        Blog
      </h1>
      <p class="text-xl text-gray-600 dark:text-gray-300">
        Thoughts, tutorials, and insights about Vue.js and Nuxt development.
      </p>
    </div>

    <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
      <article
        v-for="post in posts"
        :key="post.slug"
        class="card hover:shadow-lg transition-shadow"
      >
        <div class="mb-4">
          <span class="text-sm text-blue-600 dark:text-blue-400 font-medium">
            {{ post.category }}
          </span>
          <span class="text-sm text-gray-500 dark:text-gray-400 ml-2">
            {{ formatDate(post.date) }}
          </span>
        </div>

        <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-3">
          {{ post.title }}
        </h2>

        <p class="text-gray-600 dark:text-gray-300 mb-4">
          {{ post.excerpt }}
        </p>

        <NuxtLink
          :to="`/blog/${post.slug}`"
          class="text-blue-600 dark:text-blue-400 hover:text-blue-700 dark:hover:text-blue-300 font-medium"
        >
          Read more →
        </NuxtLink>
      </article>
    </div>
  </div>
</template>

<script setup lang="ts">
useHead({
  title: 'Blog - Vue Nuxt App',
  meta: [
    { name: 'description', content: 'Read our latest blog posts about Vue.js and Nuxt development' }
  ]
})

const posts = ref([
  {
    slug: 'getting-started-nuxt-3',
    title: 'Getting Started with Nuxt 3',
    excerpt: 'Learn how to build modern web applications with Nuxt 3 and Vue 3.',
    category: 'Tutorial',
    date: new Date('2024-01-15')
  },
  {
    slug: 'vue-composition-api-guide',
    title: 'Vue Composition API Guide',
    excerpt: 'Master the Vue 3 Composition API with practical examples and best practices.',
    category: 'Guide',
    date: new Date('2024-01-10')
  },
  {
    slug: 'building-ssr-apps-nuxt',
    title: 'Building SSR Apps with Nuxt',
    excerpt: 'Understand server-side rendering and how it improves your app performance.',
    category: 'Deep Dive',
    date: new Date('2024-01-05')
  }
])

const formatDate = (date: Date) => {
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  }).format(date)
}
</script>
EOF

    # Create composable
    cat > composables/useApi.ts << 'EOF'
export const useApi = () => {
  const config = useRuntimeConfig()

  const get = async <T>(url: string): Promise<T> => {
    const { data } = await $fetch<{ data: T }>(`${config.public.apiBase}${url}`)
    return data
  }

  const post = async <T, U>(url: string, body: U): Promise<T> => {
    const { data } = await $fetch<{ data: T }>(`${config.public.apiBase}${url}`, {
      method: 'POST',
      body
    })
    return data
  }

  return {
    get,
    post
  }
}
EOF

    # Create store with Pinia
    cat > stores/counter.ts << 'EOF'
import { defineStore } from 'pinia'

export const useCounterStore = defineStore('counter', () => {
  const count = ref(0)
  const doubleCount = computed(() => count.value * 2)

  const increment = () => {
    count.value++
  }

  const decrement = () => {
    count.value--
  }

  const reset = () => {
    count.value = 0
  }

  return {
    count,
    doubleCount,
    increment,
    decrement,
    reset
  }
})
EOF

    # Create API route
    mkdir -p server/api
    cat > server/api/stats.ts << 'EOF'
export default defineEventHandler(async (event) => {
  // Simulate API delay
  await new Promise(resolve => setTimeout(resolve, 100))

  return {
    users: 1250,
    posts: 89,
    views: 15430,
    uptime: '99.9%'
  }
})
EOF

    # Create types
    cat > types/index.ts << 'EOF'
export interface Post {
  slug: string
  title: string
  excerpt: string
  content?: string
  category: string
  date: Date
  author?: string
  tags?: string[]
}

export interface ApiResponse<T> {
  data: T
  message?: string
  status: 'success' | 'error'
}

export interface User {
  id: string
  name: string
  email: string
  avatar?: string
}
EOF

    # Create environment files
    cat > .env.example << 'EOF'
NUXT_API_SECRET=your-secret-key-here
NUXT_PUBLIC_API_BASE=/api
EOF

    # Create Docker configuration
    cat > Dockerfile << 'EOF'
FROM node:20-alpine as builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM node:20-alpine

WORKDIR /app

COPY --from=builder /app/.output ./

EXPOSE 3000

CMD ["node", "server/index.mjs"]
EOF

    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - NUXT_API_SECRET=production-secret
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

    # Configure ESLint and Prettier
    cat > .eslintrc.js << 'EOF'
module.exports = {
  root: true,
  extends: ['@nuxt/eslint-config'],
  rules: {
    // Add your custom rules here
  }
}
EOF

    cat > prettier.config.js << 'EOF'
module.exports = {
  semi: false,
  singleQuote: true,
  trailingComma: 'es5',
  tabWidth: 2,
  useTabs: false,
}
EOF

    # Update package.json scripts
    npm pkg set scripts.lint="eslint ."
    npm pkg set scripts.lint:fix="eslint . --fix"
    npm pkg set scripts.format="prettier --write ."
    npm pkg set scripts.test="vitest"
    npm pkg set scripts.test:e2e="playwright test"

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/vue-nuxt-app

    # Install dependencies and run initial build
    cd /home/coder/vue-nuxt-app
    npm install

    echo "✅ Vue.js + Nuxt development environment ready!"
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

resource "coder_metadata" "vue_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "vue_version"
    value = data.coder_parameter.vue_version.value
  }
}

resource "coder_metadata" "ui_framework" {
  resource_id = coder_agent.main.id
  item {
    key   = "ui_framework"
    value = data.coder_parameter.ui_framework.value
  }
}

resource "coder_metadata" "features" {
  resource_id = coder_agent.main.id
  item {
    key   = "features"
    value = data.coder_parameter.nuxt_features.value
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
resource "coder_app" "nuxt_dev" {
  agent_id     = coder_agent.main.id
  slug         = "nuxt-dev"
  display_name = "Nuxt Dev Server"
  url          = "http://localhost:3000"
  icon         = "/icon/nuxt.svg"
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
  command      = "code /home/coder/vue-nuxt-app"
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
