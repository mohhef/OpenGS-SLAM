#!/bin/bash
# OpenGS-SLAM Installation Script
# RGB-Only Gaussian Splatting SLAM for Unbounded Outdoor Scenes
# ICRA 2025

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=============================================="
echo "OpenGS-SLAM Installation"
echo "=============================================="
echo ""
echo "Installation options:"
echo "  1. Docker (recommended) - Isolated, reproducible environment"
echo "  2. Conda (manual) - Native installation with dependencies"
echo ""

# Parse arguments
USE_DOCKER=false
DOWNLOAD_CHECKPOINT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --docker)
            USE_DOCKER=true
            shift
            ;;
        --conda)
            USE_DOCKER=false
            shift
            ;;
        --no-checkpoint)
            DOWNLOAD_CHECKPOINT=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./install_all.sh [--docker|--conda] [--no-checkpoint]"
            exit 1
            ;;
    esac
done

# Default to Docker if not specified and Docker is available
if command -v docker &> /dev/null && docker info &> /dev/null; then
    if [ "$USE_DOCKER" = false ]; then
        echo "Docker is available. Use --docker for Docker installation (recommended)"
    fi
fi

# Initialize git submodules if needed
if [ ! -d "submodules/simple-knn" ] || [ ! -d "submodules/diff-gaussian-rasterization" ]; then
    echo "[0/4] Initializing git submodules..."
    git submodule update --init --recursive
fi

# Download checkpoint first (shared between Docker and conda)
if [ "$DOWNLOAD_CHECKPOINT" = true ]; then
    echo ""
    echo "[1/4] Downloading DUSt3R checkpoint..."
    mkdir -p checkpoints/

    CHECKPOINT_FILE="checkpoints/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth"
    if [ -f "$CHECKPOINT_FILE" ]; then
        echo "Checkpoint already exists: $CHECKPOINT_FILE"
    else
        echo "Downloading DUSt3R checkpoint (~330MB)..."
        wget -q --show-progress \
            https://download.europe.naverlabs.com/ComputerVision/DUSt3R/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth \
            -P checkpoints/ || {
                echo "Warning: Failed to download checkpoint. Please download manually from:"
                echo "  https://download.europe.naverlabs.com/ComputerVision/DUSt3R/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth"
            }
    fi
fi

if [ "$USE_DOCKER" = true ]; then
    # Docker installation
    echo ""
    echo "[2/4] Building Docker image..."

    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo "Error: Docker daemon is not running. Please start Docker."
        exit 1
    fi

    # Build Docker image
    docker build -t opengs-slam:latest .

    echo ""
    echo "=============================================="
    echo "Docker Installation complete!"
    echo "=============================================="
    echo ""
    echo "To use OpenGS-SLAM via Docker:"
    echo "  docker run --gpus all -v /path/to/data:/data -v /path/to/output:/output \\"
    echo "    opengs-slam:latest python slam.py --config /data/config.yaml"
    echo ""
    echo "Or use SLAMAdverserialLab integration:"
    echo "  python -m slamadverseriallab evaluate configs/experiment.yaml --slam opengsslam"

else
    # Conda installation
    echo ""
    echo "[2/4] Setting up conda environment..."

    # Detect conda installation
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        source "$HOME/miniconda3/etc/profile.d/conda.sh"
    elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        source "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        echo "Error: Could not find conda installation"
        echo "Please install Miniconda or Anaconda, or use --docker for Docker installation"
        exit 1
    fi

    # Use conda environment file (with pinned CUDA 11.8.0)
    ENV_FILE="environment_conda.yaml"
    if [ ! -f "$ENV_FILE" ]; then
        ENV_FILE="environment_flexible.yaml"
        if [ ! -f "$ENV_FILE" ]; then
            ENV_FILE="environment.yml"
        fi
    fi
    echo "Using environment file: $ENV_FILE"

    if conda env list | grep -q "^opengs-slam "; then
        echo "Environment 'opengs-slam' exists, updating..."
        conda env update -f "$ENV_FILE" --prune
    else
        echo "Creating environment 'opengs-slam'..."
        conda env create -f "$ENV_FILE"
    fi

    # Activate environment
    conda activate opengs-slam

    # Set CUDA paths
    export CUDA_HOME="$CONDA_PREFIX"
    export LD_LIBRARY_PATH="$CONDA_PREFIX/lib:$LD_LIBRARY_PATH"
    export PATH="$CONDA_PREFIX/bin:$PATH"

    # Try to use conda GCC if available
    if [ -f "$CONDA_PREFIX/bin/gcc" ]; then
        export CC="$CONDA_PREFIX/bin/gcc"
        export CXX="$CONDA_PREFIX/bin/g++"
    fi

    # Add include paths
    export CPLUS_INCLUDE_PATH="$CONDA_PREFIX/include:$CPLUS_INCLUDE_PATH"
    export C_INCLUDE_PATH="$CONDA_PREFIX/include:$C_INCLUDE_PATH"

    echo ""
    echo "[3/4] Installing Gaussian Splatting submodules..."

    # Fix numpy version
    echo "Ensuring numpy<2 for compatibility..."
    pip install "numpy>=1.24,<2" --force-reinstall

    # Install simple-knn
    if [ -d "submodules/simple-knn" ]; then
        echo "Installing simple-knn..."
        pip install submodules/simple-knn --no-build-isolation || {
            echo ""
            echo "Warning: Failed to build simple-knn. This is often due to CUDA header issues."
            echo "Consider using Docker installation instead: ./install_all.sh --docker"
        }
    fi

    # Install diff-gaussian-rasterization
    if [ -d "submodules/diff-gaussian-rasterization" ]; then
        echo "Installing diff-gaussian-rasterization..."
        pip install submodules/diff-gaussian-rasterization --no-build-isolation || {
            echo ""
            echo "Warning: Failed to build diff-gaussian-rasterization."
            echo "Consider using Docker installation instead: ./install_all.sh --docker"
        }
    fi

    # Compile RoPE CUDA kernels
    echo ""
    echo "[4/4] Compiling CUDA kernels for RoPE..."
    if [ -d "croco/models/curope" ]; then
        cd croco/models/curope/
        python setup.py build_ext --inplace || echo "Warning: Failed to compile RoPE kernels"
        cd "$SCRIPT_DIR"
    fi

    echo ""
    echo "=============================================="
    echo "Conda Installation complete!"
    echo "=============================================="
    echo ""
    echo "To use OpenGS-SLAM:"
    echo "  conda activate opengs-slam"
    echo "  python slam.py --config configs/mono/tum/freiburg1_desk.yaml"
    echo ""
    echo "Or use SLAMAdverserialLab integration:"
    echo "  python -m slamadverseriallab evaluate configs/experiment.yaml --slam opengsslam"
fi

echo ""
echo "Note: You must agree to the DUSt3R license when using this code."
