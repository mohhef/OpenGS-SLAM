# OpenGS-SLAM Docker Image
# Based on PyTorch 2.1 with CUDA 11.8 (matching the conda environment)

FROM pytorch/pytorch:2.1.0-cuda11.8-cudnn8-devel

LABEL maintainer="SLAMAdverserialLab"
LABEL description="OpenGS-SLAM: RGB-Only Gaussian Splatting SLAM for Unbounded Outdoor Scenes"

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Set CUDA environment variables for build
ENV CUDA_HOME=/usr/local/cuda
ENV PATH="${CUDA_HOME}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}"
ENV TORCH_CUDA_ARCH_LIST="7.0;7.5;8.0;8.6;8.9;9.0"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    ninja-build \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libffi-dev \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Verify CUDA is available
RUN nvcc --version

# Set working directory
WORKDIR /opengs-slam

# Ensure numpy<2 for compatibility first
RUN pip install --no-cache-dir "numpy>=1.24,<2"

# Install Python dependencies via pip
RUN pip install --no-cache-dir \
    opencv-python-headless==4.8.1.78 \
    absl-py \
    addict \
    configargparse \
    einops \
    evo \
    ffmpy \
    freetype-py \
    glfw \
    gradio \
    gradio-client \
    huggingface-hub \
    imageio \
    imgviz \
    kapture \
    kapture-localization \
    lpips \
    munch \
    numpy-quaternion \
    open3d \
    piexif \
    pillow-heif \
    plotly \
    plyfile \
    poselib \
    pyglm \
    "pyglet==1.5.29" \
    pyopengl \
    pyquaternion \
    pyrender \
    python-dotenv \
    roma \
    scikit-learn \
    seaborn \
    tensorboard \
    tenacity \
    torchmetrics \
    trimesh \
    typer \
    wandb

# Copy submodules first (for layer caching)
COPY submodules/ /opengs-slam/submodules/

# Build simple-knn with verbose output
RUN cd /opengs-slam/submodules/simple-knn && \
    pip install . --no-build-isolation -v

# Build diff-gaussian-rasterization
RUN cd /opengs-slam/submodules/diff-gaussian-rasterization && \
    pip install . --no-build-isolation -v

# Copy rest of the code
COPY . /opengs-slam/

# Build CroCo/RoPE CUDA kernels if present
RUN if [ -d "/opengs-slam/croco/models/curope" ]; then \
        cd /opengs-slam/croco/models/curope && \
        python setup.py build_ext --inplace; \
    fi

# Download DUSt3R checkpoint (can be mounted instead for faster builds)
RUN mkdir -p /opengs-slam/checkpoints && \
    if [ ! -f "/opengs-slam/checkpoints/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth" ]; then \
        wget -q --show-progress \
            https://download.europe.naverlabs.com/ComputerVision/DUSt3R/DUSt3R_ViTLarge_BaseDecoder_512_dpt.pth \
            -P /opengs-slam/checkpoints/ || true; \
    fi

# Create output directory
RUN mkdir -p /output

# Default command
CMD ["python", "slam.py", "--help"]
