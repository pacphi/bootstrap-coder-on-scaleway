# Architecture Documentation

This document provides a comprehensive overview of the Bootstrap Coder on Scaleway system architecture, including the **two-phase deployment strategy**, component relationships, CI/CD workflows, deployment flows, management scripts, hooks framework, and integration patterns with advanced GitHub Actions automation.

## System Overview

The Bootstrap Coder on Scaleway system is a multi-tier architecture designed for production-ready development environments with a **two-phase deployment strategy**. It combines infrastructure automation, platform orchestration, and workspace templating to deliver scalable development platforms with enhanced reliability and troubleshooting capabilities.

```mermaid
graph TB
    subgraph "Management Layer"
        Scripts[Setup/Teardown Scripts]
        CostCalc[Cost Calculator]
        ResourceTracker[Resource Tracker]
        Validation[Validation Scripts]
        TestRunner[Test Runner]
        Backup[Backup System]
        Scale[Dynamic Scaling]
        Hooks[Hooks Framework]
        GitHub[GitHub Actions CI/CD]
    end

    subgraph "Platform Layer"
        Coder[Coder Server]
        OAuth[OAuth Integration]
        Workspaces[User Workspaces]
        Templates[Workspace Templates]
    end

    subgraph "Infrastructure Layer"
        K8s[Scaleway Kapsule]
        PostgreSQL[Managed PostgreSQL]
        LoadBalancer[Load Balancer]
        Network[VPC & Security Groups]
    end

    subgraph "Template Categories"
        Backend[Backend Templates]
        Frontend[Frontend Templates]
        AI[AI-Enhanced Templates]
        DevOps[DevOps Templates]
        Mobile[Mobile Templates]
        DataML[Data/ML Templates]
    end

    Scripts --> Coder
    Coder --> K8s
    Coder --> PostgreSQL
    Templates --> Workspaces
    Workspaces --> K8s
    LoadBalancer --> Coder
    Network --> K8s
    Network --> PostgreSQL
```

## Two-Phase Deployment Strategy

### Architecture Benefits

The system implements a **two-phase deployment approach** that provides significant advantages over monolithic deployment:

```mermaid
graph LR
    subgraph "Phase 1: Infrastructure"
        InfraStart[Start Infrastructure Deployment]
        Cluster[Deploy Kubernetes Cluster]
        Database[Provision PostgreSQL]
        Networking[Configure VPC & Security]
        KubeconfigReady[Upload Kubeconfig Artifact]
    end

    subgraph "Phase 2: Coder Application"
        CoderStart[Start Coder Deployment]
        RemoteState[Read Infrastructure State]
        ValidateStorage[Validate Storage Classes]
        DeployCoder[Deploy Coder Platform]
        DeployTemplates[Deploy Workspace Templates]
    end

    InfraStart --> Cluster
    Cluster --> Database
    Database --> Networking
    Networking --> KubeconfigReady

    KubeconfigReady --> CoderStart
    CoderStart --> RemoteState
    RemoteState --> ValidateStorage
    ValidateStorage --> DeployCoder
    DeployCoder --> DeployTemplates
```

### Key Advantages

1. **Enhanced Reliability**: Infrastructure failures don't prevent cluster access for troubleshooting
2. **Better Separation of Concerns**: Clear boundaries between infrastructure and application deployment
3. **Independent Retry Capability**: Failed Coder deployments can be retried without rebuilding infrastructure
4. **Immediate Troubleshooting Access**: Kubeconfig available immediately after Phase 1 completion
5. **Cleaner State Management**: Separate Terraform state files for infrastructure and application components

### Environment Structure

```
environments/
├── dev/
│   ├── infra/          # Phase 1: Infrastructure components
│   │   ├── main.tf     # Cluster, database, networking, security
│   │   ├── providers.tf # S3 backend: key="infra/terraform.tfstate"
│   │   └── outputs.tf  # Infrastructure outputs for Phase 2
│   └── coder/          # Phase 2: Coder application
│       ├── main.tf     # Coder deployment with remote state data source
│       ├── providers.tf # S3 backend: key="coder/terraform.tfstate"
│       └── outputs.tf  # Coder application outputs
├── staging/
│   ├── infra/
│   └── coder/
└── prod/
    ├── infra/
    └── coder/
```

## CI/CD & GitHub Actions Architecture

### GitHub Actions Workflow Architecture

```mermaid
graph TB
    subgraph "GitHub Repository"
        Code[Source Code]
        Workflows[.github/workflows/]
        Secrets[Repository Secrets]
        Environments[Environment Protection]
    end

    subgraph "Workflow Types"
        Deploy[deploy-environment.yml<br/>Complete Two-Phase Deployment]
        InfraDeploy[deploy-infrastructure.yml<br/>Phase 1: Infrastructure Only]
        CoderDeploy[deploy-coder.yml<br/>Phase 2: Coder Application]
        Teardown[teardown-environment.yml<br/>Two-Phase Teardown]
        Validate[validate-templates.yml]
    end

    subgraph "Execution Environment"
        Runner[GitHub Runner]
        Tools[CLI Tools<br/>• Terraform<br/>• kubectl<br/>• Helm]
        Scripts[Project Scripts]
    end

    subgraph "Target Infrastructure"
        ScalewayAPI[Scaleway API]
        K8sCluster[Kubernetes Cluster]
        CoderInstance[Coder Instance]
    end

    subgraph "Notifications"
        Slack[Slack Notifications]
        Email[Email Reports]
        GitHub[GitHub Status]
    end

    Code --> Workflows
    Workflows --> Deploy
    Workflows --> Teardown
    Workflows --> Validate

    Deploy --> Runner
    Teardown --> Runner
    Validate --> Runner

    Runner --> Tools
    Tools --> Scripts

    Scripts --> ScalewayAPI
    Scripts --> K8sCluster
    Scripts --> CoderInstance

    Scripts --> Slack
    Scripts --> Email
    Scripts --> GitHub
```

### CI/CD Pipeline Flow

```mermaid
flowchart TD
    subgraph "Triggers"
        Manual[Manual Dispatch]
        Push[Push to Branch]
        PR[Pull Request]
        Schedule[Scheduled]
    end

    subgraph "Pre-Deployment"
        Validation[Template Validation]
        CostCheck[Cost Estimation]
        Security[Security Scan]
        Prerequisites[Prereq Check]
    end

    subgraph "Deployment Phase"
        Infrastructure[Infrastructure]
        Platform[Platform Setup]
        Templates[Template Deploy]
        Monitoring[Monitor Setup]
    end

    subgraph "Post-Deployment"
        HealthCheck[Health Validation]
        Integration[Integration Tests]
        Backup[Initial Backup]
        Notification[Notifications]
    end

    subgraph "Environments"
        Dev[Development]
        Staging[Staging]
        Prod[Production]
    end

    Manual --> Validation
    Push --> Validation
    PR --> Validation
    Schedule --> Validation

    Validation --> CostCheck
    CostCheck --> Security
    Security --> Prerequisites

    Prerequisites --> Infrastructure
    Infrastructure --> Platform
    Platform --> Templates
    Templates --> Monitoring

    Monitoring --> HealthCheck
    HealthCheck --> Integration
    Integration --> Backup
    Backup --> Notification

    Notification --> Dev
    Notification --> Staging
    Notification --> Prod
```

## Infrastructure Architecture

### Scaleway Resource Topology

```mermaid
graph TB
    subgraph "Scaleway Cloud"
        subgraph "VPC Network"
            PrivateNet[Private Network]
            SecurityGroups[Security Groups]
        end

        subgraph "Compute"
            Kapsule[Kapsule Cluster]
            NodePools[Node Pools]
        end

        subgraph "Database"
            PostgreSQL[Managed PostgreSQL]
            Backups[Automated Backups]
        end

        subgraph "Networking"
            LB[Load Balancer]
            SSL[SSL Certificates]
        end

        subgraph "Storage"
            BlockStorage[Block Storage]
            PV[Persistent Volumes]
        end
    end

    Internet --> LB
    LB --> Kapsule
    Kapsule --> PrivateNet
    PostgreSQL --> PrivateNet
    Kapsule --> BlockStorage
    BlockStorage --> PV
    SecurityGroups --> Kapsule
    SecurityGroups --> PostgreSQL
```

### Multi-Environment Configuration

| Environment | Nodes | CPU/Node | RAM/Node | Database | Monthly Cost |
|-------------|-------|----------|-----------|----------|--------------|
| Development | 2 | 1 vCPU | 2GB | DB-DEV-S | €53.70 |
| Staging | 3 | 2 vCPU | 4GB | DB-GP-S | €97.85 |
| Production | 5 | 4 vCPU | 8GB | DB-GP-M HA | €374.50 |

## Deployment Flow Architecture

### DevOps Deployment Sequence

```mermaid
sequenceDiagram
    participant DevOps as DevOps Engineer
    participant SetupScript as Setup Script
    participant Terraform as Terraform
    participant Scaleway as Scaleway API
    participant K8s as Kubernetes
    participant Coder as Coder Server
    participant Template as Template System

    DevOps->>SetupScript: ./setup.sh --env=prod --template=java-spring
    SetupScript->>SetupScript: Validate prerequisites
    SetupScript->>SetupScript: Check Scaleway credentials
    SetupScript->>SetupScript: Calculate costs & confirm budget

    SetupScript->>Terraform: terraform plan
    Terraform->>Scaleway: Plan infrastructure changes
    Scaleway-->>Terraform: Return planned resources
    Terraform-->>SetupScript: Show deployment plan

    SetupScript->>DevOps: Request approval for €374.50/month
    DevOps->>SetupScript: Approve deployment

    SetupScript->>Terraform: terraform apply
    Terraform->>Scaleway: Create VPC & Security Groups
    Terraform->>Scaleway: Create Kapsule cluster
    Terraform->>Scaleway: Create PostgreSQL instance
    Terraform->>Scaleway: Create Load Balancer

    Terraform->>K8s: Deploy Coder server
    Terraform->>K8s: Configure RBAC & Network Policies
    Terraform->>K8s: Set up monitoring stack

    K8s->>Coder: Start Coder server
    Coder->>Template: Load workspace templates

    SetupScript->>DevOps: Environment ready at https://coder.example.com
```

### Developer Workflow Sequence

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant CoderUI as Coder Web UI
    participant K8s as Kubernetes
    participant Template as Template Engine
    participant Workspace as Development Workspace
    participant ClaudeFlow as Claude Code Flow

    Dev->>CoderUI: Login with OAuth
    CoderUI->>Dev: Show available templates

    Dev->>CoderUI: Select "Python Django + CrewAI" template
    CoderUI->>Template: Request workspace creation

    Template->>K8s: Create workspace pod
    K8s->>Workspace: Initialize container with:
    Note over Workspace: - Python 3.11 + Django 4.2<br/>- CrewAI framework<br/>- PostgreSQL client<br/>- VS Code + extensions<br/>- Claude Code CLI

    Workspace->>ClaudeFlow: Initialize AI environment
    ClaudeFlow->>Workspace: Load 87 MCP tools
    ClaudeFlow->>Workspace: Configure swarm/hive-mind modes

    K8s-->>CoderUI: Workspace ready
    CoderUI->>Dev: Provide workspace URL + credentials

    Dev->>Workspace: Access via VS Code or web terminal
    Dev->>ClaudeFlow: Start AI-assisted development

    loop Development Cycle
        Dev->>Workspace: Write code with AI assistance
        Workspace->>ClaudeFlow: Request code generation/review
        ClaudeFlow->>Workspace: Provide intelligent suggestions
        Workspace->>K8s: Auto-save to persistent volume
    end
```

## Two-Phase Module Dependency Architecture

### Terraform Module Relationships

```mermaid
graph TB
    subgraph "Environment Configurations"
        subgraph "Development"
            DevInfra[environments/dev/infra/main.tf]
            DevCoder[environments/dev/coder/main.tf]
        end
        subgraph "Staging"
            StagingInfra[environments/staging/infra/main.tf]
            StagingCoder[environments/staging/coder/main.tf]
        end
        subgraph "Production"
            ProdInfra[environments/prod/infra/main.tf]
            ProdCoder[environments/prod/coder/main.tf]
        end
    end

    subgraph "Shared Resources"
        SharedVars[shared/variables.tf]
        SharedLocals[shared/locals.tf]
        SharedProviders[shared/providers.tf]
    end

    subgraph "Infrastructure Modules (Phase 1)"
        Networking[modules/networking]
        Cluster[modules/scaleway-cluster]
        Database[modules/postgresql]
        Security[modules/security]
    end

    subgraph "Application Modules (Phase 2)"
        CoderDeploy[modules/coder-deployment]
        RemoteState[terraform_remote_state.infra]
    end

    subgraph "Template System"
        BackendTemplates[templates/backend/*]
        FrontendTemplates[templates/frontend/*]
        AITemplates[templates/ai-enhanced/*]
        DevOpsTemplates[templates/devops/*]
        MobileTemplates[templates/mobile/*]
        DataMLTemplates[templates/data-ml/*]
    end

    DevInfra --> SharedVars
    StagingInfra --> SharedVars
    ProdInfra --> SharedVars

    DevInfra --> Networking
    DevInfra --> Cluster
    DevInfra --> Database
    DevInfra --> Security

    DevCoder --> RemoteState
    DevCoder --> CoderDeploy
    RemoteState -.->|"Reads infra outputs"| DevInfra

    Networking --> Cluster
    Networking --> Database
    Security --> Cluster

    CoderDeploy --> BackendTemplates
    CoderDeploy --> FrontendTemplates
    CoderDeploy --> AITemplates
    CoderDeploy --> DevOpsTemplates
    CoderDeploy --> MobileTemplates
    CoderDeploy --> DataMLTemplates
```

### Two-Phase Module Input/Output Flow

```mermaid
flowchart TD
    subgraph "Phase 1: Infrastructure Modules"
        subgraph "Networking Module"
            NetIn[Inputs:<br/>• region<br/>• environment<br/>• cidr_block]
            NetOut[Outputs:<br/>• vpc_id<br/>• private_network_id<br/>• security_group_ids]
        end

        subgraph "Cluster Module"
            ClusterIn[Inputs:<br/>• vpc_id<br/>• private_network_id<br/>• node_type<br/>• node_count]
            ClusterOut[Outputs:<br/>• cluster_id<br/>• kubeconfig<br/>• cluster_endpoint]
        end

        subgraph "PostgreSQL Module"
            DBIn[Inputs:<br/>• vpc_id<br/>• private_network_id<br/>• instance_type<br/>• backup_retention]
            DBOut[Outputs:<br/>• database_host<br/>• database_port<br/>• connection_string]
        end
    end

    subgraph "Remote State Bridge"
        S3Backend[S3 Backend Storage<br/>infra/terraform.tfstate]
        RemoteStateData[Remote State Data Source<br/>Reads infra outputs]
    end

    subgraph "Phase 2: Application Module"
        subgraph "Coder Module"
            CoderIn[Inputs (from remote state):<br/>• cluster_endpoint<br/>• database_host<br/>• kubeconfig<br/>• domain_name<br/>• oauth_config]
            CoderOut[Outputs:<br/>• coder_url<br/>• admin_credentials<br/>• workspace_templates]
        end
    end

    NetOut --> ClusterIn
    NetOut --> DBIn
    ClusterOut --> S3Backend
    DBOut --> S3Backend
    NetOut --> S3Backend

    S3Backend --> RemoteStateData
    RemoteStateData --> CoderIn
```

## Security Architecture

### Security Boundaries and Controls

```mermaid
graph TB
    subgraph "Internet"
        Users[End Users]
        Admins[System Administrators]
    end

    subgraph "Edge Security"
        LB[Load Balancer + WAF]
        SSL[TLS 1.3 Termination]
        RateLimit[Rate Limiting]
    end

    subgraph "Network Security"
        VPC[Private VPC]
        SecurityGroups[Security Groups]
        NetworkPolicies[K8s Network Policies]
    end

    subgraph "Kubernetes Security"
        subgraph "Pod Security"
            PSS[Pod Security Standards]
            SecurityContext[Security Context]
            NonRoot[Non-root Containers]
        end

        subgraph "Access Control"
            RBAC[Role-Based Access Control]
            ServiceAccounts[Service Accounts]
            Secrets[Encrypted Secrets]
        end

        subgraph "Resource Control"
            ResourceQuotas[Resource Quotas]
            LimitRanges[Limit Ranges]
            PodDisruption[Pod Disruption Budgets]
        end
    end

    subgraph "Application Security"
        CoderAuth[Coder Authentication]
        OAuth2[OAuth2 Integration]
        WorkspaceIsolation[Workspace Isolation]
    end

    Users --> LB
    Admins --> LB
    LB --> SSL
    SSL --> VPC
    VPC --> SecurityGroups
    SecurityGroups --> NetworkPolicies
    NetworkPolicies --> PSS
    NetworkPolicies --> RBAC
    NetworkPolicies --> ResourceQuotas
    RBAC --> CoderAuth
    CoderAuth --> OAuth2
    OAuth2 --> WorkspaceIsolation
```

### RBAC Configuration

```mermaid
graph LR
    subgraph "Service Accounts"
        CoderSA[coder-service-account]
        WorkspaceSA[workspace-service-account]
        MonitoringSA[monitoring-service-account]
    end

    subgraph "Cluster Roles"
        CoderClusterRole[coder-cluster-role]
        WorkspaceRole[workspace-role]
        MonitoringRole[monitoring-role]
    end

    subgraph "Permissions"
        PodManagement[Pod Create/Delete/List]
        ServiceManagement[Service Create/Update]
        SecretAccess[Secret Read/Write]
        MetricsRead[Metrics Read-Only]
    end

    CoderSA --> CoderClusterRole
    WorkspaceSA --> WorkspaceRole
    MonitoringSA --> MonitoringRole

    CoderClusterRole --> PodManagement
    CoderClusterRole --> ServiceManagement
    CoderClusterRole --> SecretAccess

    WorkspaceRole --> PodManagement
    MonitoringRole --> MetricsRead
```

## Template System Architecture

### Template Categories and Relationships

```mermaid
graph TB
    subgraph "Template Categories"
        subgraph "Backend (7 templates)"
            JavaSpring[Java Spring Boot]
            PythonDjango[Python Django + CrewAI]
            GoFiber[Go Fiber]
            RubyRails[Ruby on Rails]
            PHPSymfony[PHP Symfony]
            RustActix[Rust Actix Web]
            DotNetCore[.NET Core]
        end

        subgraph "Frontend (4 templates)"
            ReactTS[React + TypeScript]
            Angular[Angular]
            VueNuxt[Vue.js + Nuxt]
            SvelteKit[Svelte Kit]
        end

        subgraph "AI-Enhanced (2 templates)"
            ClaudeFlowBase[Claude Flow Base]
            ClaudeFlowEnt[Claude Flow Enterprise]
        end

        subgraph "DevOps (3 templates)"
            DockerCompose[Docker Compose]
            K8sHelm[Kubernetes + Helm]
            TerraformAnsible[Terraform + Ansible]
        end

        subgraph "Data/ML (2 templates)"
            JupyterPython[Jupyter + Python]
            RStudio[R Studio]
        end

        subgraph "Mobile (3 templates)"
            Flutter[Flutter]
            ReactNative[React Native]
            Ionic[Ionic]
        end
    end

    subgraph "Template Engine"
        TemplateProcessor[Template Processor]
        ResourceAllocation[Resource Allocation]
        ImageBuilder[Container Image Builder]
        VolumeProvisioning[Volume Provisioning]
    end

    subgraph "Runtime Environment"
        K8sPods[Kubernetes Pods]
        PersistentVolumes[Persistent Volumes]
        NetworkServices[Network Services]
        Monitoring[Monitoring Integration]
    end

    JavaSpring --> TemplateProcessor
    PythonDjango --> TemplateProcessor
    ReactTS --> TemplateProcessor
    ClaudeFlowBase --> TemplateProcessor

    TemplateProcessor --> ResourceAllocation
    TemplateProcessor --> ImageBuilder
    TemplateProcessor --> VolumeProvisioning

    ResourceAllocation --> K8sPods
    ImageBuilder --> K8sPods
    VolumeProvisioning --> PersistentVolumes
    K8sPods --> NetworkServices
    K8sPods --> Monitoring
```

### Template Configuration Flow

```mermaid
sequenceDiagram
    participant User as User
    participant Coder as Coder Server
    participant Template as Template Engine
    participant K8s as Kubernetes API
    participant Registry as Container Registry
    participant Storage as Persistent Storage

    User->>Coder: Select "Python Django + CrewAI" template
    Coder->>Template: Process template configuration

    Template->>Template: Parse template variables:
    Note over Template: - Python version: 3.11<br/>- Django version: 4.2<br/>- CPU: 2 cores<br/>- Memory: 4GB<br/>- Storage: 20GB

    Template->>Registry: Pull base Ubuntu 22.04 image
    Template->>K8s: Create ConfigMap with setup scripts
    Template->>Storage: Provision 20GB PVC

    Template->>K8s: Create Pod with:
    Note over K8s: spec:<br/>  containers:<br/>  - image: ubuntu:22.04<br/>    resources:<br/>      requests: {cpu: 2, memory: 4Gi}<br/>    volumeMounts:<br/>    - mountPath: /home/coder<br/>      name: workspace-storage

    K8s->>Template: Pod created successfully
    Template->>Coder: Workspace ready
    Coder->>User: Provide access URL + credentials
```

## Claude Code Flow Integration

### AI-Enhanced Development Architecture

```mermaid
graph TB
    subgraph "Claude Code Flow Environment"
        subgraph "MCP Tools (87 total)"
            FileOps[File Operations]
            GitOps[Git Integration]
            DockerOps[Docker Management]
            K8sOps[Kubernetes Operations]
            AITools[AI-Specific Tools]
            WebTools[Web Scraping & APIs]
        end

        subgraph "Operating Modes"
            SwarmMode[Swarm Mode<br/>Quick Tasks]
            HiveMindMode[Hive-Mind Mode<br/>Complex Projects]
        end

        subgraph "Development Stacks"
            FullStack[Full Stack<br/>Node.js + Python + Go]
            PythonAI[Python AI/ML<br/>TensorFlow + PyTorch]
            JSStack[JavaScript/TypeScript<br/>React + Node.js]
            SystemsStack[Go + Rust<br/>Systems Programming]
        end
    end

    subgraph "Integration Points"
        VSCode[VS Code Extensions]
        Terminal[Enhanced Terminal]
        Jupyter[Jupyter Integration]
        GitIntegration[Git Workflows]
    end

    subgraph "AI Capabilities"
        CodeGeneration[Code Generation]
        CodeReview[Automated Review]
        Documentation[Auto Documentation]
        Testing[Test Generation]
        Optimization[Performance Optimization]
    end

    SwarmMode --> FileOps
    SwarmMode --> GitOps
    HiveMindMode --> AITools
    HiveMindMode --> K8sOps

    FullStack --> VSCode
    PythonAI --> Jupyter
    JSStack --> Terminal
    SystemsStack --> GitIntegration

    VSCode --> CodeGeneration
    Terminal --> CodeReview
    Jupyter --> Documentation
    GitIntegration --> Testing
```

### AI-Assisted Development Workflow

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Workspace as Workspace Environment
    participant ClaudeFlow as Claude Code Flow
    participant MCP as MCP Tools
    participant AI as AI Engine
    participant Git as Git Repository

    Dev->>Workspace: Start new project
    Workspace->>ClaudeFlow: Initialize AI environment
    ClaudeFlow->>MCP: Load 87 MCP tools
    MCP-->>ClaudeFlow: Tools ready

    Dev->>ClaudeFlow: "Create a Django REST API for user management"
    ClaudeFlow->>AI: Process request in hive-mind mode
    AI->>MCP: Use file operations + code generation
    MCP->>Workspace: Generate project structure
    MCP->>Workspace: Create Django models, views, serializers
    MCP->>Workspace: Generate tests and documentation

    ClaudeFlow->>Dev: Show generated code with explanations
    Dev->>ClaudeFlow: "Add authentication and permissions"
    ClaudeFlow->>AI: Enhance existing code
    AI->>MCP: Modify files + add security features
    MCP->>Workspace: Update code with auth integration

    ClaudeFlow->>Git: Auto-commit with descriptive messages
    ClaudeFlow->>Dev: Provide next steps and optimization suggestions
```

## Cost Management Architecture

### Cost Tracking and Budgeting Flow

```mermaid
graph TB
    subgraph "Cost Data Sources"
        ScalewayAPI[Scaleway Pricing API]
        ResourceUsage[Resource Usage Metrics]
        HistoricalData[Historical Cost Data]
    end

    subgraph "Cost Calculator Engine"
        PriceEngine[Price Calculation Engine]
        BudgetTracker[Budget Tracking]
        AlertSystem[Alert System]
        Forecasting[Cost Forecasting]
    end

    subgraph "Cost Management Actions"
        BudgetAlerts[Budget Alerts]
        ResourceOptimization[Resource Optimization]
        AutoScaling[Auto-scaling Recommendations]
        ReportGeneration[Cost Reports]
    end

    subgraph "Output Formats"
        TableOutput[Table View]
        JSONOutput[JSON Export]
        CSVOutput[CSV Export]
        EmailAlerts[Email Notifications]
    end

    ScalewayAPI --> PriceEngine
    ResourceUsage --> PriceEngine
    HistoricalData --> Forecasting

    PriceEngine --> BudgetTracker
    BudgetTracker --> AlertSystem
    Forecasting --> AutoScaling

    AlertSystem --> BudgetAlerts
    BudgetTracker --> ResourceOptimization
    PriceEngine --> ReportGeneration

    BudgetAlerts --> EmailAlerts
    ReportGeneration --> TableOutput
    ReportGeneration --> JSONOutput
    ReportGeneration --> CSVOutput
```

### Cost Calculation Workflow

```mermaid
sequenceDiagram
    participant Admin as Platform Admin
    participant CostCalc as Cost Calculator
    participant ScalewayAPI as Scaleway API
    participant MetricsDB as Metrics Database
    participant AlertSystem as Alert System

    Admin->>CostCalc: ./cost-calculator.sh --env=prod --set-budget=500
    CostCalc->>ScalewayAPI: Fetch current pricing data
    ScalewayAPI-->>CostCalc: Return resource prices

    CostCalc->>MetricsDB: Get resource usage metrics
    MetricsDB-->>CostCalc: Return CPU, memory, storage usage

    CostCalc->>CostCalc: Calculate monthly costs:
    Note over CostCalc: Compute: 5 nodes × €28.20 = €141<br/>Database: DB-GP-M HA = €178.50<br/>Load Balancer: GP-L = €35<br/>Storage: 500GB × €0.04 = €20<br/>Total: €374.50/month

    CostCalc->>CostCalc: Check against budget (€500)
    CostCalc->>AlertSystem: Set alert threshold (80% = €400)

    CostCalc->>Admin: Display cost breakdown
    Note over Admin: Current: €374.50/month (74.9% of budget)<br/>Projected annual: €4,494<br/>Alert threshold: €400/month

    CostCalc->>AlertSystem: Schedule daily cost checks
    AlertSystem-->>Admin: Email if costs exceed €400/month
```

## Monitoring and Observability

### Monitoring Stack Architecture

```mermaid
graph TB
    subgraph "Data Collection"
        NodeExporter[Node Exporter]
        PodMetrics[Pod Metrics]
        CoderMetrics[Coder Metrics]
        CustomMetrics[Custom Application Metrics]
    end

    subgraph "Metrics Processing"
        Prometheus[Prometheus Server]
        AlertManager[Alert Manager]
        ServiceMonitor[Service Monitors]
    end

    subgraph "Visualization"
        Grafana[Grafana Dashboards]
        AlertDashboard[Alert Dashboard]
        CostDashboard[Cost Dashboard]
    end

    subgraph "Alerting Channels"
        EmailAlerts[Email Notifications]
        SlackAlerts[Slack Integration]
        PagerDuty[PagerDuty Integration]
    end

    NodeExporter --> Prometheus
    PodMetrics --> Prometheus
    CoderMetrics --> ServiceMonitor
    ServiceMonitor --> Prometheus
    CustomMetrics --> Prometheus

    Prometheus --> AlertManager
    Prometheus --> Grafana
    AlertManager --> EmailAlerts
    AlertManager --> SlackAlerts
    AlertManager --> PagerDuty

    Grafana --> AlertDashboard
    Grafana --> CostDashboard
```

## Disaster Recovery and Backup Architecture

### Backup and Recovery Workflow

```mermaid
graph TB
    subgraph "Backup Sources"
        PostgresDB[PostgreSQL Database]
        WorkspaceData[Workspace Persistent Volumes]
        CoderConfig[Coder Configuration]
        K8sManifests[Kubernetes Manifests]
    end

    subgraph "Backup Storage"
        ScalewayStorage[Scaleway Object Storage]
        CrossRegionReplication[Cross-Region Replication]
        EncryptedBackups[Encrypted Backups]
    end

    subgraph "Recovery Procedures"
        DBRestore[Database Restore]
        VolumeRestore[Volume Restore]
        ConfigRestore[Configuration Restore]
        FullEnvironmentRestore[Full Environment Restore]
    end

    PostgresDB --> ScalewayStorage
    WorkspaceData --> ScalewayStorage
    CoderConfig --> ScalewayStorage
    K8sManifests --> ScalewayStorage

    ScalewayStorage --> CrossRegionReplication
    ScalewayStorage --> EncryptedBackups

    ScalewayStorage --> DBRestore
    ScalewayStorage --> VolumeRestore
    ScalewayStorage --> ConfigRestore
    ScalewayStorage --> FullEnvironmentRestore
```

## Two-Phase Management Scripts Architecture

### Script Ecosystem Overview

```mermaid
graph TB
    subgraph "Core Lifecycle Scripts (Two-Phase Aware)"
        Setup[setup.sh<br/>Two-Phase Environment Deployment<br/>Auto-detects infra/ + coder/ structure]
        Teardown[teardown.sh<br/>Two-Phase Environment Cleanup<br/>Coder first, then infrastructure]
        Backup[backup.sh<br/>Data Protection<br/>Separate infra/coder state backups]
    end

    subgraph "Operational Scripts"
        Validate[validate.sh<br/>Health Checking]
        Scale[scale.sh<br/>Dynamic Scaling]
        TestRunner[test-runner.sh<br/>Comprehensive Testing]
    end

    subgraph "Utility Scripts"
        CostCalc[cost-calculator.sh<br/>Cost Management]
        ResourceTracker[resource-tracker.sh<br/>Usage Monitoring]
        StateManager[state-manager.sh<br/>Remote State Operations]
    end

    subgraph "Integration Scripts"
        Hooks[Hooks Framework<br/>Custom Automation]
        GitHub[GitHub Actions<br/>Two-Phase CI/CD]
    end

    subgraph "Phase 1: Infrastructure"
        Scaleway[Scaleway API]
        InfraState[Infrastructure State<br/>infra/terraform.tfstate]
    end

    subgraph "Phase 2: Application"
        Kubernetes[Kubernetes API]
        Coder[Coder API]
        CoderState[Coder State<br/>coder/terraform.tfstate]
        Monitoring[Monitoring Stack]
    end

    Setup --> Scaleway
    Setup --> InfraState
    Setup --> Kubernetes
    Setup --> Coder
    Setup --> CoderState
    Setup --> Hooks

    Teardown --> Backup
    Teardown --> CoderState
    Teardown --> InfraState
    Teardown --> Hooks

    Validate --> Kubernetes
    Validate --> Coder
    Validate --> Monitoring

    Scale --> Kubernetes
    Scale --> CostCalc

    TestRunner --> Setup
    TestRunner --> Validate
    TestRunner --> GitHub

    StateManager --> InfraState
    StateManager --> CoderState
    CostCalc --> Scaleway
    ResourceTracker --> Kubernetes
    ResourceTracker --> Monitoring
```

### Two-Phase Script Interaction Flow

```mermaid
sequenceDiagram
    participant User as User/CI
    participant Setup as Setup Script
    participant PreHook as Pre-Setup Hook
    participant InfraTF as Infrastructure Terraform
    participant CoderTF as Coder Terraform
    participant PostHook as Post-Setup Hook
    participant Validate as Validation
    participant Backup as Backup System

    User->>Setup: ./setup.sh --env=prod
    Setup->>Setup: Detect environment structure (infra/ + coder/)
    Setup->>Setup: Load configuration
    Setup->>PreHook: Execute pre-setup.sh
    PreHook-->>Setup: Pre-checks passed

    Note over Setup: Phase 1: Infrastructure Deployment
    Setup->>InfraTF: terraform plan (infra/)
    InfraTF-->>Setup: Infrastructure plan ready
    Setup->>User: Show cost estimate
    User->>Setup: Approve deployment

    Setup->>InfraTF: terraform apply (infra/)
    InfraTF-->>Setup: Infrastructure ready + kubeconfig

    Note over Setup: Phase 2: Coder Application Deployment
    Setup->>CoderTF: terraform plan (coder/)
    Note over CoderTF: Uses remote state to read infra outputs
    CoderTF-->>Setup: Coder application plan ready

    Setup->>CoderTF: terraform apply (coder/)
    CoderTF-->>Setup: Coder application ready

    Setup->>PostHook: Execute post-setup.sh
    PostHook->>Validate: Run health checks (both phases)
    Validate-->>PostHook: All systems healthy
    PostHook->>Backup: Create initial backup (separate states)
    Backup-->>PostHook: Backup completed
    PostHook-->>Setup: Post-setup complete

    Setup->>User: Complete environment ready
    Note over User: Kubeconfig available throughout for troubleshooting
```

## Hooks Framework Architecture

### Hooks Execution Architecture

```mermaid
graph TB
    subgraph "Hook Types"
        PreSetup[pre-setup.sh<br/>Before Deployment]
        PostSetup[post-setup.sh<br/>After Deployment]
        PreTeardown[pre-teardown.sh<br/>Before Cleanup]
        PostTeardown[post-teardown.sh<br/>After Cleanup]
    end

    subgraph "Hook Capabilities"
        Validation[Custom Validation]
        Notifications[Team Notifications]
        ExternalAPI[External API Calls]
        Compliance[Compliance Checks]
        Monitoring[Monitor Integration]
        Backup[Backup Operations]
    end

    subgraph "Integration Points"
        Slack[Slack/Teams]
        JIRA[JIRA/Ticketing]
        LDAP[LDAP/SSO]
        Vault[Vault/Secrets]
        Prometheus[Metrics Collection]
        Grafana[Dashboard Updates]
    end

    subgraph "Core Scripts"
        SetupScript[setup.sh]
        TeardownScript[teardown.sh]
    end

    SetupScript --> PreSetup
    PreSetup --> Validation
    PreSetup --> ExternalAPI
    PreSetup --> Compliance

    SetupScript --> PostSetup
    PostSetup --> Notifications
    PostSetup --> Monitoring
    PostSetup --> Backup

    TeardownScript --> PreTeardown
    PreTeardown --> Validation
    PreTeardown --> Backup

    TeardownScript --> PostTeardown
    PostTeardown --> Notifications
    PostTeardown --> ExternalAPI

    Notifications --> Slack
    Notifications --> JIRA
    ExternalAPI --> LDAP
    ExternalAPI --> Vault
    Monitoring --> Prometheus
    Monitoring --> Grafana
```

### Hook Environment and Context

```mermaid
flowchart TD
    subgraph "Environment Variables"
        EnvVars[ENVIRONMENT<br/>TEMPLATE<br/>PROJECT_ROOT]
        SystemVars[KUBECONFIG<br/>SCW_* credentials]
        CustomVars[Custom exports from hooks]
    end

    subgraph "Context Information"
        DeploymentContext[Deployment metadata]
        ResourceContext[Resource information]
        UserContext[User and timing info]
    end

    subgraph "Hook Execution"
        ValidationHooks[Validation Hooks]
        ActionHooks[Action Hooks]
        NotificationHooks[Notification Hooks]
    end

    subgraph "External Integrations"
        APIs[External APIs]
        Databases[External Databases]
        Services[External Services]
    end

    EnvVars --> ValidationHooks
    SystemVars --> ActionHooks
    CustomVars --> NotificationHooks

    DeploymentContext --> ValidationHooks
    ResourceContext --> ActionHooks
    UserContext --> NotificationHooks

    ValidationHooks --> APIs
    ActionHooks --> Databases
    NotificationHooks --> Services
```

This comprehensive architecture documentation provides detailed insights into all aspects of the Bootstrap Coder on Scaleway system, including the new GitHub Actions CI/CD integration, management scripts ecosystem, hooks framework, and advanced monitoring capabilities. Teams can use this documentation to understand system interactions, plan deployments, troubleshoot issues, and extend the platform with custom functionality.