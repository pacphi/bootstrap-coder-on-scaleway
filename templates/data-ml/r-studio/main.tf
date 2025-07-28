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
  option {
    name  = "64 GB"
    value = "64"
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
    max = 500
  }
}

data "coder_parameter" "r_version" {
  name         = "r_version"
  display_name = "R Version"
  description  = "R version to install"
  default      = "4.3"
  icon         = "/icon/r.svg"
  mutable      = false
  option {
    name  = "R 4.2"
    value = "4.2"
  }
  option {
    name  = "R 4.3"
    value = "4.3"
  }
  option {
    name  = "R 4.4"
    value = "4.4"
  }
}

data "coder_parameter" "rstudio_edition" {
  name         = "rstudio_edition"
  display_name = "RStudio Edition"
  description  = "RStudio Server edition to install"
  default      = "open-source"
  icon         = "/icon/rstudio.svg"
  mutable      = false
  option {
    name  = "Open Source"
    value = "open-source"
  }
  option {
    name  = "VS Code (Quarto)"
    value = "vscode"
  }
}

data "coder_parameter" "data_packages" {
  name         = "data_packages"
  display_name = "Data Science Packages"
  description  = "Pre-install data science package collections"
  default      = "tidyverse"
  icon         = "/icon/package.svg"
  mutable      = false
  option {
    name  = "Tidyverse + Essential"
    value = "tidyverse"
  }
  option {
    name  = "Machine Learning"
    value = "ml"
  }
  option {
    name  = "Bioinformatics"
    value = "bio"
  }
  option {
    name  = "All Packages"
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

    echo "📊 Setting up R Studio data science environment..."

    # Update system
    sudo apt-get update
    sudo apt-get upgrade -y

    # Install system dependencies
    sudo apt-get install -y \
      wget \
      curl \
      git \
      build-essential \
      gfortran \
      libblas-dev \
      liblapack-dev \
      libxml2-dev \
      libssl-dev \
      libcurl4-openssl-dev \
      libfontconfig1-dev \
      libcairo2-dev \
      libgit2-dev \
      libharfbuzz-dev \
      libfribidi-dev \
      libfreetype6-dev \
      libpng-dev \
      libtiff5-dev \
      libjpeg-dev \
      libgdal-dev \
      gdal-bin \
      libproj-dev \
      proj-data \
      proj-bin \
      libgeos-dev \
      libudunits2-dev \
      netcdf-bin \
      libnetcdf-dev \
      libhdf5-dev \
      libv8-dev \
      libgmp-dev \
      libmpfr-dev \
      libmagick++-dev \
      pandoc \
      pandoc-citeproc \
      texlive-latex-base \
      texlive-fonts-recommended \
      texlive-latex-recommended \
      texlive-latex-extra \
      texlive-xetex \
      lmodern \
      htop \
      tree \
      jq \
      unzip

    # Install R ${data.coder_parameter.r_version.value}
    echo "📈 Installing R ${data.coder_parameter.r_version.value}..."

    # Add R repository
    wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | sudo gpg --dearmor -o /usr/share/keyrings/r-project.gpg
    echo "deb [signed-by=/usr/share/keyrings/r-project.gpg] https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" | sudo tee -a /etc/apt/sources.list.d/r-project.list

    sudo apt-get update
    sudo apt-get install -y r-base r-base-dev r-recommended

    # Install Python for reticulate
    echo "🐍 Installing Python for R integration..."
    sudo apt-get install -y python3 python3-pip python3-venv python3-dev
    pip3 install --user numpy pandas matplotlib scikit-learn jupyter

    # Install RStudio Server or VS Code based on edition
    case "${data.coder_parameter.rstudio_edition.value}" in
      "open-source")
        echo "📊 Installing RStudio Server Open Source..."
        wget https://download2.rstudio.org/server/jammy/amd64/rstudio-server-2023.12.1-402-amd64.deb
        sudo dpkg -i rstudio-server-2023.12.1-402-amd64.deb
        sudo apt-get install -f -y
        rm rstudio-server-2023.12.1-402-amd64.deb

        # Configure RStudio Server
        sudo systemctl enable rstudio-server
        sudo systemctl start rstudio-server

        # Set up user for RStudio
        sudo usermod -s /bin/bash coder
        echo "coder:password" | sudo chpasswd
        ;;
      "vscode")
        echo "💻 Installing VS Code with Quarto and R extensions..."
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
        sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
        sudo apt update
        sudo apt install -y code

        # Install Quarto
        wget https://github.com/quarto-dev/quarto-cli/releases/download/v1.4.549/quarto-1.4.549-linux-amd64.deb
        sudo dpkg -i quarto-1.4.549-linux-amd64.deb
        rm quarto-1.4.549-linux-amd64.deb

        # Install VS Code extensions
        code --install-extension REditorSupport.r
        code --install-extension quarto.quarto
        code --install-extension ms-python.python
        code --install-extension ms-toolsai.jupyter
        code --install-extension ms-vscode.vscode-json
        code --install-extension GitHub.copilot
        ;;
    esac

    # Install Docker
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Create R project structure
    cd /home/coder
    mkdir -p {data/{raw,processed,external},scripts,notebooks,reports,plots,models,functions}

    # Install R packages based on selection
    echo "📦 Installing R packages for ${data.coder_parameter.data_packages.value}..."

    # Create R script for package installation
    cat > install_packages.R << 'EOF'
# Install essential packages first
essential_packages <- c(
  "devtools", "remotes", "renv", "pak",
  "here", "fs", "glue", "janitor",
  "conflicted", "reprex"
)

install.packages(essential_packages, repos = "https://cloud.r-project.org/")

# Package collections based on selection
package_selection <- "${data.coder_parameter.data_packages.value}"

if (package_selection %in% c("tidyverse", "all")) {
  tidyverse_packages <- c(
    "tidyverse", "tidymodels", "DT", "plotly",
    "shiny", "shinydashboard", "flexdashboard",
    "rmarkdown", "knitr", "bookdown", "blogdown",
    "targets", "tarchetypes"
  )
  install.packages(tidyverse_packages, repos = "https://cloud.r-project.org/")
}

if (package_selection %in% c("ml", "all")) {
  ml_packages <- c(
    "caret", "randomForest", "xgboost", "glmnet",
    "e1071", "rpart", "tree", "ROCR",
    "pROC", "corrplot", "VIM", "mice",
    "keras", "tensorflow", "reticulate"
  )
  install.packages(ml_packages, repos = "https://cloud.r-project.org/")
}

if (package_selection %in% c("bio", "all")) {
  # Install Bioconductor
  if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager")

  bio_packages <- c(
    "Biostrings", "GenomicRanges", "IRanges",
    "rtracklayer", "GenomicFeatures", "AnnotationDbi",
    "org.Hs.eg.db", "TxDb.Hsapiens.UCSC.hg38.knownGene",
    "DESeq2", "edgeR", "limma", "ComplexHeatmap"
  )
  BiocManager::install(bio_packages)
}

if (package_selection == "all") {
  additional_packages <- c(
    "sf", "raster", "terra", "leaflet",
    "httr", "rvest", "jsonlite", "xml2",
    "lubridate", "hms", "clock",
    "DBI", "RSQLite", "RPostgres", "odbc",
    "parallel", "foreach", "doParallel",
    "profvis", "bench", "tictoc"
  )
  install.packages(additional_packages, repos = "https://cloud.r-project.org/")
}

# Create startup message
cat("✅ R packages installed successfully!\n")
EOF

    # Run package installation
    Rscript install_packages.R
    rm install_packages.R

    # Create sample R scripts and notebooks
    cat > scripts/data_analysis.R << 'EOF'
# Data Analysis Template
# Author: R Studio Environment
# Date: $(date +%Y-%m-%d)

# Load required libraries
library(tidyverse)
library(here)
library(janitor)

# Set up conflicted preferences
library(conflicted)
conflict_prefer("filter", "dplyr")
conflict_prefer("lag", "dplyr")

# Create sample data
set.seed(42)
sample_data <- tibble(
  id = 1:1000,
  group = sample(c("A", "B", "C"), 1000, replace = TRUE),
  value1 = rnorm(1000, mean = 50, sd = 10),
  value2 = rnorm(1000, mean = 100, sd = 20),
  date = seq.Date(from = as.Date("2023-01-01"),
                  by = "day", length.out = 1000)
) %>%
  clean_names()

# Basic analysis
summary_stats <- sample_data %>%
  group_by(group) %>%
  summarise(
    count = n(),
    mean_value1 = mean(value1),
    mean_value2 = mean(value2),
    sd_value1 = sd(value1),
    sd_value2 = sd(value2),
    .groups = "drop"
  )

print(summary_stats)

# Create visualization
p1 <- sample_data %>%
  ggplot(aes(x = value1, y = value2, color = group)) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "lm", se = TRUE) +
  labs(
    title = "Relationship between Value1 and Value2",
    subtitle = "Sample data analysis",
    x = "Value 1",
    y = "Value 2",
    color = "Group"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(size = 14, face = "bold"),
    legend.position = "bottom"
  )

print(p1)

# Save results
ggsave(here("plots", "value_relationship.png"), p1,
       width = 10, height = 6, dpi = 300)

write_csv(summary_stats, here("data", "processed", "summary_stats.csv"))
write_csv(sample_data, here("data", "processed", "sample_data.csv"))

cat("✅ Analysis complete! Check the plots and data directories.\n")
EOF

    # Create R Markdown template
    cat > notebooks/analysis_template.Rmd << 'EOF'
---
title: "Data Analysis Report"
author: "R Studio Environment"
date: "`r Sys.Date()`"
output:
  html_document:
    theme: flatly
    highlight: tango
    toc: true
    toc_float: true
    code_folding: show
  pdf_document:
    toc: true
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(
  echo = TRUE,
  warning = FALSE,
  message = FALSE,
  fig.width = 10,
  fig.height = 6,
  dpi = 300
)

# Load libraries
library(tidyverse)
library(DT)
library(plotly)
library(here)

# Set ggplot theme
theme_set(theme_minimal())
```

# Executive Summary

This report provides a comprehensive analysis of the dataset. Key findings include:

- Summary point 1
- Summary point 2
- Summary point 3

# Data Import and Cleaning

```{r data-import}
# Import data
data <- read_csv(here("data", "raw", "sample_data.csv"))

# Display data structure
glimpse(data)
```

```{r data-table}
# Interactive data table
datatable(
  head(data, 100),
  options = list(
    pageLength = 10,
    scrollX = TRUE
  ),
  caption = "Sample of the dataset"
)
```

# Exploratory Data Analysis

## Summary Statistics

```{r summary-stats}
# Generate summary statistics
summary_stats <- data %>%
  select(where(is.numeric)) %>%
  summary()

print(summary_stats)
```

## Visualizations

```{r visualizations}
# Distribution plot
p1 <- data %>%
  select(where(is.numeric)) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "value") %>%
  ggplot(aes(x = value)) +
  geom_histogram(bins = 30, fill = "steelblue", alpha = 0.7) +
  facet_wrap(~variable, scales = "free") +
  labs(
    title = "Distribution of Numeric Variables",
    x = "Value",
    y = "Frequency"
  )

print(p1)
```

```{r interactive-plot}
# Interactive plot with plotly
p2 <- data %>%
  ggplot(aes(x = value1, y = value2, color = group)) +
  geom_point(alpha = 0.6) +
  labs(title = "Interactive Scatter Plot")

ggplotly(p2)
```

# Statistical Analysis

```{r statistical-analysis}
# Perform statistical tests
# Example: t-test between groups
# t_test_result <- t.test(value1 ~ group, data = data)
# print(t_test_result)
```

# Conclusions

Based on the analysis:

1. Conclusion 1
2. Conclusion 2
3. Conclusion 3

# Session Information

```{r session-info}
sessionInfo()
```
EOF

    # Create utility functions
    cat > functions/data_utils.R << 'EOF'
# Data Utilities for R Analysis
# Collection of useful functions for data analysis

#' Check data quality
#' @param df A data frame
#' @return A summary of data quality issues
check_data_quality <- function(df) {
  list(
    dimensions = dim(df),
    missing_values = sapply(df, function(x) sum(is.na(x))),
    missing_percentage = sapply(df, function(x) round(sum(is.na(x))/length(x)*100, 2)),
    duplicated_rows = sum(duplicated(df)),
    column_types = sapply(df, class)
  )
}

#' Create a publication-ready table
#' @param df A data frame
#' @param caption Table caption
#' @return A formatted table
create_pub_table <- function(df, caption = NULL) {
  require(knitr)
  require(kableExtra)

  kable(df, caption = caption) %>%
    kable_styling(
      bootstrap_options = c("striped", "hover", "condensed"),
      full_width = FALSE,
      position = "center"
    )
}

#' Save plot with consistent formatting
#' @param plot ggplot object
#' @param filename File name
#' @param width Width in inches
#' @param height Height in inches
save_publication_plot <- function(plot, filename, width = 10, height = 6) {
  require(here)

  ggsave(
    filename = here("plots", filename),
    plot = plot,
    width = width,
    height = height,
    dpi = 300,
    bg = "white"
  )

  cat(glue::glue("✅ Plot saved: {filename}\n"))
}

#' Load all custom functions
load_functions <- function() {
  function_files <- list.files(here("functions"), pattern = "*.R", full.names = TRUE)
  sapply(function_files, source)
  cat("✅ Custom functions loaded\n")
}
EOF

    # Create .Rprofile for project setup
    cat > .Rprofile << 'EOF'
# Project-specific R profile
cat("🚀 Welcome to your R Studio Data Science Environment!\n")
cat("📊 Project initialized with data science packages\n")

# Set options
options(
  repos = c(CRAN = "https://cloud.r-project.org/"),
  warn = 1,
  scipen = 999,
  digits = 4,
  max.print = 100
)

# Load essential packages quietly
suppressPackageStartupMessages({
  library(here)
  library(conflicted)
})

# Set conflict preferences
if (requireNamespace("conflicted", quietly = TRUE)) {
  conflicted::conflict_prefer("filter", "dplyr")
  conflicted::conflict_prefer("lag", "dplyr")
  conflicted::conflict_prefer("set_names", "purrr")
}

# Source utility functions if available
if (file.exists(here("functions", "data_utils.R"))) {
  source(here("functions", "data_utils.R"))
}

# Display helpful information
cat("\n📁 Project structure:\n")
if (requireNamespace("fs", quietly = TRUE)) {
  fs::dir_tree(max_depth = 2)
}

cat("\n🔧 Useful commands:\n")
cat("  - check_data_quality(df) : Check data quality\n")
cat("  - here() : Get project root path\n")
cat("  - load_functions() : Load custom functions\n")
cat("\n")
EOF

    # Create renv.lock for reproducible environments
    if command -v R >/dev/null 2>&1; then
      R -e "if (!requireNamespace('renv', quietly = TRUE)) install.packages('renv'); renv::init()"
    fi

    # Create Docker configuration
    cat > Dockerfile << 'EOF'
FROM rocker/rstudio:${data.coder_parameter.r_version.value}

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libxml2-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libgit2-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgdal-dev \
    gdal-bin \
    libproj-dev \
    proj-data \
    proj-bin \
    libgeos-dev \
    libudunits2-dev \
    netcdf-bin \
    libnetcdf-dev \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages for reticulate
RUN pip3 install numpy pandas matplotlib scikit-learn jupyter

# Install R packages
RUN R -e "install.packages(c('tidyverse', 'tidymodels', 'shiny', 'rmarkdown', 'here', 'janitor', 'DT', 'plotly'))"

# Copy project files
COPY . /home/rstudio/project
RUN chown -R rstudio:rstudio /home/rstudio/project

# Set working directory
WORKDIR /home/rstudio/project

EXPOSE 8787

CMD ["/init"]
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  rstudio:
    build: .
    container_name: rstudio-server
    ports:
      - "8787:8787"
    environment:
      - PASSWORD=password
      - ROOT=TRUE
    volumes:
      - .:/home/rstudio/project
      - rstudio-data:/home/rstudio
    restart: unless-stopped

  postgres:
    image: postgres:15-alpine
    container_name: postgres-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: analytics
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  rstudio-data:
  postgres_data:
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
# History files
.Rhistory
.Rapp.history

# Session Data files
.RData

# User-specific files
.Ruserdata

# R Environment Variables
.Renviron

# RStudio files
.Rproj.user/
*.Rproj

# produced vignettes
vignettes/*.html
vignettes/*.pdf

# OAuth2 token, see https://github.com/hadley/httr/releases/tag/v0.3
.httr-oauth

# knitr and R markdown default cache directories
*_cache/
/cache/

# Temporary files created by R markdown
*.utf8.md
*.knit.md

# R Environment Variables
.Renviron

# pkgdown site
docs/

# translation temp files
po/*~

# Data files
*.csv
*.xlsx
*.rds
*.feather
*.parquet

# Plots
plots/*.png
plots/*.pdf
plots/*.svg

# Models
models/*.rds
models/*.pkl
EOF

    # Create project README
    cat > README.md << 'EOF'
# R Studio Data Science Environment

This is a comprehensive R data science environment with pre-configured packages and project structure.

## Features

- R ${data.coder_parameter.r_version.value} with ${data.coder_parameter.data_packages.value} packages
- ${data.coder_parameter.rstudio_edition.value == "open-source" ? "RStudio Server" : "VS Code with Quarto"}
- Organized project structure for reproducible research
- Docker support for containerized development
- Custom utility functions for common data science tasks

## Project Structure

```
├── data/
│   ├── raw/          # Raw, immutable data
│   ├── processed/    # Cleaned and transformed data
│   └── external/     # External reference data
├── scripts/          # R scripts for analysis
├── notebooks/        # R Markdown notebooks
├── reports/          # Generated reports
├── plots/            # Generated visualizations
├── models/           # Saved models
└── functions/        # Custom R functions
```

## Getting Started

1. Access ${data.coder_parameter.rstudio_edition.value == "open-source" ? "RStudio Server at http://localhost:8787" : "VS Code for R development"}
2. Open the sample analysis script: `scripts/data_analysis.R`
3. Explore the R Markdown template: `notebooks/analysis_template.Rmd`

## Installed Packages

The environment includes packages for:
- Data manipulation: tidyverse, janitor, here
- Visualization: ggplot2, plotly, DT
- Reporting: rmarkdown, knitr
- ${data.coder_parameter.data_packages.value == "ml" ? "Machine Learning: caret, randomForest, xgboost" : ""}
- ${data.coder_parameter.data_packages.value == "bio" ? "Bioinformatics: Bioconductor packages" : ""}

## Usage Tips

- Use `here()` for file paths to ensure reproducibility
- Check `check_data_quality()` function for data validation
- Save plots with `save_publication_plot()` for consistency
- Use renv for package version management

## Docker Usage

```bash
# Build and run
docker-compose up -d

# Access RStudio Server
# http://localhost:8787 (user: rstudio, password: password)
```
EOF

    # Set proper ownership
    sudo chown -R coder:coder /home/coder

    # Create symbolic links for easier access
    ln -sf scripts/data_analysis.R /home/coder/quick_analysis.R
    ln -sf notebooks/analysis_template.Rmd /home/coder/template.Rmd

    echo "✅ R Studio data science environment ready!"
    case "${data.coder_parameter.rstudio_edition.value}" in
      "open-source")
        echo "🔗 RStudio Server: http://localhost:8787"
        echo "👤 Username: coder, Password: password"
        ;;
      "vscode")
        echo "💻 VS Code with R and Quarto support installed"
        echo "📊 Use Quarto for literate programming"
        ;;
    esac
    echo "📦 Packages installed: ${data.coder_parameter.data_packages.value}"

  EOT

}

# Metadata
resource "coder_metadata" "r_version" {
  resource_id = coder_agent.main.id
  item {
    key   = "r_version"
    value = data.coder_parameter.r_version.value
  }
}

resource "coder_metadata" "rstudio_edition" {
  resource_id = coder_agent.main.id
  item {
    key   = "rstudio_edition"
    value = data.coder_parameter.rstudio_edition.value
  }
}

resource "coder_metadata" "data_packages" {
  resource_id = coder_agent.main.id
  item {
    key   = "data_packages"
    value = data.coder_parameter.data_packages.value
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
resource "coder_app" "rstudio_server" {
  count        = data.coder_parameter.rstudio_edition.value == "open-source" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "rstudio"
  display_name = "RStudio Server"
  url          = "http://localhost:8787"
  icon         = "/icon/rstudio.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8787"
    interval  = 10
    threshold = 30
  }
}

resource "coder_app" "vscode" {
  count        = data.coder_parameter.rstudio_edition.value == "vscode" ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder"
  share        = "owner"
}

resource "coder_app" "shiny_server" {
  agent_id     = coder_agent.main.id
  slug         = "shiny"
  display_name = "Shiny Server"
  url          = "http://localhost:3838"
  icon         = "/icon/shiny.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:3838"
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
      "r-workspace"  = "true"
      "data-science" = "true"
    }
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "fast-ssd" # Use fast storage for data science

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
      "r-workspace"                = "true"
      "data-science"               = "true"
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
          "r-workspace"                 = "true"
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
            name       = "tmp"
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
          name = "tmp"
          empty_dir {
            size_limit = "10Gi"
          }
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

        # Toleration for data science workloads
        toleration {
          key      = "data-science-workloads"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.home]
}
