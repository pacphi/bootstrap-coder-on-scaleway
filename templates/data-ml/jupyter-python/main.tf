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

data "coder_parameter" "python_version" {
  name         = "python_version"
  display_name = "Python Version"
  description  = "Python version to install"
  default      = "3.11"
  icon         = "/icon/python.svg"
  mutable      = false
  option {
    name  = "Python 3.10"
    value = "3.10"
  }
  option {
    name  = "Python 3.11"
    value = "3.11"
  }
  option {
    name  = "Python 3.12"
    value = "3.12"
  }
}

data "coder_parameter" "ml_framework" {
  name         = "ml_framework"
  display_name = "ML Framework"
  description  = "Primary machine learning framework"
  default      = "pytorch"
  icon         = "/icon/ai.svg"
  mutable      = false
  option {
    name  = "PyTorch + Lightning"
    value = "pytorch"
  }
  option {
    name  = "TensorFlow + Keras"
    value = "tensorflow"
  }
  option {
    name  = "Scikit-learn + XGBoost"
    value = "sklearn"
  }
  option {
    name  = "All Frameworks"
    value = "all"
  }
}

data "coder_parameter" "enable_gpu" {
  name         = "enable_gpu"
  display_name = "Enable GPU Support"
  description  = "Enable CUDA GPU support for deep learning"
  default      = "true"
  type         = "bool"
  icon         = "/icon/gpu.svg"
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

    echo "🐍 Setting up Jupyter Python ML/AI development environment..."

    # Update system
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential

    # Install system dependencies for data science
    sudo apt-get install -y \
      python3-dev \
      python3-pip \
      python3-venv \
      libhdf5-dev \
      libnetcdf-dev \
      libopenblas-dev \
      liblapack-dev \
      libblas-dev \
      gfortran \
      libffi-dev \
      libssl-dev \
      zlib1g-dev \
      libjpeg-dev \
      libpng-dev \
      libfreetype6-dev \
      pkg-config \
      graphviz \
      graphviz-dev \
      ffmpeg \
      libsm6 \
      libxext6 \
      libxrender-dev \
      libglib2.0-0 \
      libgomp1

    # Install Python ${data.coder_parameter.python_version.value}
    echo "📦 Installing Python ${data.coder_parameter.python_version.value}..."
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt-get update
    sudo apt-get install -y \
      python${data.coder_parameter.python_version.value} \
      python${data.coder_parameter.python_version.value}-dev \
      python${data.coder_parameter.python_version.value}-venv \
      python${data.coder_parameter.python_version.value}-distutils

    # Set Python ${data.coder_parameter.python_version.value} as default
    sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${data.coder_parameter.python_version.value} 1
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python${data.coder_parameter.python_version.value} 1

    # Install pip for the correct Python version
    curl -sS https://bootstrap.pypa.io/get-pip.py | python${data.coder_parameter.python_version.value}

    # Install Poetry for dependency management
    echo "📚 Installing Poetry..."
    curl -sSL https://install.python-poetry.org | python3 -
    export PATH="/home/coder/.local/bin:$PATH"
    echo 'export PATH="/home/coder/.local/bin:$PATH"' >> ~/.bashrc

    # Install Conda/Mamba for environment management
    echo "🐍 Installing Miniforge (Conda + Mamba)..."
    curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
    bash Miniforge3-$(uname)-$(uname -m).sh -b -p $HOME/miniforge3
    rm Miniforge3-$(uname)-$(uname -m).sh

    echo 'export PATH="$HOME/miniforge3/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/miniforge3/bin:$PATH"

    # Initialize conda
    $HOME/miniforge3/bin/conda init bash
    source ~/.bashrc

    # Create ML environment
    echo "🧠 Creating ML environment..."
    mamba create -n mlenv python=${data.coder_parameter.python_version.value} -y
    source $HOME/miniforge3/bin/activate mlenv

    # Install base data science packages
    echo "📊 Installing base data science packages..."
    mamba install -y \
      jupyter \
      jupyterlab \
      notebook \
      ipython \
      ipywidgets \
      numpy \
      pandas \
      matplotlib \
      seaborn \
      plotly \
      bokeh \
      altair \
      scipy \
      statsmodels \
      sympy \
      numba \
      dask \
      polars

    # Install ML framework specific packages
    case "${data.coder_parameter.ml_framework.value}" in
      "pytorch"|"all")
        echo "🔥 Installing PyTorch ecosystem..."
        if [[ "${data.coder_parameter.enable_gpu.value}" == "true" ]]; then
          mamba install -y pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia
        else
          mamba install -y pytorch torchvision torchaudio cpuonly -c pytorch
        fi
        mamba install -y \
          lightning \
          torchmetrics \
          transformers \
          datasets \
          tokenizers \
          accelerate \
          diffusers \
          timm
        pip install torch-geometric wandb tensorboard
        ;;
    esac

    case "${data.coder_parameter.ml_framework.value}" in
      "tensorflow"|"all")
        echo "🧮 Installing TensorFlow ecosystem..."
        if [[ "${data.coder_parameter.enable_gpu.value}" == "true" ]]; then
          pip install tensorflow[and-cuda]
        else
          pip install tensorflow
        fi
        pip install \
          keras \
          tensorflow-probability \
          tensorflow-datasets \
          tensorflow-hub \
          tf-agents \
          tensorflow-addons
        ;;
    esac

    case "${data.coder_parameter.ml_framework.value}" in
      "sklearn"|"all")
        echo "⚙️ Installing Scikit-learn ecosystem..."
        mamba install -y \
          scikit-learn \
          scikit-image \
          scikit-optimize \
          xgboost \
          lightgbm \
          catboost \
          imbalanced-learn \
          feature-engine
        ;;
    esac

    # Install additional ML/AI packages
    echo "🤖 Installing additional ML/AI packages..."
    pip install \
      openai \
      anthropic \
      langchain \
      langchain-community \
      chromadb \
      faiss-cpu \
      sentence-transformers \
      spacy \
      nltk \
      textblob \
      gensim \
      opencv-python \
      pillow \
      albumentations \
      gradio \
      streamlit \
      dash \
      mlflow \
      optuna \
      hyperopt \
      ray[tune] \
      joblib \
      tqdm \
      click \
      typer \
      rich \
      pydantic

    # Install development and testing packages
    pip install \
      pytest \
      pytest-cov \
      black \
      isort \
      flake8 \
      mypy \
      pre-commit \
      jupyter-lab-code-formatter \
      nbqa \
      papermill \
      nbconvert \
      jupytext

    # Install VS Code and extensions
    echo "💻 Installing VS Code..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    sudo apt update
    sudo apt install -y code

    # Install VS Code extensions for data science
    code --install-extension ms-python.python
    code --install-extension ms-python.vscode-pylance
    code --install-extension ms-toolsai.jupyter
    code --install-extension ms-toolsai.jupyter-keymap
    code --install-extension ms-toolsai.jupyter-renderers
    code --install-extension ms-python.black-formatter
    code --install-extension ms-python.isort
    code --install-extension ms-python.flake8
    code --install-extension ms-python.mypy-type-checker
    code --install-extension GitHub.copilot
    code --install-extension ms-vscode.vscode-json

    # Install Docker
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker coder
    sudo systemctl enable docker --now

    # Create project structure
    cd /home/coder
    mkdir -p {notebooks,data/{raw,processed,external},src,models,reports,references,experiments}

    # Create sample notebooks
    cat > notebooks/01_data_exploration.ipynb << 'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Data Exploration\n",
    "\n",
    "This notebook demonstrates basic data exploration techniques using pandas, matplotlib, and seaborn."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import numpy as np\n",
    "import matplotlib.pyplot as plt\n",
    "import seaborn as sns\n",
    "from pathlib import Path\n",
    "\n",
    "# Set style\n",
    "plt.style.use('seaborn-v0_8')\n",
    "sns.set_palette('husl')\n",
    "\n",
    "print(f\"📊 Data Science Environment Ready!\")\n",
    "print(f\"Python: {pd.__version__}\")\n",
    "print(f\"Pandas: {pd.__version__}\")\n",
    "print(f\"NumPy: {np.__version__}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Create sample dataset\n",
    "np.random.seed(42)\n",
    "data = {\n",
    "    'feature_1': np.random.normal(0, 1, 1000),\n",
    "    'feature_2': np.random.normal(2, 1.5, 1000),\n",
    "    'feature_3': np.random.exponential(1, 1000),\n",
    "    'category': np.random.choice(['A', 'B', 'C'], 1000)\n",
    "}\n",
    "df = pd.DataFrame(data)\n",
    "df['target'] = (df['feature_1'] * 0.5 + df['feature_2'] * 0.3 - df['feature_3'] * 0.2 + \n",
    "                np.random.normal(0, 0.1, 1000))\n",
    "\n",
    "print(f\"Dataset shape: {df.shape}\")\n",
    "df.head()"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Basic statistics\n",
    "df.describe()"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Visualization\n",
    "fig, axes = plt.subplots(2, 2, figsize=(12, 8))\n",
    "\n",
    "# Distribution plots\n",
    "df['feature_1'].hist(ax=axes[0,0], bins=30, alpha=0.7)\n",
    "axes[0,0].set_title('Feature 1 Distribution')\n",
    "\n",
    "sns.boxplot(data=df, x='category', y='target', ax=axes[0,1])\n",
    "axes[0,1].set_title('Target by Category')\n",
    "\n",
    "# Correlation heatmap\n",
    "corr_matrix = df.select_dtypes(include=[np.number]).corr()\n",
    "sns.heatmap(corr_matrix, annot=True, ax=axes[1,0], cmap='coolwarm')\n",
    "axes[1,0].set_title('Correlation Matrix')\n",
    "\n",
    "# Scatter plot\n",
    "axes[1,1].scatter(df['feature_1'], df['target'], alpha=0.5)\n",
    "axes[1,1].set_xlabel('Feature 1')\n",
    "axes[1,1].set_ylabel('Target')\n",
    "axes[1,1].set_title('Feature 1 vs Target')\n",
    "\n",
    "plt.tight_layout()\n",
    "plt.show()"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3 (ipykernel)",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "${data.coder_parameter.python_version.value}"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    # Create ML pipeline notebook
    cat > notebooks/02_ml_pipeline.ipynb << 'EOF'
{
 "cells": [
  {
   "cell_type": "markdown",
   "metadata": {},
   "source": [
    "# Machine Learning Pipeline\n",
    "\n",
    "This notebook demonstrates a complete ML pipeline with ${data.coder_parameter.ml_framework.value}."
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "import pandas as pd\n",
    "import numpy as np\n",
    "from sklearn.model_selection import train_test_split\n",
    "from sklearn.preprocessing import StandardScaler\n",
    "from sklearn.metrics import classification_report, confusion_matrix\n",
    "import matplotlib.pyplot as plt\n",
    "import seaborn as sns\n",
    "\n",
    "print(\"🤖 ML Pipeline Ready!\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Load and prepare data\n",
    "from sklearn.datasets import make_classification\n",
    "\n",
    "X, y = make_classification(\n",
    "    n_samples=1000,\n",
    "    n_features=20,\n",
    "    n_informative=10,\n",
    "    n_redundant=10,\n",
    "    n_classes=3,\n",
    "    random_state=42\n",
    ")\n",
    "\n",
    "# Split data\n",
    "X_train, X_test, y_train, y_test = train_test_split(\n",
    "    X, y, test_size=0.2, random_state=42, stratify=y\n",
    ")\n",
    "\n",
    "# Scale features\n",
    "scaler = StandardScaler()\n",
    "X_train_scaled = scaler.fit_transform(X_train)\n",
    "X_test_scaled = scaler.transform(X_test)\n",
    "\n",
    "print(f\"Training set size: {X_train.shape}\")\n",
    "print(f\"Test set size: {X_test.shape}\")\n",
    "print(f\"Class distribution: {np.bincount(y)}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Train model\n",
    "from sklearn.ensemble import RandomForestClassifier\n",
    "from sklearn.linear_model import LogisticRegression\n",
    "from sklearn.svm import SVC\n",
    "\n",
    "models = {\n",
    "    'Random Forest': RandomForestClassifier(n_estimators=100, random_state=42),\n",
    "    'Logistic Regression': LogisticRegression(random_state=42, max_iter=1000),\n",
    "    'SVM': SVC(random_state=42, probability=True)\n",
    "}\n",
    "\n",
    "results = {}\n",
    "for name, model in models.items():\n",
    "    model.fit(X_train_scaled, y_train)\n",
    "    train_score = model.score(X_train_scaled, y_train)\n",
    "    test_score = model.score(X_test_scaled, y_test)\n",
    "    results[name] = {'train_score': train_score, 'test_score': test_score}\n",
    "    print(f\"{name}: Train={train_score:.3f}, Test={test_score:.3f}\")"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "metadata": {},
   "outputs": [],
   "source": [
    "# Evaluate best model\n",
    "best_model_name = max(results, key=lambda x: results[x]['test_score'])\n",
    "best_model = models[best_model_name]\n",
    "\n",
    "y_pred = best_model.predict(X_test_scaled)\n",
    "print(f\"Best model: {best_model_name}\")\n",
    "print(\"\\nClassification Report:\")\n",
    "print(classification_report(y_test, y_pred))\n",
    "\n",
    "# Confusion matrix\n",
    "plt.figure(figsize=(8, 6))\n",
    "sns.heatmap(confusion_matrix(y_test, y_pred), annot=True, fmt='d', cmap='Blues')\n",
    "plt.title(f'Confusion Matrix - {best_model_name}')\n",
    "plt.xlabel('Predicted')\n",
    "plt.ylabel('Actual')\n",
    "plt.show()"
   ]
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3 (ipykernel)",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "${data.coder_parameter.python_version.value}"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 4
}
EOF

    # Create src directory with utilities
    cat > src/utils.py << 'EOF'
"""
Utility functions for data science projects.
"""
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from typing import List, Dict, Any, Optional
from pathlib import Path

def load_data(file_path: str) -> pd.DataFrame:
    """Load data from various file formats."""
    path = Path(file_path)

    if path.suffix == '.csv':
        return pd.read_csv(file_path)
    elif path.suffix == '.parquet':
        return pd.read_parquet(file_path)
    elif path.suffix in ['.xlsx', '.xls']:
        return pd.read_excel(file_path)
    elif path.suffix == '.json':
        return pd.read_json(file_path)
    else:
        raise ValueError(f"Unsupported file format: {path.suffix}")

def describe_dataframe(df: pd.DataFrame) -> Dict[str, Any]:
    """Get comprehensive description of DataFrame."""
    return {
        'shape': df.shape,
        'columns': df.columns.tolist(),
        'dtypes': df.dtypes.to_dict(),
        'missing_values': df.isnull().sum().to_dict(),
        'memory_usage': df.memory_usage(deep=True).sum(),
        'numeric_summary': df.describe().to_dict() if len(df.select_dtypes(include=[np.number]).columns) > 0 else None
    }

def plot_missing_values(df: pd.DataFrame, figsize: tuple = (12, 6)) -> None:
    """Plot missing values heatmap."""
    missing = df.isnull()

    if not missing.any().any():
        print("No missing values found!")
        return

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=figsize)

    # Missing values heatmap
    sns.heatmap(missing, ax=ax1, cbar=True, yticklabels=False, cmap='viridis')
    ax1.set_title('Missing Values Heatmap')

    # Missing values count
    missing_count = missing.sum().sort_values(ascending=False)
    missing_count = missing_count[missing_count > 0]

    if len(missing_count) > 0:
        missing_count.plot(kind='bar', ax=ax2)
        ax2.set_title('Missing Values Count by Column')
        ax2.tick_params(axis='x', rotation=45)

    plt.tight_layout()
    plt.show()

def correlation_analysis(df: pd.DataFrame, threshold: float = 0.7) -> None:
    """Analyze correlations and highlight high correlations."""
    numeric_df = df.select_dtypes(include=[np.number])

    if numeric_df.empty:
        print("No numeric columns found!")
        return

    corr_matrix = numeric_df.corr()

    # Plot correlation heatmap
    plt.figure(figsize=(10, 8))
    sns.heatmap(corr_matrix, annot=True, cmap='coolwarm', center=0,
                square=True, fmt='.2f')
    plt.title('Correlation Matrix')
    plt.tight_layout()
    plt.show()

    # Find high correlations
    high_corr = []
    for i in range(len(corr_matrix.columns)):
        for j in range(i+1, len(corr_matrix.columns)):
            corr_val = abs(corr_matrix.iloc[i, j])
            if corr_val >= threshold:
                high_corr.append({
                    'feature_1': corr_matrix.columns[i],
                    'feature_2': corr_matrix.columns[j],
                    'correlation': corr_matrix.iloc[i, j]
                })

    if high_corr:
        print(f"\nHigh correlations (threshold >= {threshold}):")
        for item in high_corr:
            print(f"  {item['feature_1']} - {item['feature_2']}: {item['correlation']:.3f}")
    else:
        print(f"\nNo high correlations found (threshold >= {threshold})")
EOF

    # Create requirements files
    cat > requirements.txt << 'EOF'
# Core data science
numpy>=1.24.0
pandas>=2.0.0
scipy>=1.10.0
matplotlib>=3.7.0
seaborn>=0.12.0
plotly>=5.14.0
bokeh>=3.1.0

# Machine learning
scikit-learn>=1.3.0
xgboost>=1.7.0
lightgbm>=3.3.0

# Jupyter
jupyter>=1.0.0
jupyterlab>=4.0.0
ipywidgets>=8.0.0

# Development
pytest>=7.0.0
black>=23.0.0
isort>=5.12.0
flake8>=6.0.0
mypy>=1.3.0
EOF

    # Create environment.yml
    cat > environment.yml << 'EOF'
name: mlenv
channels:
  - conda-forge
  - pytorch
  - nvidia
dependencies:
  - python=${data.coder_parameter.python_version.value}
  - numpy
  - pandas
  - scipy
  - matplotlib
  - seaborn
  - plotly
  - bokeh
  - jupyter
  - jupyterlab
  - ipywidgets
  - scikit-learn
  - xgboost
  - lightgbm
  - pip
  - pip:
    - mlflow
    - optuna
    - wandb
    - streamlit
    - gradio
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM jupyter/scipy-notebook:latest

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    graphviz \
    graphviz-dev \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

USER $NB_UID

# Copy requirements
COPY requirements.txt /tmp/requirements.txt

# Install Python packages
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Install additional packages based on ML framework
ARG ML_FRAMEWORK=pytorch
RUN if [ "$ML_FRAMEWORK" = "pytorch" ] || [ "$ML_FRAMEWORK" = "all" ]; then \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu; \
    fi

RUN if [ "$ML_FRAMEWORK" = "tensorflow" ] || [ "$ML_FRAMEWORK" = "all" ]; then \
    pip install tensorflow; \
    fi

WORKDIR /home/jovyan/work

EXPOSE 8888

CMD ["start-notebook.sh", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--NotebookApp.token=''", "--NotebookApp.password=''"]
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  jupyter:
    build:
      context: .
      args:
        ML_FRAMEWORK: ${data.coder_parameter.ml_framework.value}
    ports:
      - "8888:8888"
    volumes:
      - .:/home/jovyan/work
      - jupyter-data:/home/jovyan/.jupyter
    environment:
      - JUPYTER_ENABLE_LAB=yes
      - GRANT_SUDO=yes
    restart: unless-stopped

  mlflow:
    image: python:3.11-slim
    ports:
      - "5000:5000"
    volumes:
      - mlflow-data:/mlruns
    command: >
      bash -c "pip install mlflow &&
               mlflow server --host 0.0.0.0 --port 5000 --default-artifact-root /mlruns"
    restart: unless-stopped

volumes:
  jupyter-data:
  mlflow-data:
EOF

    # Create .gitignore
    cat > .gitignore << 'EOF'
# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class

# Jupyter Notebook checkpoints
.ipynb_checkpoints

# Data files
data/raw/*
!data/raw/.gitkeep
data/processed/*
!data/processed/.gitkeep
*.csv
*.parquet
*.h5
*.hdf5

# Model files
models/*
!models/.gitkeep
*.pkl
*.joblib
*.pt
*.pth
*.onnx

# MLflow
mlruns/
mlflow.db

# Environment
.env
venv/
env/
ENV/

# IDEs
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
EOF

    # Create data directory structure
    mkdir -p data/{raw,processed,external}
    touch data/raw/.gitkeep
    touch data/processed/.gitkeep
    touch data/external/.gitkeep
    touch models/.gitkeep

    # Configure JupyterLab
    source $HOME/miniforge3/bin/activate mlenv

    # Install JupyterLab extensions
    pip install \
      jupyterlab-git \
      jupyterlab-lsp \
      python-lsp-server \
      jupyterlab-code-formatter \
      jupyterlab-variableinspector

    # Set proper ownership
    sudo chown -R coder:coder /home/coder

    echo "✅ Jupyter Python ML/AI development environment ready!"
    echo "Conda environment 'mlenv' created with Python ${data.coder_parameter.python_version.value}"
    echo "ML Framework: ${data.coder_parameter.ml_framework.value}"
    echo "GPU Support: ${data.coder_parameter.enable_gpu.value}"
    echo ""
    echo "To activate the environment: conda activate mlenv"
    echo "To start Jupyter Lab: jupyter lab --ip=0.0.0.0 --port=8888 --no-browser"

  EOT

  # Metadata
  metadata {
    display_name = "Python Version"
    key          = "python_version"
    value        = data.coder_parameter.python_version.value
  }

  metadata {
    display_name = "ML Framework"
    key          = "ml_framework"
    value        = data.coder_parameter.ml_framework.value
  }

  metadata {
    display_name = "GPU Support"
    key          = "gpu_enabled"
    value        = data.coder_parameter.enable_gpu.value
  }

  metadata {
    display_name = "CPU"
    key          = "cpu"
    value        = data.coder_parameter.cpu.value
  }

  metadata {
    display_name = "Memory"
    key          = "memory"
    value        = "${data.coder_parameter.memory.value}GB"
  }
}

# Applications
resource "coder_app" "jupyter_lab" {
  agent_id     = coder_agent.main.id
  slug         = "jupyter-lab"
  display_name = "JupyterLab"
  url          = "http://localhost:8888"
  icon         = "/icon/jupyter.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:8888"
    interval  = 10
    threshold = 20
  }
}

resource "coder_app" "jupyter_notebook" {
  agent_id     = coder_agent.main.id
  slug         = "jupyter-notebook"
  display_name = "Jupyter Notebook"
  url          = "http://localhost:8888/tree"
  icon         = "/icon/jupyter.svg"
  subdomain    = false
  share        = "owner"
}

resource "coder_app" "mlflow" {
  agent_id     = coder_agent.main.id
  slug         = "mlflow"
  display_name = "MLflow"
  url          = "http://localhost:5000"
  icon         = "/icon/mlflow.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:5000"
    interval  = 15
    threshold = 30
  }
}

resource "coder_app" "vscode" {
  agent_id     = coder_agent.main.id
  slug         = "vscode"
  display_name = "VS Code"
  icon         = "/icon/vscode.svg"
  command      = "code /home/coder"
  share        = "owner"
}

# Kubernetes resources
resource "kubernetes_persistent_volume_claim" "home" {
  metadata {
    name      = "coder-${data.coder_workspace.me.id}-home"
    namespace = var.namespace

    labels = {
      "ml-workspace" = "true"
    }
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "fast-ssd"  # Use fast storage for ML workloads

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

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace.me.owner_id
      "com.coder.user.username"    = data.coder_workspace.me.owner
      "ml-workspace"               = "true"
    }

    annotations = {
      "com.coder.user.email" = data.coder_workspace.me.owner_email
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name"     = "coder-workspace"
        "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
          "app.kubernetes.io/component" = "workspace"
          "ml-workspace"               = "true"
        }
      }

      spec {
        security_context {
          run_as_user  = 1000
          run_as_group = 1000
          fs_group     = 1000
        }

        # Use node with GPU if requested
        dynamic "node_selector" {
          for_each = data.coder_parameter.enable_gpu.value ? [1] : []
          content {
            "accelerator" = "nvidia-tesla-k80"
          }
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
              add = data.coder_parameter.enable_gpu.value ? ["SYS_ADMIN", "SYS_RESOURCE"] : ["SYS_ADMIN"]
            }
          }

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          # GPU support (conditional)
          dynamic "env" {
            for_each = data.coder_parameter.enable_gpu.value ? [1] : []
            content {
              name  = "NVIDIA_VISIBLE_DEVICES"
              value = "all"
            }
          }

          dynamic "env" {
            for_each = data.coder_parameter.enable_gpu.value ? [1] : []
            content {
              name  = "NVIDIA_DRIVER_CAPABILITIES"
              value = "compute,utility"
            }
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

        # Toleration for GPU nodes
        dynamic "toleration" {
          for_each = data.coder_parameter.enable_gpu.value ? [1] : []
          content {
            key      = "nvidia.com/gpu"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.home]
}