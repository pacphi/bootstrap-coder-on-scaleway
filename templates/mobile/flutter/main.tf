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
  default      = "20"
  type         = "number"
  icon         = "/icon/folder.svg"
  mutable      = false
  validation {
    min = 15
    max = 100
  }
}

data "coder_parameter" "flutter_version" {
  name         = "flutter_version"
  display_name = "Flutter Version"
  description  = "Flutter version to install"
  default      = "3.22"
  icon         = "/icon/flutter.svg"
  mutable      = false
  option {
    name  = "Flutter 3.16"
    value = "3.16"
  }
  option {
    name  = "Flutter 3.19"
    value = "3.19"
  }
  option {
    name  = "Flutter 3.22"
    value = "3.22"
  }
}

data "coder_parameter" "dart_version" {
  name         = "dart_version"
  display_name = "Dart Version"
  description  = "Dart version to use (comes with Flutter)"
  default      = "3.4"
  icon         = "/icon/dart.svg"
  mutable      = false
  option {
    name  = "Dart 3.2"
    value = "3.2"
  }
  option {
    name  = "Dart 3.3"
    value = "3.3"
  }
  option {
    name  = "Dart 3.4"
    value = "3.4"
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
    name  = "Desktop Only"
    value = "desktop"
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

    echo "🎯 Setting up Flutter development environment..."

    # Update system and install essential packages
    sudo apt-get update
    sudo apt-get install -y curl wget git unzip xz-utils zip libglu1-mesa \
      build-essential cmake ninja-build pkg-config libgtk-3-dev \
      liblzma-dev libstdc++6 lib32stdc++6 libc6-i386 libgcc1

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

    # Install Flutter SDK via git
    echo "📱 Installing Flutter ${data.coder_parameter.flutter_version.value}..."
    git clone https://github.com/flutter/flutter.git -b stable /home/coder/flutter

    # Set Flutter PATH
    export PATH="$PATH:/home/coder/flutter/bin"
    echo 'export PATH="$PATH:/home/coder/flutter/bin"' >> ~/.bashrc

    # Run flutter doctor to complete setup
    flutter doctor --android-licenses || true
    flutter precache
    flutter config --no-analytics

    # Install Android SDK and tools for Android development
    if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      echo "🤖 Setting up Android development environment..."

      # Create Android directory structure
      mkdir -p /home/coder/Android/{cmdline-tools,platform-tools,platforms,build-tools,emulator}
      cd /home/coder/Android/cmdline-tools

      # Download and install Android Command Line Tools
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
      echo "no" | avdmanager create avd -n FlutterAVD -k "system-images;android-34;google_apis_playstore;x86_64" --force

      # Configure AVD for better performance
      echo "hw.gpu.enabled=yes" >> ~/.android/avd/FlutterAVD.avd/config.ini
      echo "hw.gpu.mode=host" >> ~/.android/avd/FlutterAVD.avd/config.ini
    fi

    # Install Chrome for Flutter web development
    if [[ "${data.coder_parameter.target_platform.value}" == "web" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      echo "🌐 Setting up Web development environment..."
      wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
      echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
      sudo apt-get update
      sudo apt-get install -y google-chrome-stable

      # Enable Flutter web support
      flutter config --enable-web
    fi

    # Install additional tools for desktop development
    if [[ "${data.coder_parameter.target_platform.value}" == "desktop" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
      echo "🖥️ Setting up Desktop development environment..."
      sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev

      # Enable Flutter desktop support
      flutter config --enable-linux-desktop
      flutter config --enable-windows-desktop
      flutter config --enable-macos-desktop
    fi

    # Install VS Code
    echo "💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install VS Code extensions for Flutter development
    echo "🔌 Installing VS Code extensions..."
    code --install-extension Dart-Code.flutter
    code --install-extension Dart-Code.dart-code
    code --install-extension ms-vscode.vscode-json
    code --install-extension GitHub.copilot
    code --install-extension ms-vscode.hexeditor
    code --install-extension formulahendry.auto-rename-tag
    code --install-extension bradlc.vscode-tailwindcss
    code --install-extension esbenp.prettier-vscode
    code --install-extension usernamehw.errorlens
    code --install-extension alefragnani.Bookmarks

    # Install Android Studio command line tools (optional for advanced users)
    echo "🏗️ Installing Android Studio command line tools..."
    sudo apt-get install -y libc6:i386 libncurses5:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386

    # Install additional useful tools
    sudo apt-get install -y htop tree jq imagemagick ffmpeg

    # Install Docker for containerized builds
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Create Flutter project
    cd /home/coder
    echo "🏗️ Creating Flutter project..."

    # Create Flutter app with specified configuration
    flutter create flutter_app \
      --project-name flutter_app \
      --org com.example.flutter \
      --platforms ${data.coder_parameter.target_platform.value == "all" ? "android,ios,web,linux,windows,macos" : data.coder_parameter.target_platform.value}

    cd flutter_app

    # Add commonly used Flutter packages
    flutter pub add http provider shared_preferences
    flutter pub add path_provider sqflite
    flutter pub add flutter_bloc bloc
    flutter pub add go_router
    flutter pub add cached_network_image
    flutter pub add flutter_secure_storage
    flutter pub add connectivity_plus
    flutter pub add device_info_plus
    flutter pub add package_info_plus

    # Add dev dependencies
    flutter pub add --dev flutter_test mockito build_runner json_annotation json_serializable
    flutter pub add --dev flutter_launcher_icons flutter_native_splash
    flutter pub add --dev very_good_analysis

    # Create project structure
    mkdir -p lib/{core,features,shared}
    mkdir -p lib/core/{constants,errors,network,utils}
    mkdir -p lib/features/{auth,home,profile}
    mkdir -p lib/shared/{models,widgets,services}
    mkdir -p assets/{images,icons,fonts}
    mkdir -p test/{unit,widget,integration}

    # Create core constants
    cat > lib/core/constants/app_constants.dart << 'EOF'
class AppConstants {
  static const String appName = 'Flutter App';
  static const String appVersion = '1.0.0';
  static const String baseUrl = 'https://api.example.com';

  // API endpoints
  static const String apiAuth = '/auth';
  static const String apiUser = '/user';
  static const String apiData = '/data';

  // Storage keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserData = 'user_data';

  // App settings
  static const Duration apiTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
}
EOF

    # Create error handling
    cat > lib/core/errors/exceptions.dart << 'EOF'
class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException({
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'ServerException: $message (Status: $statusCode)';
}

class CacheException implements Exception {
  final String message;

  const CacheException({required this.message});

  @override
  String toString() => 'CacheException: $message';
}

class NetworkException implements Exception {
  final String message;

  const NetworkException({required this.message});

  @override
  String toString() => 'NetworkException: $message';
}
EOF

    cat > lib/core/errors/failures.dart << 'EOF'
abstract class Failure {
  final String message;
  final int? statusCode;

  const Failure({
    required this.message,
    this.statusCode,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Failure &&
           other.message == message &&
           other.statusCode == statusCode;
  }

  @override
  int get hashCode => message.hashCode ^ statusCode.hashCode;
}

class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    super.statusCode,
  });
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message});
}

class NetworkFailure extends Failure {
  const NetworkFailure({required super.message});
}
EOF

    # Create network service
    cat > lib/core/network/api_service.dart << 'EOF'
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../errors/exceptions.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final http.Client _client = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> get(String endpoint) async {
    return _makeRequest(() => _client.get(
      Uri.parse('$${AppConstants.baseUrl}$$endpoint'),
      headers: await _getHeaders(),
    ));
  }

  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data) async {
    return _makeRequest(() => _client.post(
      Uri.parse('$${AppConstants.baseUrl}$$endpoint'),
      headers: await _getHeaders(),
      body: json.encode(data),
    ));
  }

  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> data) async {
    return _makeRequest(() => _client.put(
      Uri.parse('$${AppConstants.baseUrl}$$endpoint'),
      headers: await _getHeaders(),
      body: json.encode(data),
    ));
  }

  Future<Map<String, dynamic>> delete(String endpoint) async {
    return _makeRequest(() => _client.delete(
      Uri.parse('$${AppConstants.baseUrl}$$endpoint'),
      headers: await _getHeaders(),
    ));
  }

  Future<Map<String, dynamic>> _makeRequest(Future<http.Response> Function() request) async {
    try {
      final response = await request().timeout(AppConstants.apiTimeout);
      return _handleResponse(response);
    } on SocketException {
      throw const NetworkException(message: 'No internet connection');
    } on HttpException {
      throw const NetworkException(message: 'Network error occurred');
    } catch (e) {
      throw ServerException(message: 'Unexpected error: $e');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw ServerException(
        message: 'Request failed with status $${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _storage.read(key: AppConstants.keyAccessToken);
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
EOF

    # Create app theme
    cat > lib/core/theme/app_theme.dart << 'EOF'
import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFF03DAC6);
  static const Color errorColor = Color(0xFFB00020);
  static const Color surfaceColor = Color(0xFFFAFAFA);
  static const Color backgroundColor = Color(0xFFFFFFFF);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
      fillColor: surfaceColor,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
    ),
  );
}
EOF

    # Create app router
    cat > lib/core/router/app_router.dart << 'EOF'
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfilePage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: $${state.location}'),
      ),
    ),
  );
}
EOF

    # Create shared models
    cat > lib/shared/models/user_model.dart << 'EOF'
class UserModel {
  final String id;
  final String name;
  final String email;
  final String? avatar;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatar,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatar: json['avatar'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatar': avatar,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? avatar,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, email: $email)';
  }
}
EOF

    # Create feature pages
    mkdir -p lib/features/home/presentation/pages
    cat > lib/features/home/presentation/pages/home_page.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      body: const Center(
        child: WelcomeWidget(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Welcome to Flutter development!'),
            ),
          );
        },
        child: const Icon(Icons.flutter_dash),
      ),
    );
  }
}

class WelcomeWidget extends StatelessWidget {
  const WelcomeWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.flutter_dash,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Welcome to Flutter!',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your Flutter ${data.coder_parameter.flutter_version.value} development environment is ready.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildStatusIndicator(
            context,
            'Flutter ${data.coder_parameter.flutter_version.value}',
            true,
          ),
          const SizedBox(height: 8),
          _buildStatusIndicator(
            context,
            'Dart ${data.coder_parameter.dart_version.value}',
            true,
          ),
          const SizedBox(height: 8),
          _buildStatusIndicator(
            context,
            'Target: ${data.coder_parameter.target_platform.value}',
            true,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Happy Coding!'),
                  content: const Text('Start building your amazing Flutter app!'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Start Building'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context, String text, bool isActive) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isActive ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
EOF

    mkdir -p lib/features/auth/presentation/pages
    cat > lib/features/auth/presentation/pages/login_page.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: LoginForm(),
        ),
      ),
    );
  }
}

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock),
            ),
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                // Simulate login
                context.go('/home');
              }
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
EOF

    mkdir -p lib/features/profile/presentation/pages
    cat > lib/features/profile/presentation/pages/profile_page.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: ProfileContent(),
        ),
      ),
    );
  }
}

class ProfileContent extends StatelessWidget {
  const ProfileContent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: theme.colorScheme.primary,
          child: Icon(
            Icons.person,
            size: 50,
            color: theme.colorScheme.onPrimary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Flutter Developer',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'developer@example.com',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('Settings'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings tapped')),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Logout'),
          onTap: () => context.go('/login'),
        ),
      ],
    );
  }
}
EOF

    # Update main.dart
    cat > lib/main.dart << 'EOF'
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Flutter App',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: AppRouter.router,
      debugShowCheckedModeBanner: false,
    );
  }
}
EOF

    # Create test files
    cat > test/widget_test.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Welcome to Flutter!'), findsOneWidget);
  });
}
EOF

    # Create VS Code settings
    mkdir -p .vscode
    cat > .vscode/settings.json << 'EOF'
{
  "dart.flutterSdkPath": "/home/coder/flutter",
  "dart.debugExternalPackageLibraries": true,
  "dart.debugSdkLibraries": false,
  "editor.formatOnSave": true,
  "editor.rulers": [80],
  "dart.lineLength": 80,
  "files.associations": {
    "*.dart": "dart"
  },
  "search.exclude": {
    "**/.dart_tool": true,
    "**/build": true,
    "**/.gradle": true,
    "**/android/.gradle": true,
    "**/ios/Pods": true
  },
  "dart.openDevTools": "flutter",
  "dart.previewFlutterUiGuides": true,
  "dart.previewFlutterUiGuidesCustomTracking": true
}
EOF

    cat > .vscode/launch.json << 'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flutter: Run Debug",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart",
      "flutterMode": "debug"
    },
    {
      "name": "Flutter: Run Profile",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart",
      "flutterMode": "profile"
    },
    {
      "name": "Flutter: Run Release",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart",
      "flutterMode": "release"
    }
  ]
}
EOF

    # Create Docker configuration for Flutter builds
    cat > Dockerfile << 'EOF'
FROM cirrusci/flutter:stable

WORKDIR /app

# Copy pubspec files
COPY pubspec.* ./

# Install dependencies
RUN flutter pub get

# Copy source code
COPY . .

# Build the app
RUN flutter build web

# Use nginx to serve the web app
FROM nginx:alpine
COPY --from=0 /app/build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

    # Create development scripts
    mkdir -p scripts
    cat > scripts/setup.sh << 'EOF'
#!/bin/bash

echo "🔧 Setting up Flutter project..."

# Get dependencies
flutter pub get

# Analyze code
flutter analyze

# Run code generation if needed
flutter packages pub run build_runner build --delete-conflicting-outputs

# Run tests
flutter test

echo "✅ Flutter project setup complete!"
EOF

    chmod +x scripts/setup.sh

    cat > scripts/build.sh << 'EOF'
#!/bin/bash

echo "🏗️ Building Flutter app for ${data.coder_parameter.target_platform.value}..."

case "${data.coder_parameter.target_platform.value}" in
  "android")
    flutter build apk --release
    echo "📱 Android APK built: build/app/outputs/flutter-apk/app-release.apk"
    ;;
  "ios")
    flutter build ios --release --no-codesign
    echo "🍎 iOS app built (requires macOS for full build)"
    ;;
  "web")
    flutter build web --release
    echo "🌐 Web app built: build/web/"
    ;;
  "desktop"|"linux")
    flutter build linux --release
    echo "🖥️ Linux app built: build/linux/x64/release/bundle/"
    ;;
  "all")
    flutter build apk --release
    flutter build web --release
    flutter build linux --release
    echo "📦 All platforms built successfully!"
    ;;
esac
EOF

    chmod +x scripts/build.sh

    cat > scripts/run-dev.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Flutter development server..."

# Start Android emulator in background if available
if [[ "${data.coder_parameter.target_platform.value}" == "android" || "${data.coder_parameter.target_platform.value}" == "all" ]]; then
  if command -v emulator &> /dev/null; then
    echo "📱 Starting Android emulator..."
    emulator -avd FlutterAVD -no-audio -no-window &

    # Wait for emulator to boot
    adb wait-for-device
    echo "📱 Android emulator ready"
  fi
fi

# Run Flutter app
case "${data.coder_parameter.target_platform.value}" in
  "web")
    flutter run -d chrome --web-hostname=0.0.0.0 --web-port=3000
    ;;
  "android")
    flutter run
    ;;
  "desktop"|"linux")
    flutter run -d linux
    ;;
  "all")
    echo "Multiple platforms available. Choose your target:"
    flutter devices
    flutter run
    ;;
esac
EOF

    chmod +x scripts/run-dev.sh

    # Update pubspec.yaml with additional configuration
    cat >> pubspec.yaml << 'EOF'

# Custom configuration for Flutter Coder template
flutter_icons:
  android: true
  ios: true
  image_path: "assets/icons/icon.png"
  adaptive_icon_background: "#ffffff"
  adaptive_icon_foreground: "assets/icons/foreground.png"

flutter_native_splash:
  color: "#ffffff"
  image: assets/icons/splash.png
  android_12:
    color: "#ffffff"
    image: assets/icons/splash.png

dev_dependencies:
  very_good_analysis: ^5.1.0

# Assets
flutter:
  assets:
    - assets/images/
    - assets/icons/
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
        - asset: assets/fonts/Roboto-Bold.ttf
          weight: 700
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/flutter_app
    sudo chown -R coder:coder /home/coder/flutter
    sudo chown -R coder:coder /home/coder/Android 2>/dev/null || true

    # Install dependencies
    cd /home/coder/flutter_app
    flutter pub get

    # Generate necessary files
    flutter packages pub run build_runner build --delete-conflicting-outputs || true

    # Run flutter doctor to verify setup
    flutter doctor

    echo "✅ Flutter development environment ready!"
    echo "🎯 Flutter version: ${data.coder_parameter.flutter_version.value}"
    echo "🎯 Dart version: ${data.coder_parameter.dart_version.value}"
    echo "🎯 Target platforms: ${data.coder_parameter.target_platform.value}"
    echo "💻 CPU: ${data.coder_parameter.cpu.value} cores"
    echo "🧠 Memory: ${data.coder_parameter.memory.value}GB"

  EOT

}

# Metadata
resource "coder_metadata" "flutter_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "flutter_version"
    value = data.coder_parameter.flutter_version.value
  }
}

resource "coder_metadata" "dart_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "dart_version"
    value = data.coder_parameter.dart_version.value
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
resource "coder_app" "flutter_dev" {
  agent_id     = coder_agent.main.id
  slug         = "flutter-dev"
  display_name = "Flutter Dev Server"
  url          = "http://localhost:3000"
  icon         = "/icon/flutter.svg"
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
  command      = "code /home/coder/flutter_app"
  share        = "owner"
}

resource "coder_app" "android_emulator" {
  count        = contains(["android", "all"], data.coder_parameter.target_platform.value) ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "android-emulator"
  display_name = "Android Emulator"
  icon         = "/icon/android.svg"
  command      = "emulator -avd FlutterAVD"
  share        = "owner"
}

resource "coder_app" "flutter_inspector" {
  agent_id     = coder_agent.main.id
  slug         = "flutter-inspector"
  display_name = "Flutter Inspector"
  url          = "http://localhost:9100"
  icon         = "/icon/flutter.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:9100"
    interval  = 15
    threshold = 20
  }
}

resource "coder_app" "dart_devtools" {
  agent_id     = coder_agent.main.id
  slug         = "dart-devtools"
  display_name = "Dart DevTools"
  url          = "http://localhost:9200"
  icon         = "/icon/dart.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:9200"
    interval  = 15
    threshold = 20
  }
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
            name  = "FLUTTER_ROOT"
            value = "/home/coder/flutter"
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

          # Expose Flutter development ports
          port {
            container_port = 3000
            name           = "flutter-web"
            protocol       = "TCP"
          }

          port {
            container_port = 8080
            name           = "flutter-debug"
            protocol       = "TCP"
          }

          port {
            container_port = 9100
            name           = "flutter-inspector"
            protocol       = "TCP"
          }

          port {
            container_port = 9200
            name           = "dart-devtools"
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

# Service for Flutter development ports
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
      name        = "flutter-web"
      port        = 3000
      target_port = 3000
      protocol    = "TCP"
    }

    port {
      name        = "flutter-debug"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    port {
      name        = "flutter-inspector"
      port        = 9100
      target_port = 9100
      protocol    = "TCP"
    }

    port {
      name        = "dart-devtools"
      port        = 9200
      target_port = 9200
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}
