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

data "coder_parameter" "dotnet_version" {
  name         = "dotnet_version"
  display_name = ".NET Version"
  description  = ".NET version to install"
  default      = "8.0"
  icon         = "/icon/dotnet.svg"
  mutable      = false
  option {
    name  = ".NET 6.0 LTS"
    value = "6.0"
  }
  option {
    name  = ".NET 8.0 LTS"
    value = "8.0"
  }
}

data "coder_parameter" "project_template" {
  name         = "project_template"
  display_name = "Project Template"
  description  = "Choose .NET project template"
  default      = "webapi"
  icon         = "/icon/api.svg"
  mutable      = false
  option {
    name  = "Web API"
    value = "webapi"
  }
  option {
    name  = "MVC Web App"
    value = "mvc"
  }
  option {
    name  = "Blazor Server"
    value = "blazorserver"
  }
  option {
    name  = "Console App"
    value = "console"
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
    name  = "Rider"
    value = "rider"
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

    echo "💙 Setting up .NET Core development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y wget curl git apt-transport-https

    # Install .NET ${data.coder_parameter.dotnet_version.value}
    echo "📦 Installing .NET ${data.coder_parameter.dotnet_version.value}..."
    wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb

    sudo apt-get update
    sudo apt-get install -y dotnet-sdk-${data.coder_parameter.dotnet_version.value}

    # Install additional development tools
    sudo apt-get install -y \
      build-essential \
      postgresql-client \
      libpq-dev \
      redis-tools \
      htop \
      tree \
      jq \
      unzip

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

        # Install .NET extensions
        code --install-extension ms-dotnettools.csharp
        code --install-extension ms-dotnettools.vscode-dotnet-runtime
        code --install-extension formulahendry.dotnet-test-explorer
        code --install-extension kreativ-software.csharpextensions
        code --install-extension ms-vscode.vscode-json
        ;;
      "rider")
        echo "🧠 Installing JetBrains Rider..."
        wget -q https://download.jetbrains.com/rider/JetBrains.Rider-2023.3.2.tar.gz -O /tmp/rider.tar.gz
        sudo tar -xzf /tmp/rider.tar.gz -C /opt
        sudo ln -sf /opt/JetBrains\ Rider-*/bin/rider.sh /usr/local/bin/rider
        rm /tmp/rider.tar.gz
        ;;
    esac

    # Create .NET project
    echo "🏗️ Creating .NET ${data.coder_parameter.project_template.value} project..."
    cd /home/coder

    case "${data.coder_parameter.project_template.value}" in
      "webapi")
        dotnet new webapi -n DotNetApi --use-controllers
        cd DotNetApi

        # Add useful NuGet packages
        dotnet add package Microsoft.EntityFrameworkCore.Design
        dotnet add package Microsoft.EntityFrameworkCore.SqlServer
        dotnet add package Microsoft.EntityFrameworkCore.Tools
        dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
        dotnet add package Swashbuckle.AspNetCore
        dotnet add package Serilog.AspNetCore
        dotnet add package AutoMapper.Extensions.Microsoft.DependencyInjection
        ;;
      "mvc")
        dotnet new mvc -n DotNetMvc
        cd DotNetMvc

        dotnet add package Microsoft.EntityFrameworkCore.Design
        dotnet add package Microsoft.EntityFrameworkCore.SqlServer
        dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
        dotnet add package Microsoft.AspNetCore.Identity.EntityFrameworkCore
        ;;
      "blazorserver")
        dotnet new blazorserver -n DotNetBlazor
        cd DotNetBlazor

        dotnet add package Microsoft.EntityFrameworkCore.Design
        dotnet add package Microsoft.EntityFrameworkCore.SqlServer
        dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
        ;;
      "console")
        dotnet new console -n DotNetConsole
        cd DotNetConsole

        dotnet add package Microsoft.Extensions.Hosting
        dotnet add package Microsoft.Extensions.DependencyInjection
        dotnet add package Microsoft.Extensions.Configuration
        ;;
    esac

    PROJECT_DIR=$(pwd)
    PROJECT_NAME=$(basename "$PROJECT_DIR")

    # Add development packages for API projects
    if [[ "${data.coder_parameter.project_template.value}" == "webapi" ]]; then
      # Create Models
      mkdir -p Models
      cat > Models/User.cs << 'EOF'
using System.ComponentModel.DataAnnotations;

namespace DotNetApi.Models;

public class User
{
    public int Id { get; set; }

    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [EmailAddress]
    public string Email { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
EOF

      # Create DTOs
      mkdir -p DTOs
      cat > DTOs/CreateUserDto.cs << 'EOF'
using System.ComponentModel.DataAnnotations;

namespace DotNetApi.DTOs;

public class CreateUserDto
{
    [Required]
    [MaxLength(100)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [EmailAddress]
    public string Email { get; set; } = string.Empty;
}
EOF

      cat > DTOs/ApiResponse.cs << 'EOF'
namespace DotNetApi.DTOs;

public class ApiResponse<T>
{
    public string Status { get; set; } = string.Empty;
    public T? Data { get; set; }
    public string? Message { get; set; }

    public static ApiResponse<T> Success(T data, string? message = null)
    {
        return new ApiResponse<T>
        {
            Status = "success",
            Data = data,
            Message = message
        };
    }

    public static ApiResponse<object> Error(string message)
    {
        return new ApiResponse<object>
        {
            Status = "error",
            Data = null,
            Message = message
        };
    }
}
EOF

      # Create DbContext
      mkdir -p Data
      cat > Data/ApplicationDbContext.cs << 'EOF'
using Microsoft.EntityFrameworkCore;
using DotNetApi.Models;

namespace DotNetApi.Data;

public class ApplicationDbContext : DbContext
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Email).IsUnique();
            entity.Property(e => e.CreatedAt).HasDefaultValueSql("GETUTCDATE()");
        });
    }
}
EOF

      # Create Controller
      cat > Controllers/UsersController.cs << 'EOF'
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DotNetApi.Data;
using DotNetApi.Models;
using DotNetApi.DTOs;

namespace DotNetApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly ApplicationDbContext _context;
    private readonly ILogger<UsersController> _logger;

    public UsersController(ApplicationDbContext context, ILogger<UsersController> logger)
    {
        _context = context;
        _logger = logger;
    }

    [HttpGet]
    public async Task<ActionResult<ApiResponse<IEnumerable<User>>>> GetUsers()
    {
        try
        {
            var users = await _context.Users.OrderByDescending(u => u.CreatedAt).ToListAsync();
            return Ok(ApiResponse<IEnumerable<User>>.Success(users));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching users");
            return StatusCode(500, ApiResponse<object>.Error("Internal server error"));
        }
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<ApiResponse<User>>> GetUser(int id)
    {
        try
        {
            var user = await _context.Users.FindAsync(id);
            if (user == null)
            {
                return NotFound(ApiResponse<object>.Error("User not found"));
            }

            return Ok(ApiResponse<User>.Success(user));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching user {UserId}", id);
            return StatusCode(500, ApiResponse<object>.Error("Internal server error"));
        }
    }

    [HttpPost]
    public async Task<ActionResult<ApiResponse<User>>> CreateUser(CreateUserDto dto)
    {
        try
        {
            var user = new User
            {
                Name = dto.Name,
                Email = dto.Email
            };

            _context.Users.Add(user);
            await _context.SaveChangesAsync();

            return CreatedAtAction(nameof(GetUser), new { id = user.Id },
                ApiResponse<User>.Success(user, "User created successfully"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating user");
            return StatusCode(500, ApiResponse<object>.Error("Internal server error"));
        }
    }

    [HttpDelete("{id}")]
    public async Task<ActionResult<ApiResponse<object>>> DeleteUser(int id)
    {
        try
        {
            var user = await _context.Users.FindAsync(id);
            if (user == null)
            {
                return NotFound(ApiResponse<object>.Error("User not found"));
            }

            _context.Users.Remove(user);
            await _context.SaveChangesAsync();

            return Ok(ApiResponse<object>.Success(null, "User deleted successfully"));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting user {UserId}", id);
            return StatusCode(500, ApiResponse<object>.Error("Internal server error"));
        }
    }
}
EOF

      # Update Program.cs
      cat > Program.cs << 'EOF'
using Microsoft.EntityFrameworkCore;
using DotNetApi.Data;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Add Entity Framework
builder.Services.AddDbContext<ApplicationDbContext>(options =>
{
    var connectionString = builder.Configuration.GetConnectionString("DefaultConnection")
        ?? "Server=localhost;Database=DotNetApiDb;Trusted_Connection=true;TrustServerCertificate=true;";
    options.UseSqlServer(connectionString);
});

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", builder =>
    {
        builder.AllowAnyOrigin()
               .AllowAnyMethod()
               .AllowAnyHeader();
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseCors("AllowAll");
app.UseAuthorization();

// Add health check endpoint
app.MapGet("/health", () => new
{
    Status = "success",
    Message = ".NET API is running!",
    Timestamp = DateTime.UtcNow,
    Version = "1.0.0"
});

app.MapControllers();

// Ensure database is created
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
    context.Database.EnsureCreated();
}

app.Run();
EOF
    fi

    # Create appsettings.json
    cat > appsettings.json << 'EOF'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=dotnet_db;Username=postgres;Password=password"
  }
}
EOF

    cat > appsettings.Development.json << 'EOF'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore.Database.Command": "Information"
    }
  },
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Database=dotnet_db;Username=postgres;Password=password"
  }
}
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["*.csproj", "./"]
RUN dotnet restore
COPY . .
RUN dotnet build -c Release -o /app/build

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS publish
WORKDIR /src
COPY --from=build /src .
RUN dotnet publish -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=publish /app/publish .
EXPOSE 80
EXPOSE 443
ENTRYPOINT ["dotnet", "$(PROJECT_NAME).dll"]
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app:
    build: .
    ports:
      - "5000:80"
      - "5001:443"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ConnectionStrings__DefaultConnection=Host=postgres;Database=dotnet_db;Username=postgres;Password=password
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: dotnet_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  postgres_data:
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
bin/
obj/
*.user
*.suo
*.cache
*.docx
.vs/
.vscode/
wwwroot/dist/
ClientApp/dist/
**/node_modules/
appsettings.Development.json
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder/$PROJECT_NAME

    # Build and restore packages
    cd /home/coder/$PROJECT_NAME
    dotnet restore
    dotnet build

    echo "✅ .NET Core development environment ready!"
    echo "Run 'dotnet run' to start the development server"

  EOT

}

# Metadata
resource "coder_metadata" "dotnet_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "dotnet_version"
    value = data.coder_parameter.dotnet_version.value
  }
}

resource "coder_metadata" "project_template" {
  resource_id = coder_agent.main.id
  item {
    key   = "project_template"
    value = data.coder_parameter.project_template.value
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
resource "coder_app" "dotnet_app" {
  agent_id     = coder_agent.main.id
  slug         = "dotnet-app"
  display_name = ".NET Application"
  url          = "http://localhost:5000"
  icon         = "/icon/dotnet.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:5000/health"
    interval  = 10
    threshold = 15
  }
}

resource "coder_app" "swagger" {
  count        = data.coder_parameter.project_template.value == "webapi" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "swagger"
  display_name = "Swagger UI"
  url          = "http://localhost:5000/swagger"
  icon         = "/icon/swagger.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "vscode" {
  count        = data.coder_parameter.ide.value == "vscode" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder"
  share        = "owner"
}

resource "coder_app" "rider" {
  count        = data.coder_parameter.ide.value == "rider" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "rider"
  display_name = "JetBrains Rider"
  icon         = "/icon/rider.svg"
  command      = "rider /home/coder"
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
