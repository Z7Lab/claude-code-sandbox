# Configurable base image — override with:
#   docker build --build-arg BASE_IMAGE=python:3.13-bookworm ...
# See images.conf for available presets.
ARG BASE_IMAGE=node:20-bookworm
FROM ${BASE_IMAGE}

# Fix APT cache size issue for ARM devices (Raspberry Pi, etc.)
RUN echo 'APT::Cache-Start "100000000";' > /etc/apt/apt.conf.d/00cache

# Install Node.js if the base image doesn't include it.
# Node images already have node/npm; Python/CUDA/Ubuntu images don't.
RUN if ! command -v node >/dev/null 2>&1; then \
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
        apt-get install -y nodejs; \
    fi

# Install Python if the base image doesn't include it.
# Node images need Python added; Python images already have it.
RUN if ! command -v python3 >/dev/null 2>&1; then \
        apt-get update && apt-get install -y \
            python3 python3-pip python3-venv \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# Install common development tools (skip any already present)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    vim \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code inside the container (always get latest version)
# Use --no-cache when building to force fetching the actual latest version
RUN npm install -g @anthropic-ai/claude-code@latest

# Create home directory with permissive permissions (works for any UID)
# Safe because: container is isolated and ephemeral
RUN mkdir -p /home/claude && chmod 777 /home/claude

# Set up cache directories
ENV PIP_CACHE_DIR=/cache/pip
ENV NPM_CONFIG_CACHE=/cache/npm

# Expose port for authentication
EXPOSE 3000

# Default command
CMD ["claude"]
