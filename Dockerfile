# Use a full development image with common tools
FROM node:20-bullseye

# Fix APT cache size issue for ARM devices (Raspberry Pi, etc.)
RUN echo 'APT::Cache-Start "100000000";' > /etc/apt/apt.conf.d/00cache

# Install common development tools and languages
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
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