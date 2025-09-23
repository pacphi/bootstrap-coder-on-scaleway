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
  default      = "22"
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
  default      = "22"
  icon         = "/icon/nodejs.svg"
  mutable      = false
  option {
  }
  option {
    name  = "Node.js 20 LTS"
    value = "20"
  }
  option {
    name  = "Node.js 22 LTS"
    value = "22"
  }
}

data "coder_parameter" "react_native_version" {
  name         = "react_native_version"
  display_name = "React Native Version"
  description  = "React Native version to use"
  default      = "0.74"
  icon         = "/icon/react.svg"
  mutable      = false
  option {
    name  = "React Native 0.72"
    value = "0.72"
  }
  option {
    name  = "React Native 0.73"
    value = "0.73"
  }
  option {
    name  = "React Native 0.74"
    value = "0.74"
  }
}

data "coder_parameter" "target_platform" {
  name         = "target_platform"
  display_name = "Target Platform"
  description  = "Target mobile platforms for development"
  default      = "both"
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
    name  = "Both iOS & Android"
    value = "both"
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

    echo "📱 Setting up React Native development environment..."

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
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install ${data.coder_parameter.node_version.value}
    nvm use ${data.coder_parameter.node_version.value}
    nvm alias default ${data.coder_parameter.node_version.value}

    # Update PATH and environment
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc

    # Install Yarn and pnpm
    npm install -g yarn pnpm

    # Install React Native CLI and Expo CLI
    echo "⚛️ Installing React Native CLI and Expo CLI..."
    npm install -g @react-native-community/cli @expo/cli create-expo-app

    # Install Android SDK and tools if Android development is enabled
    if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "both" ]]; then
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
      sdkmanager "system-images;android-34;google_apis;x86_64"
      sdkmanager "emulator"

      # Create Android Virtual Device
      echo "📱 Creating Android Virtual Device..."
      echo "no" | avdmanager create avd -n ReactNativeAVD -k "system-images;android-34;google_apis;x86_64" --force
    fi

    # Install iOS development tools if iOS development is enabled (limited on Linux)
    if [[ "${data.coder_parameter.target_platform.value}" == "ios" || "${data.coder_parameter.target_platform.value}" == "both" ]]; then
      echo "🍎 Setting up iOS development tools (limited on Linux)..."
      # Install ios-deploy for device deployment
      npm install -g ios-deploy

      # Note: Xcode is not available on Linux, but we can install some tools
      echo "Note: Full iOS development requires macOS and Xcode. Using iOS simulator alternatives."
    fi

    # Install Fastlane for deployment automation
    echo "🚀 Installing Fastlane..."
    sudo apt-get install -y ruby ruby-dev
    sudo gem install fastlane -NV

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

    # Install VS Code extensions for React Native development
    echo "🔌 Installing VS Code extensions..."
    code --install-extension ms-vscode.vscode-react-native
    code --install-extension ms-vscode.vscode-typescript-next
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension esbenp.prettier-vscode
    code --install-extension dbaeumer.vscode-eslint
    code --install-extension ms-vscode.vscode-json
    code --install-extension GitHub.copilot
    code --install-extension ms-python.python
    code --install-extension ms-vscode.hexeditor
    code --install-extension formulahendry.auto-rename-tag
    code --install-extension ms-vscode.vscode-gradle
    code --install-extension redhat.java

    # Install additional useful tools
    sudo apt-get install -y htop tree jq imagemagick

    # Create React Native project
    cd /home/coder
    echo "🏗️ Creating React Native project..."

    # Initialize React Native project with specified version
    if command -v npx &> /dev/null; then
      npx react-native@${data.coder_parameter.react_native_version.value} init ReactNativeApp --version ${data.coder_parameter.react_native_version.value}
    else
      npm install -g react-native-cli
      react-native init ReactNativeApp --version ${data.coder_parameter.react_native_version.value}
    fi

    cd ReactNativeApp

    # Install additional useful React Native packages
    npm install --save react-navigation/native react-navigation/native-stack
    npm install --save react-native-screens react-native-safe-area-context
    npm install --save @react-native-async-storage/async-storage
    npm install --save react-native-vector-icons
    npm install --save axios
    npm install --save-dev @testing-library/react-native @testing-library/jest-native
    npm install --save-dev detox jest-circus

    # Create project structure
    mkdir -p src/{components,screens,navigation,services,utils,hooks,store,types,assets/{images,icons}}

    # Create sample components and screens
    cat > src/components/Welcome.tsx << 'EOF'
import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  SafeAreaView,
  Alert,
} from 'react-native';

interface WelcomeProps {
  name?: string;
}

const Welcome: React.FC<WelcomeProps> = ({ name = 'Developer' }) => {
  const handlePress = () => {
    Alert.alert('Welcome!', 'Your React Native environment is ready!');
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.content}>
        <Text style={styles.title}>Welcome, {name}!</Text>
        <Text style={styles.subtitle}>
          Your React Native development environment is ready to go.
        </Text>

        <View style={styles.statusContainer}>
          <View style={styles.statusItem}>
            <View style={styles.statusIndicator} />
            <Text style={styles.statusText}>React Native ${data.coder_parameter.react_native_version.value}</Text>
          </View>
          <View style={styles.statusItem}>
            <View style={styles.statusIndicator} />
            <Text style={styles.statusText}>Node.js ${data.coder_parameter.node_version.value}</Text>
          </View>
          <View style={styles.statusItem}>
            <View style={styles.statusIndicator} />
            <Text style={styles.statusText}>Target: ${data.coder_parameter.target_platform.value}</Text>
          </View>
        </View>

        <TouchableOpacity style={styles.button} onPress={handlePress}>
          <Text style={styles.buttonText}>Start Building</Text>
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f0f2f5',
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 12,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 16,
    color: '#666',
    marginBottom: 40,
    textAlign: 'center',
    lineHeight: 24,
    maxWidth: 300,
  },
  statusContainer: {
    marginBottom: 40,
  },
  statusItem: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  statusIndicator: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#4CAF50',
    marginRight: 12,
  },
  statusText: {
    fontSize: 14,
    color: '#666',
  },
  button: {
    backgroundColor: '#007AFF',
    paddingHorizontal: 32,
    paddingVertical: 16,
    borderRadius: 8,
    elevation: 2,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
    textAlign: 'center',
  },
});

export default Welcome;
EOF

    # Update App.tsx
    cat > App.tsx << 'EOF'
import React from 'react';
import Welcome from './src/components/Welcome';

const App: React.FC = () => {
  return <Welcome name="Coder" />;
};

export default App;
EOF

    # Create API service
    cat > src/services/api.ts << 'EOF'
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';

class ApiService {
  private client: AxiosInstance;

  constructor(baseURL: string = 'http://localhost:8000/api') {
    this.client = axios.create({
      baseURL,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      async (config: AxiosRequestConfig) => {
        const token = await AsyncStorage.getItem('auth_token');
        if (token && config.headers) {
          config.headers.Authorization = `Bearer $${token}`;
        }
        return config;
      },
      (error) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response: AxiosResponse) => response,
      async (error) => {
        if (error.response?.status === 401) {
          await AsyncStorage.removeItem('auth_token');
          // Handle logout or redirect to login
        }
        return Promise.reject(error);
      }
    );
  }

  async get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.get<T>(url, config);
    return response.data;
  }

  async post<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.post<T>(url, data, config);
    return response.data;
  }

  async put<T>(url: string, data?: any, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.put<T>(url, data, config);
    return response.data;
  }

  async delete<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.delete<T>(url, config);
    return response.data;
  }
}

export default new ApiService();
EOF

    # Create custom hooks
    cat > src/hooks/useApi.ts << 'EOF'
import { useState, useEffect, useCallback } from 'react';
import ApiService from '../services/api';

interface UseApiResult<T> {
  data: T | null;
  loading: boolean;
  error: Error | null;
  refetch: () => Promise<void>;
}

export function useApi<T>(url: string, dependencies: any[] = []): UseApiResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await ApiService.get<T>(url);
      setData(result);
    } catch (err) {
      setError(err as Error);
    } finally {
      setLoading(false);
    }
  }, [url]);

  useEffect(() => {
    fetchData();
  }, [fetchData, ...dependencies]);

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
  createdAt: string;
  updatedAt: string;
}

export interface ApiResponse<T> {
  status: 'success' | 'error';
  data: T;
  message?: string;
  pagination?: {
    current: number;
    pages: number;
    total: number;
  };
}

export interface Post {
  id: string;
  title: string;
  content: string;
  author: User;
  createdAt: string;
  updatedAt: string;
}

export type StackParamList = {
  Home: undefined;
  Profile: { userId: string };
  Settings: undefined;
};
EOF

    # Create navigation setup
    cat > src/navigation/AppNavigator.tsx << 'EOF'
import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { StackParamList } from '../types';

const Stack = createNativeStackNavigator<StackParamList>();

const AppNavigator: React.FC = () => {
  return (
    <NavigationContainer>
      <Stack.Navigator initialRouteName="Home">
        {/* Add your screens here */}
      </Stack.Navigator>
    </NavigationContainer>
  );
};

export default AppNavigator;
EOF

    # Create Metro configuration
    cat > metro.config.js << 'EOF'
const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);

// Add support for additional asset types
config.resolver.assetExts.push('db', 'mp3', 'ttf', 'obj', 'png', 'jpg');

module.exports = config;
EOF

    # Create Fastlane configuration
    mkdir -p fastlane
    cat > fastlane/Fastfile << 'EOF'
default_platform(:android)

platform :android do
  desc "Build and deploy Android app"
  lane :build do
    gradle(
      task: "clean assembleRelease",
      project_dir: "./android/"
    )
  end

  desc "Deploy to Google Play Console"
  lane :deploy do
    upload_to_play_store(
      track: 'internal',
      apk: './android/app/build/outputs/apk/release/app-release.apk'
    )
  end
end

platform :ios do
  desc "Build and deploy iOS app"
  lane :build do
    build_app(
      workspace: "./ios/ReactNativeApp.xcworkspace",
      scheme: "ReactNativeApp",
      export_method: "ad-hoc"
    )
  end

  desc "Deploy to TestFlight"
  lane :deploy do
    upload_to_testflight
  end
end
EOF

    # Create Jest configuration
    cat > jest.config.js << 'EOF'
module.exports = {
  preset: 'react-native',
  moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node'],
  transform: {
    '^.+\\.(js|jsx|ts|tsx)$': 'babel-jest',
  },
  testMatch: [
    '**/__tests__/**/*.(ts|tsx|js)',
    '**/*.(test|spec).(ts|tsx|js)',
  ],
  moduleNameMapping: {
    '^@/(.*)$': '<rootDir>/src/$1',
  },
  setupFilesAfterEnv: ['<rootDir>/jest.setup.js'],
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.d.ts',
    '!src/**/__tests__/**',
  ],
  coverageDirectory: 'coverage',
  coverageReporters: ['text', 'lcov'],
};
EOF

    # Create Jest setup
    cat > jest.setup.js << 'EOF'
import 'react-native-gesture-handler/jestSetup';
import '@testing-library/jest-native/extend-expect';

jest.mock('react-native-reanimated', () => {
  const Reanimated = require('react-native-reanimated/mock');
  Reanimated.default.call = () => {};
  return Reanimated;
});

jest.mock('react-native/Libraries/Animated/NativeAnimatedHelper');
EOF

    # Create Detox configuration for E2E testing
    cat > .detoxrc.js << 'EOF'
module.exports = {
  testRunner: 'jest',
  runnerConfig: 'e2e/jest.config.js',
  skipLegacyWorkersInjection: true,
  apps: {
    'android.debug': {
      type: 'android.apk',
      binaryPath: 'android/app/build/outputs/apk/debug/app-debug.apk',
      build: 'cd android && ./gradlew assembleDebug assembleAndroidTest -DtestBuildType=debug',
      reversePorts: [8081],
    },
    'ios.debug': {
      type: 'ios.app',
      binaryPath: 'ios/build/Build/Products/Debug-iphonesimulator/ReactNativeApp.app',
      build: 'xcodebuild -workspace ios/ReactNativeApp.xcworkspace -scheme ReactNativeApp -configuration Debug -sdk iphonesimulator -derivedDataPath ios/build',
    },
  },
  devices: {
    simulator: {
      type: 'ios.simulator',
      device: {
        type: 'iPhone 15',
      },
    },
    emulator: {
      type: 'android.emulator',
      device: {
        avdName: 'ReactNativeAVD',
      },
    },
  },
  configurations: {
    'ios.debug': {
      device: 'simulator',
      app: 'ios.debug',
    },
    'android.debug': {
      device: 'emulator',
      app: 'android.debug',
    },
  },
};
EOF

    # Create sample test files
    mkdir -p __tests__ e2e
    cat > __tests__/App.test.tsx << 'EOF'
import React from 'react';
import { render, screen } from '@testing-library/react-native';
import App from '../App';

describe('App', () => {
  it('renders welcome message', () => {
    render(<App />);
    expect(screen.getByText(/Welcome, Coder!/)).toBeDefined();
  });

  it('renders start building button', () => {
    render(<App />);
    expect(screen.getByText('Start Building')).toBeDefined();
  });
});
EOF

    # Create Docker configuration for builds
    cat > Dockerfile.android << 'EOF'
FROM reactnativecommunity/react-native-android:latest

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

# Build Android APK
RUN cd android && ./gradlew assembleRelease

# Extract APK
RUN mkdir -p /output && \
    cp android/app/build/outputs/apk/release/app-release.apk /output/
EOF

    # Create development scripts
    cat > scripts/start-dev.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting React Native development server..."

# Start Metro bundler in background
npm start &

# Wait a bit for Metro to start
sleep 5

# Start Android emulator if available and target includes Android
if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "both" ]]; then
  if command -v emulator &> /dev/null; then
    echo "📱 Starting Android emulator..."
    emulator -avd ReactNativeAVD -no-audio -no-window &

    # Wait for emulator to boot
    adb wait-for-device

    echo "📱 Running on Android..."
    npm run android
  fi
fi

# For iOS, just show instructions (since we're on Linux)
if [[ "${data.coder_parameter.target_platform.value}" == "ios" || "${data.coder_parameter.target_platform.value}" == "both" ]]; then
  echo "🍎 For iOS development, use a macOS environment with Xcode"
  echo "📱 You can use Expo Go app on your iOS device for testing"
fi

wait
EOF

    chmod +x scripts/start-dev.sh

    # Update package.json with additional scripts
    npm pkg set scripts.test="jest"
    npm pkg set scripts.test:watch="jest --watch"
    npm pkg set scripts.test:coverage="jest --coverage"
    npm pkg set scripts.test:e2e="detox test"
    npm pkg set scripts.build:android="cd android && ./gradlew assembleRelease"
    npm pkg set scripts.dev="./scripts/start-dev.sh"
    npm pkg set scripts.lint="eslint . --ext .js,.jsx,.ts,.tsx"
    npm pkg set scripts.type-check="tsc --noEmit"

    # Create VS Code workspace settings
    mkdir -p .vscode
    cat > .vscode/settings.json << 'EOF'
{
  "typescript.preferences.importModuleSpecifier": "relative",
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "emmet.includeLanguages": {
    "typescript": "typescriptreact",
    "javascript": "javascriptreact"
  },
  "files.associations": {
    "*.tsx": "typescriptreact"
  },
  "search.exclude": {
    "node_modules": true,
    "ios/build": true,
    "android/build": true,
    "android/.gradle": true
  }
}
EOF

    cat > .vscode/launch.json << 'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Android",
      "cwd": "$${workspaceFolder}",
      "type": "reactnativedirect",
      "request": "launch",
      "platform": "android"
    },
    {
      "name": "Debug iOS",
      "cwd": "$${workspaceFolder}",
      "type": "reactnativedirect",
      "request": "launch",
      "platform": "ios"
    },
    {
      "name": "Attach to packager",
      "cwd": "$${workspaceFolder}",
      "type": "reactnativedirect",
      "request": "attach"
    }
  ]
}
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/ReactNativeApp
    sudo chown -R coder:coder /home/coder/Android 2>/dev/null || true

    # Install dependencies
    cd /home/coder/ReactNativeApp
    npm install

    echo "✅ React Native development environment ready!"
    echo "📱 Platform target: ${data.coder_parameter.target_platform.value}"
    echo "⚛️ React Native version: ${data.coder_parameter.react_native_version.value}"
    echo "📦 Node.js version: ${data.coder_parameter.node_version.value}"

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

resource "coder_metadata" "react_native_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "react_native_version"
    value = data.coder_parameter.react_native_version.value
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
resource "coder_app" "react_native_metro" {
  agent_id     = coder_agent.main.id
  slug         = "metro-bundler"
  display_name = "Metro Bundler"
  url          = "http://localhost:8081"
  icon         = "/icon/react.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8081/status"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder/ReactNativeApp"
  share        = "owner"
}

resource "coder_app" "android_studio" {
  count        = contains(["android", "both"], data.coder_parameter.target_platform.value) ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "android-emulator"
  display_name = "Android Emulator"
  icon         = "/icon/android.svg"
  command      = "emulator -avd ReactNativeAVD"
  share        = "owner"
}

resource "coder_app" "expo_devtools" {
  agent_id     = coder_agent.main.id
  slug         = "expo-devtools"
  display_name = "Expo Dev Tools"
  url          = "http://localhost:19002"
  icon         = "/icon/expo.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:19002"
    interval  = 15
    threshold = 20
  }
}

resource "coder_app" "flipper" {
  agent_id     = coder_agent.main.id
  slug         = "flipper"
  display_name = "Flipper Debugger"
  url          = "http://localhost:9222"
  icon         = "/icon/debug.svg"
  subdomain    = false
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

          # Expose common React Native development ports
          port {
            container_port = 8081
            name           = "metro"
            protocol       = "TCP"
          }

          port {
            container_port = 19000
            name           = "expo"
            protocol       = "TCP"
          }

          port {
            container_port = 19002
            name           = "expo-devtools"
            protocol       = "TCP"
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

# Service for React Native development ports
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
      name        = "metro"
      port        = 8081
      target_port = 8081
      protocol    = "TCP"
    }

    port {
      name        = "expo"
      port        = 19000
      target_port = 19000
      protocol    = "TCP"
    }

    port {
      name        = "expo-devtools"
      port        = 19002
      target_port = 19002
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
