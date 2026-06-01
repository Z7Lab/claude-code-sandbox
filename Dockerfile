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
# Uses the official native installer (npm installation is deprecated)
# Use --no-cache when building to force fetching the actual latest version
RUN PATH="/root/.local/bin:${PATH}" \
    && export PATH \
    && curl -fsSL https://claude.ai/install.sh | bash \
    && cp /root/.local/bin/claude /usr/local/bin/claude \
    && chmod a+rx /usr/local/bin/claude

# Create home directory with permissive permissions (works for any UID)
# Safe because: container is isolated and ephemeral
# .local/bin and the symlink satisfy Claude Code's native-install self-check,
# which expects ~/.local/bin to exist, be on PATH, and contain the claude binary.
RUN mkdir -p /home/claude/.local/bin && chmod -R 777 /home/claude \
    && ln -s /usr/local/bin/claude /home/claude/.local/bin/claude
ENV PATH="/home/claude/.local/bin:${PATH}"

# Set up cache directories
ENV PIP_CACHE_DIR=/cache/pip
ENV NPM_CONFIG_CACHE=/cache/npm

# Expose port for authentication
EXPOSE 3000

# Entrypoint symlinks .claude.json from inside .claude/ to ~ on startup.
# This avoids Docker EBUSY errors from bind-mounting individual files
# while keeping .claude.json persistent across sessions.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod a+rx /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command
CMD ["claude"]
