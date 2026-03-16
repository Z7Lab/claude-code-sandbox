#!/bin/bash

# Auto-detect script location for portability
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SANDBOX_DIR="$SCRIPT_DIR"
CACHE_DIR="$SANDBOX_DIR/cache"
CONFIG_DIR="$CACHE_DIR/claude-config"
RESOURCES_DIR="$CONFIG_DIR/resources"
EXTRA_MOUNTS_CONF="$SANDBOX_DIR/mounts.conf"

# Resource preset definitions
declare -A PRESET_MEMORY=(
    [light]="1g"
    [medium]="2g"
    [heavy]="4g"
    [ml]="8g"
    [unlimited]=""
)
declare -A PRESET_CPUS=(
    [light]="1"
    [medium]="2"
    [heavy]="4"
    [ml]="4"
    [unlimited]=""
)
declare -A PRESET_PIDS=(
    [light]="50"
    [medium]="100"
    [heavy]="200"
    [ml]="100"
    [unlimited]=""
)
declare -A PRESET_GPU=(
    [light]="false"
    [medium]="false"
    [heavy]="false"
    [ml]="all"
    [unlimited]="false"
)

# Parse command-line arguments
MEMORY_LIMIT=""
CPU_LIMIT=""
PIDS_LIMIT=""
GPU_ENABLED="false"
PRESET=""
USE_LIMITS="ask"  # ask, yes, no
SKIP_RESOURCE_PROMPTS=false
FRESH_START=false
ENABLE_MONITORING=false
SKIP_UPDATE_CHECK=false
ALLOW_HOST_SERVICES=false  # Allow container to reach host localhost services
PORT=""  # Empty = auto-select
PORT_AUTO=true
INSTANCE_NAME=""  # Optional: user-provided instance name
CLI_MOUNTS=()  # Extra mounts from --mount flags
HEADLESS_MODE=false  # Headless mode for programmatic/dispatcher use
CUSTOM_CMD=()  # Custom command to run instead of 'claude' (everything after --)
STATUS_FILE=""  # Custom path for .sandbox-status.json (for orchestrators with concurrent jobs)
LOG_FILE=""  # Custom path for full stream-json log (headless only)

# Function to find an available port
find_available_port() {
    local start_port="${1:-3377}"
    local max_port=$((start_port + 100))
    local port=$start_port

    while [ $port -lt $max_port ]; do
        # Check if port is in use (by any process, not just Docker)
        if ! ss -tuln 2>/dev/null | grep -q ":$port " && \
           ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done

    # Fallback: return the start port and let Docker fail with clear message
    echo $start_port
    return 1
}

# Function to generate a unique container name
generate_container_name() {
    local project_name="$1"
    local port="$2"
    local instance_name="$3"

    # Clean project name for Docker (alphanumeric, hyphens, underscores only)
    local clean_project=$(basename "$project_name" | tr -cd '[:alnum:]-_' | cut -c1-20)

    if [ -n "$instance_name" ]; then
        # User-provided name
        echo "claude-sandbox-${instance_name}"
    else
        # Auto-generated: project-port
        echo "claude-sandbox-${clean_project}-${port}"
    fi
}

# Function to list running sandbox instances
list_instances() {
    echo "================================================================"
    echo "🐳 Running Claude Code Sandbox Instances"
    echo "================================================================"
    echo ""

    local instances=$(docker ps --filter "name=claude-sandbox-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)

    if [ -z "$instances" ] || [ "$(echo "$instances" | wc -l)" -le 1 ]; then
        echo "No running instances found."
    else
        echo "$instances"
    fi
    echo ""
}

# Check for --list flag early (before other argument parsing)
for arg in "$@"; do
    if [[ "$arg" == "--list" ]] || [[ "$arg" == "-l" ]]; then
        list_instances
        exit 0
    fi
done

while [[ $# -gt 0 ]]; do
    case $1 in
        --fresh)
            FRESH_START=true
            shift
            ;;
        --skip-update-check)
            SKIP_UPDATE_CHECK=true
            shift
            ;;
        --memory|-m)
            MEMORY_LIMIT="$2"
            USE_LIMITS="yes"
            SKIP_RESOURCE_PROMPTS=true
            shift 2
            ;;
        --cpus)
            CPU_LIMIT="$2"
            USE_LIMITS="yes"
            SKIP_RESOURCE_PROMPTS=true
            shift 2
            ;;
        --pids)
            PIDS_LIMIT="$2"
            USE_LIMITS="yes"
            SKIP_RESOURCE_PROMPTS=true
            shift 2
            ;;
        --gpu)
            if [ -n "$2" ] && [[ ! "$2" =~ ^-- ]]; then
                GPU_ENABLED="$2"
                shift 2
            else
                GPU_ENABLED="all"
                shift
            fi
            USE_LIMITS="yes"
            SKIP_RESOURCE_PROMPTS=true
            ;;
        --preset)
            PRESET="$2"
            USE_LIMITS="yes"
            SKIP_RESOURCE_PROMPTS=true
            shift 2
            ;;
        --unlimited)
            USE_LIMITS="no"
            SKIP_RESOURCE_PROMPTS=true
            shift
            ;;
        --monitor)
            ENABLE_MONITORING=true
            shift
            ;;
        --port)
            PORT="$2"
            PORT_AUTO=false
            shift 2
            ;;
        --name)
            INSTANCE_NAME="$2"
            shift 2
            ;;
        --allow-host-services)
            ALLOW_HOST_SERVICES=true
            shift
            ;;
        --mount)
            CLI_MOUNTS+=("$2")
            shift 2
            ;;
        --headless)
            HEADLESS_MODE=true
            SKIP_UPDATE_CHECK=true
            SKIP_RESOURCE_PROMPTS=true
            shift
            ;;
        --status-file)
            if [ -z "$2" ] || [[ "$2" =~ ^-- ]]; then
                echo "❌ ERROR: --status-file requires a path argument"
                exit 1
            fi
            STATUS_FILE="$2"
            shift 2
            ;;
        --log-file)
            if [ -z "$2" ] || [[ "$2" =~ ^-- ]]; then
                echo "❌ ERROR: --log-file requires a path argument"
                exit 1
            fi
            LOG_FILE="$2"
            shift 2
            ;;
        --)
            shift
            CUSTOM_CMD=("$@")
            break
            ;;
        --list|-l)
            # Already handled above, but include for completeness
            list_instances
            exit 0
            ;;
        *)
            PROJECT_DIR="$1"
            shift
            ;;
    esac
done

# Handle --fresh flag actions
if [ "$FRESH_START" = true ]; then
    echo "================================================================"
    echo "⚠️  CLAUDE CODE SANDBOX - FRESH START"
    echo "================================================================"
    echo ""
    echo "This will reset ONLY the Claude Code Sandbox tool (not system-wide Claude Code)."
    echo ""
    echo "This will delete:"
    echo "  • Claude credentials and session history (sandbox only)"
    echo "  • Saved configuration settings (sandbox only)"
    echo "  • Package caches inside the Docker container (pip, npm)"
    echo ""
    echo "Location: $CACHE_DIR"
    echo ""
    echo "✅ Your project files are safe - they will NOT be deleted"
    echo "✅ System-wide Claude Code installation (if any) is NOT affected"
    echo "✅ System pip/npm caches are NOT affected"
    echo ""
    echo "You will need to re-authenticate with your Anthropic account."
    echo ""
    if [ "$HEADLESS_MODE" = true ]; then
        echo "❌ ERROR: --fresh cannot be used with --headless (destructive operation requires confirmation)"
        exit 1
    else
        read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
        echo ""
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Resetting Claude Code Sandbox..."
            rm -rf "$CACHE_DIR"
            echo "✅ All data cleared"
            echo ""
        else
            echo "Cancelled. No changes made."
            exit 0
        fi
    fi
fi

# Warn if --status-file is used without --headless (it would be silently ignored)
if [ -n "$STATUS_FILE" ] && [ "$HEADLESS_MODE" != true ]; then
    echo "⚠️  Warning: --status-file is only used in --headless mode. Ignoring."
    STATUS_FILE=""
fi

# Warn if --log-file is used without --headless (it would be silently ignored)
if [ -n "$LOG_FILE" ] && [ "$HEADLESS_MODE" != true ]; then
    echo "⚠️  Warning: --log-file is only used in --headless mode. Ignoring."
    LOG_FILE=""
fi

# Create cache directories if they don't exist
mkdir -p "$CACHE_DIR/pip"
mkdir -p "$CACHE_DIR/npm"
mkdir -p "$CONFIG_DIR/.claude"
mkdir -p "$RESOURCES_DIR"

# Get project directory (current directory by default)
if [ -z "$PROJECT_DIR" ]; then
    PROJECT_DIR="$(pwd)"
fi

# Validate project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory does not exist: $PROJECT_DIR"
    exit 1
fi

# Create unique container path from host path to keep projects isolated
# Transform /home/user/my-project -> /sandboxed_home-user-my-project
CONTAINER_PATH="/sandboxed_$(echo "$PROJECT_DIR" | sed 's:^/::' | tr '/' '-' | tr ' ' '_' | tr -d "'\"")"

# ── Extra Mounts Detection ───────────────────────────────────
# Reads mounts.conf to find additional directories to mount into
# the container. All entries apply to every project.
EXTRA_MOUNT_FLAGS=""
EXTRA_MOUNT_LINES=()

if [ -f "$EXTRA_MOUNTS_CONF" ]; then
    while IFS='|' read -r conf_hostpath conf_relpath conf_mode; do
        # Skip comments and blank lines
        [[ "$conf_hostpath" =~ ^#.*$ || -z "$conf_hostpath" ]] && continue

        # Trim whitespace
        conf_hostpath=$(echo "$conf_hostpath" | xargs)
        conf_relpath=$(echo "$conf_relpath" | xargs)
        conf_mode=$(echo "$conf_mode" | xargs)

        # Expand ~ in host path
        conf_hostpath="${conf_hostpath/#\~/$HOME}"

        # Default mode to ro if not specified
        conf_mode="${conf_mode:-ro}"

        container_mount_path="$CONTAINER_PATH/$conf_relpath"

        if [ ! -e "$conf_hostpath" ]; then
            EXTRA_MOUNT_LINES+=("⚠️  $conf_hostpath does not exist (skipped)")
        elif [ ! -d "$conf_hostpath" ]; then
            EXTRA_MOUNT_LINES+=("⚠️  $conf_hostpath is not a directory (skipped)")
        elif [ ! -r "$conf_hostpath" ]; then
            EXTRA_MOUNT_LINES+=("⚠️  $conf_hostpath permission denied (skipped)")
        else
            EXTRA_MOUNT_FLAGS="$EXTRA_MOUNT_FLAGS -v $conf_hostpath:$container_mount_path:$conf_mode"
            EXTRA_MOUNT_LINES+=("$conf_hostpath → $container_mount_path ($conf_mode)")
        fi
    done < "$EXTRA_MOUNTS_CONF"
fi

# Process --mount CLI flags (format: /host/path:relative/path[:mode])
for cli_mount in "${CLI_MOUNTS[@]}"; do
    cli_hostpath=$(echo "$cli_mount" | cut -d: -f1)
    cli_relpath=$(echo "$cli_mount" | cut -d: -f2)
    cli_mode=$(echo "$cli_mount" | cut -d: -f3)

    # Expand ~ in host path
    cli_hostpath="${cli_hostpath/#\~/$HOME}"

    # Default mode to ro
    cli_mode="${cli_mode:-ro}"

    container_mount_path="$CONTAINER_PATH/$cli_relpath"

    if [ ! -e "$cli_hostpath" ]; then
        EXTRA_MOUNT_LINES+=("⚠️  $cli_hostpath does not exist (skipped)")
    elif [ ! -d "$cli_hostpath" ]; then
        EXTRA_MOUNT_LINES+=("⚠️  $cli_hostpath is not a directory (skipped)")
    elif [ ! -r "$cli_hostpath" ]; then
        EXTRA_MOUNT_LINES+=("⚠️  $cli_hostpath permission denied (skipped)")
    else
        EXTRA_MOUNT_FLAGS="$EXTRA_MOUNT_FLAGS -v $cli_hostpath:$container_mount_path:$cli_mode"
        EXTRA_MOUNT_LINES+=("$cli_hostpath → $container_mount_path ($cli_mode)")
    fi
done

# Resource config file for this project
RESOURCE_CONF_NAME="$(echo "$CONTAINER_PATH" | sed 's/^\///')"
RESOURCE_CONF="$RESOURCES_DIR/$RESOURCE_CONF_NAME.conf"

# Load saved resource settings if they exist
SAVED_MEMORY=""
SAVED_CPUS=""
SAVED_PIDS=""
SAVED_GPU="false"
if [ -f "$RESOURCE_CONF" ]; then
    source "$RESOURCE_CONF"
fi

# Apply preset if specified
if [ -n "$PRESET" ]; then
    MEMORY_LIMIT="${PRESET_MEMORY[$PRESET]}"
    CPU_LIMIT="${PRESET_CPUS[$PRESET]}"
    PIDS_LIMIT="${PRESET_PIDS[$PRESET]}"
    GPU_ENABLED="${PRESET_GPU[$PRESET]}"
fi

# Get git config with fallbacks
GIT_NAME=$(git config --global user.name 2>/dev/null || echo "Claude User")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "claude@local")

# Auto-select port if not specified (skip in headless — port is never mapped)
if [ "$HEADLESS_MODE" != true ]; then
    if [ "$PORT_AUTO" = true ] || [ -z "$PORT" ]; then
        PORT=$(find_available_port 3377)
        if [ $? -ne 0 ]; then
            echo "⚠️  Warning: Could not verify port availability. Using port $PORT"
        fi
    fi
fi

# Generate unique container name
# In headless mode without --name, use a random suffix instead of port
# to avoid collisions when multiple headless instances run concurrently
if [ "$HEADLESS_MODE" = true ] && [ -z "$INSTANCE_NAME" ]; then
    RANDOM_SUFFIX=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    CONTAINER_NAME=$(generate_container_name "$PROJECT_DIR" "$RANDOM_SUFFIX" "")
else
    CONTAINER_NAME=$(generate_container_name "$PROJECT_DIR" "$PORT" "$INSTANCE_NAME")
fi

# Check if this specific container name already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    IS_RUNNING=$(docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && echo "yes" || echo "no")

    if [ "$IS_RUNNING" = "yes" ]; then
        echo "⚠️  WARNING: Instance '$CONTAINER_NAME' is already running!"
        echo ""
        echo "Options:"
        echo "  1) Use a different port: $0 --port <number>"
        echo "  2) Use a custom name: $0 --name <name>"
        echo "  3) List running instances: $0 --list"
    else
        echo "⚠️  WARNING: A stopped container '$CONTAINER_NAME' exists"
    fi

    echo ""
    if [ "$HEADLESS_MODE" = true ]; then
        echo "❌ ERROR: Container '$CONTAINER_NAME' already exists. In headless mode, this is not auto-removed."
        echo "   Remove it manually:  docker rm -f $CONTAINER_NAME"
        echo "   Or use a unique name: --name <name>"
        exit 1
    else
        read -p "Remove existing container and continue? [y/N]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing container..."
            docker rm -f "$CONTAINER_NAME" 2>/dev/null
            echo "✅ Container removed"
            echo ""
        else
            echo "Cancelled."
            echo ""
            echo "Tip: Run '$0 --list' to see all running instances"
            exit 1
        fi
    fi
fi

# Ensure .claude.json exists as a FILE (not directory)
if [ ! -f "$CONFIG_DIR/.claude.json" ]; then
    rm -rf "$CONFIG_DIR/.claude.json"
    echo '{}' > "$CONFIG_DIR/.claude.json"
fi

# Check if this is first run (no credentials) - do this early to customize header
IS_FIRST_RUN=false
if [ ! -f "$CONFIG_DIR/.claude/.credentials.json" ]; then
    IS_FIRST_RUN=true
fi

# Skip version check entirely for custom commands (not running claude)
if [ ${#CUSTOM_CMD[@]} -gt 0 ]; then
    SKIP_UPDATE_CHECK=true
fi

# Get installed version from Docker image (only when running default claude command)
INSTALLED_VERSION=""
if [ ${#CUSTOM_CMD[@]} -eq 0 ]; then
    INSTALLED_VERSION=$(docker run --rm --entrypoint sh claude-code-sandbox -c "claude --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1" 2>/dev/null)
fi

# Initialize version check status
VERSION_CHECK_STATUS="skipped"
LATEST_VERSION=""

# Version check and update prompt (unless --skip-update-check flag is set)
if [ "$SKIP_UPDATE_CHECK" = false ]; then
    # Get latest version from npm registry (with timeout)
    # Try multiple methods in order: curl, wget, npm

    # Method 1: curl
    LATEST_VERSION=$(timeout 5 curl -s --max-time 5 https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null | grep -o '"version":"[^"]*' | cut -d'"' -f4)

    # Method 2: wget (if curl failed)
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(timeout 5 wget -qO- --timeout=5 https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null | grep -o '"version":"[^"]*' | cut -d'"' -f4)
    fi

    # Method 3: npm (if both curl and wget failed)
    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(timeout 5 npm view @anthropic-ai/claude-code version 2>/dev/null)
    fi

    # Determine version check status
    if [ -z "$LATEST_VERSION" ]; then
        VERSION_CHECK_STATUS="failed"
    elif [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        VERSION_CHECK_STATUS="up-to-date"
    elif [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
        VERSION_CHECK_STATUS="update-available"
    fi

    # Prompt for update if newer version available
    if [ "$VERSION_CHECK_STATUS" = "update-available" ]; then
        echo "================================================================"
        echo "📦 Claude Code Update Available"
        echo "================================================================"
        echo ""
        echo "   Installed version: $INSTALLED_VERSION"
        echo "   Latest version:    $LATEST_VERSION"
        echo ""
        echo "The sandbox uses a Docker image with Claude Code pre-installed."
        echo "To update, the Docker image needs to be rebuilt."
        echo ""
        read -p "Rebuild with latest version now? [Y/n]: " -n 1 -r
        echo ""
        echo ""

        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            # Ask about backup before update
            if [ -d "$CACHE_DIR/claude-config/.claude" ]; then
                echo "================================================================"
                echo "💾 BACKUP YOUR DATA?"
                echo "================================================================"
                echo ""
                echo "The Docker image rebuild should NOT affect your cache directory."
                echo "Your data is excluded from the build (see .dockerignore)."
                echo ""
                echo "However, as a safety precaution, you can backup:"
                echo "  • Authentication credentials"
                echo "  • Personal agents and slash commands"
                echo "  • Conversation history"
                echo "  • Command history and preferences"
                echo ""
                read -p "Create backup before update? [Y/n]: " -n 1 -r BACKUP_CHOICE
                echo ""
                echo ""

                if [[ ! $BACKUP_CHOICE =~ ^[Nn]$ ]]; then
                    BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                    BACKUP_DIR="$CACHE_DIR.backup-$BACKUP_TIMESTAMP"

                    echo "Creating backup..."
                    echo "Location: $BACKUP_DIR"
                    echo ""

                    if cp -r "$CACHE_DIR" "$BACKUP_DIR"; then
                        echo "✅ Backup created successfully!"
                        echo ""
                        echo "💡 To restore if needed:"
                        echo "   rm -rf $CACHE_DIR"
                        echo "   mv $BACKUP_DIR $CACHE_DIR"
                        echo ""
                    else
                        echo "❌ Backup failed!"
                        echo ""
                        read -p "Continue update anyway? [y/N]: " -n 1 -r CONTINUE_ANYWAY
                        echo ""
                        echo ""
                        if [[ ! $CONTINUE_ANYWAY =~ ^[Yy]$ ]]; then
                            echo "Update cancelled."
                            exit 0
                        fi
                    fi
                fi
            fi

            echo "================================================================"
            echo "Rebuilding Docker image with latest Claude Code..."
            echo "This may take 2-5 minutes..."
            echo ""

            if docker build --no-cache -t claude-code-sandbox "$SANDBOX_DIR"; then
                echo ""
                echo "✅ Update complete!"
                echo ""
                if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
                    echo "Your data backup is preserved at:"
                    echo "  $BACKUP_DIR"
                    echo ""
                    echo "You can safely delete it later if everything works correctly."
                    echo ""
                fi
                # Update the installed version variable for display later
                INSTALLED_VERSION="$LATEST_VERSION"
                VERSION_CHECK_STATUS="up-to-date"
            else
                echo ""
                echo "❌ Update failed. Continuing with current version ($INSTALLED_VERSION)."
                echo ""
                read -p "Press ENTER to continue..."
                echo ""
            fi
        fi
    fi
fi

# Determine display name based on whether custom command is used
if [ ${#CUSTOM_CMD[@]} -gt 0 ]; then
    PROCESS_LABEL="${CUSTOM_CMD[0]}"
else
    PROCESS_LABEL="Claude Code"
fi

# Skip all UX banners in headless mode
if [ "$HEADLESS_MODE" != true ]; then
    echo "================================================================"
    if [ "$IS_FIRST_RUN" = true ]; then
        echo "⛱️  Welcome to ${PROCESS_LABEL} Sandbox"
    else
        echo "⛱️  Welcome Back! - ${PROCESS_LABEL} Sandbox"
    fi
    echo "================================================================"
    echo ""

    # Show Claude Code version information (only for default claude command)
    if [ -n "$INSTALLED_VERSION" ]; then
        echo "📦 Claude Code Versions:"
        echo "   Installed: $INSTALLED_VERSION"

        # Show latest version and status
        if [ "$VERSION_CHECK_STATUS" = "up-to-date" ]; then
            echo "   Latest:    $LATEST_VERSION"
            echo "   Status:    ✅ Up to date"
        elif [ "$VERSION_CHECK_STATUS" = "update-available" ]; then
            echo "   Latest:    $LATEST_VERSION"
            echo "   Status:    🔔 Update available (skipped for now)"
        elif [ "$VERSION_CHECK_STATUS" = "failed" ]; then
            echo "   Latest:    ❌ Check failed (timeout or network issue)"
            echo "   Status:    ⚠️  Could not verify latest version"
        elif [ "$VERSION_CHECK_STATUS" = "skipped" ]; then
            echo "   Latest:    (check skipped with --skip-update-check)"
            echo "   Status:    ⏭️  Version check disabled"
        fi
        echo ""
    fi

    if [ "$IS_FIRST_RUN" = true ] && [ ${#CUSTOM_CMD[@]} -eq 0 ]; then
        echo "A Docker-wrapped version of Claude Code for safe isolation."
        echo ""
        echo "ℹ️  This wraps the official Claude Code in Docker for isolation."
        echo "    Official Claude Code: https://github.com/anthropics/claude-code"
        echo "    Documentation: https://docs.anthropic.com/docs/claude-code"
        echo "================================================================"
        echo ""
    fi

    # Show instance information (important for multi-instance use)
    echo "🐳 Instance Information:"
    echo "   Container name: $CONTAINER_NAME"
    if [ ${#CUSTOM_CMD[@]} -eq 0 ]; then
        echo "   Auth port:      $PORT"
        if [ "$PORT_AUTO" = true ]; then
            echo "   (Port auto-selected. Use --port <number> to specify)"
        fi
    fi
    echo ""

    # Count other running instances
    RUNNING_COUNT=$(docker ps --filter "name=claude-sandbox-" --format "{{.Names}}" 2>/dev/null | wc -l)
    if [ "$RUNNING_COUNT" -gt 0 ]; then
        echo "   📊 Other running instances: $RUNNING_COUNT"
        echo "   (Run '$0 --list' to see all)"
        echo ""
    fi

    echo "📁 Your project directory:"
    echo "   Host: $PROJECT_DIR"
    echo "   Container: $CONTAINER_PATH"
    echo ""
    echo "   → ${PROCESS_LABEL} can ONLY access files in this directory (plus any extra mounts)"
    echo "   → Each project has isolated permissions and session history"
fi  # end headless check

if [ "$HEADLESS_MODE" != true ]; then
    echo ""
    if [ ${#EXTRA_MOUNT_LINES[@]} -gt 0 ]; then
        echo "📂 Extra mounts:"
        for line in "${EXTRA_MOUNT_LINES[@]}"; do
            echo "   $line"
        done
    elif [ -f "$EXTRA_MOUNTS_CONF" ]; then
        echo "📂 Extra mounts: none for this project"
    else
        echo "📂 Extra mounts: none (see mounts.conf.example to configure)"
    fi
    echo ""
    echo "🔧 ${PROCESS_LABEL} Sandbox tool location:"
    echo "   $SANDBOX_DIR"
    echo ""
fi

# Resource limits configuration (interactive or from flags/saved settings)
if [ "$SKIP_RESOURCE_PROMPTS" = false ]; then
    echo "================================================================"
    echo "📊 RESOURCE LIMITS"
    echo "================================================================"
    echo ""

    # Check if we have saved settings
    if [ -f "$RESOURCE_CONF" ]; then
        echo "This project has saved resource settings:"
        echo ""
        [ -n "$SAVED_MEMORY" ] && echo "   Memory: $SAVED_MEMORY" || echo "   Memory: Unlimited"
        [ -n "$SAVED_CPUS" ] && echo "   CPUs: $SAVED_CPUS cores" || echo "   CPUs: Unlimited"
        [ -n "$SAVED_PIDS" ] && echo "   Max Processes: $SAVED_PIDS" || echo "   Max Processes: Unlimited"
        [ "$SAVED_GPU" != "false" ] && echo "   GPU: Enabled ($SAVED_GPU)" || echo "   GPU: Disabled"
        echo ""

        read -p "Use saved settings? [Y/n/edit]: " -r RESOURCE_CHOICE
        echo ""

        case "${RESOURCE_CHOICE,,}" in
            n|no)
                USE_LIMITS="no"
                echo "ℹ️  Using UNLIMITED resources (no limits applied)"
                echo ""
                echo "   💡 Tip: To set resource limits, rerun and choose 'edit'"
                echo ""
                ;;
            e|edit)
                # Fall through to interactive config
                ;;
            *)
                # Use saved settings
                MEMORY_LIMIT="$SAVED_MEMORY"
                CPU_LIMIT="$SAVED_CPUS"
                PIDS_LIMIT="$SAVED_PIDS"
                GPU_ENABLED="$SAVED_GPU"
                USE_LIMITS="yes"
                ;;
        esac
    fi

    # Interactive configuration if no saved settings or user chose to edit
    if [ ! -f "$RESOURCE_CONF" ] || [[ "${RESOURCE_CHOICE,,}" == "e" ]] || [[ "${RESOURCE_CHOICE,,}" == "edit" ]]; then
        echo "Resource limits prevent runaway processes and manage system load."
        echo "Leave blank (press Enter) for unlimited resources."
        echo ""
        echo "Common presets:"
        echo "  1) Light     - 1GB RAM, 1 CPU, 50 processes    (simple scripts)"
        echo "  2) Medium    - 2GB RAM, 2 CPUs, 100 processes  (typical dev work)"
        echo "  3) Heavy     - 4GB RAM, 4 CPUs, 200 processes  (builds, large projects)"
        echo "  4) ML/AI     - 8GB RAM, 4 CPUs, GPU enabled    (machine learning)"
        echo "  5) Custom    - Specify your own limits"
        echo "  6) Unlimited - No limits (default)"
        echo ""

        read -p "Choose preset [1-6] or press Enter for unlimited: " -r PRESET_CHOICE
        echo ""

        case "$PRESET_CHOICE" in
            1)
                MEMORY_LIMIT="1g"
                CPU_LIMIT="1"
                PIDS_LIMIT="50"
                GPU_ENABLED="false"
                echo "✅ Using Light preset"
                ;;
            2)
                MEMORY_LIMIT="2g"
                CPU_LIMIT="2"
                PIDS_LIMIT="100"
                GPU_ENABLED="false"
                echo "✅ Using Medium preset"
                ;;
            3)
                MEMORY_LIMIT="4g"
                CPU_LIMIT="4"
                PIDS_LIMIT="200"
                GPU_ENABLED="false"
                echo "✅ Using Heavy preset"
                ;;
            4)
                MEMORY_LIMIT="8g"
                CPU_LIMIT="4"
                PIDS_LIMIT="100"
                GPU_ENABLED="all"
                echo "✅ Using ML/AI preset"
                ;;
            5)
                echo "Custom configuration:"
                read -p "  Memory limit (e.g., 512m, 2g, 8g) [press Enter for unlimited]: " -r MEMORY_LIMIT
                read -p "  CPU limit (e.g., 1, 2, 4, 8) [press Enter for unlimited]: " -r CPU_LIMIT
                read -p "  Max processes (e.g., 50, 100, 200) [press Enter for unlimited]: " -r PIDS_LIMIT
                read -p "  GPU access? [y/N]: " -n 1 -r GPU_CHOICE
                echo ""
                if [[ $GPU_CHOICE =~ ^[Yy]$ ]]; then
                    read -p "    GPU devices (e.g., 'all', 'device=0') [default: all]: " -r GPU_DEVICE
                    GPU_ENABLED="${GPU_DEVICE:-all}"
                else
                    GPU_ENABLED="false"
                fi
                echo "✅ Custom configuration set"
                ;;
            *)
                MEMORY_LIMIT=""
                CPU_LIMIT=""
                PIDS_LIMIT=""
                GPU_ENABLED="false"
                echo "✅ Using unlimited resources"
                ;;
        esac

        # Show configured settings if any limits were set
        if [ -n "$MEMORY_LIMIT" ] || [ -n "$CPU_LIMIT" ] || [ -n "$PIDS_LIMIT" ] || [ "$GPU_ENABLED" != "false" ]; then
            echo ""
            echo "Configured limits:"
            [ -n "$MEMORY_LIMIT" ] && echo "   Memory: $MEMORY_LIMIT"
            [ -n "$CPU_LIMIT" ] && echo "   CPUs: $CPU_LIMIT cores"
            [ -n "$PIDS_LIMIT" ] && echo "   Max Processes: $PIDS_LIMIT"
            [ "$GPU_ENABLED" != "false" ] && echo "   GPU: Enabled ($GPU_ENABLED)"
            echo ""

            read -p "Save these settings for this project? [Y/n]: " -n 1 -r SAVE_CHOICE
            echo ""
            echo ""

            if [[ ! $SAVE_CHOICE =~ ^[Nn]$ ]]; then
                # Save configuration
                cat > "$RESOURCE_CONF" << EOF
# Resource limits for: $PROJECT_DIR
# Container path: $CONTAINER_PATH
# Created: $(date)
SAVED_MEMORY="$MEMORY_LIMIT"
SAVED_CPUS="$CPU_LIMIT"
SAVED_PIDS="$PIDS_LIMIT"
SAVED_GPU="$GPU_ENABLED"
EOF
                echo "✅ Settings saved for future runs"
                echo ""
            fi
        else
            echo ""
        fi
    fi
else
    # Flags were provided, show what will be used
    if [ "$USE_LIMITS" = "yes" ]; then
        echo "================================================================"
        echo "📊 RESOURCE LIMITS (from command-line flags)"
        echo "================================================================"
        echo ""
        [ -n "$MEMORY_LIMIT" ] && echo "   Memory: $MEMORY_LIMIT"
        [ -n "$CPU_LIMIT" ] && echo "   CPUs: $CPU_LIMIT cores"
        [ -n "$PIDS_LIMIT" ] && echo "   Max Processes: $PIDS_LIMIT"
        [ "$GPU_ENABLED" != "false" ] && echo "   GPU: Enabled ($GPU_ENABLED)"
        echo ""

        # Auto-save when using flags
        cat > "$RESOURCE_CONF" << EOF
# Resource limits for: $PROJECT_DIR
# Container path: $CONTAINER_PATH
# Created: $(date)
SAVED_MEMORY="$MEMORY_LIMIT"
SAVED_CPUS="$CPU_LIMIT"
SAVED_PIDS="$PIDS_LIMIT"
SAVED_GPU="$GPU_ENABLED"
EOF
    fi
fi

if [ "$HEADLESS_MODE" != true ]; then
    if [ "$IS_FIRST_RUN" = true ] && [ ${#CUSTOM_CMD[@]} -eq 0 ]; then
        echo "================================================================"
        echo "🔑 FIRST RUN - AUTHENTICATION REQUIRED"
        echo "================================================================"
        echo ""
        echo "This sandbox runs the official Claude Code inside Docker."
        echo ""
        echo "Authentication:"
        echo "   • A link will be provided to authenticate via browser"
        echo "   • Login with your Anthropic account"
        echo "   • Choose: Claude subscription (Pro/Team) or API account"
        echo ""
        echo "Credentials saved to:"
        echo "   $CONFIG_DIR/.claude/"
        echo ""
        echo "================================================================"
        echo "⚠️  IMPORTANT - READ BEFORE STARTING"
        echo "================================================================"
        echo ""
        echo "Inside the sandbox, your project appears as:"
        echo "   $CONTAINER_PATH"
        echo ""
        echo "Always reference files as:"
        echo "   ✅ $CONTAINER_PATH/src/app.py"
        echo "   ✅ $CONTAINER_PATH/tests/test.py"
        echo ""
        echo "NOT as:"
        echo "   ❌ $PROJECT_DIR/src/app.py"
        echo ""
        echo "When Claude asks 'Do you trust $CONTAINER_PATH?'"
        echo "   → Answer YES"
        echo "   → This IS your isolated project directory"
        echo "   → Docker isolation protects your system"
        echo ""
        echo "================================================================"
        if [ ${#EXTRA_MOUNT_LINES[@]} -gt 0 ]; then
            echo ""
            echo "📂 Extra mounts:"
            for line in "${EXTRA_MOUNT_LINES[@]}"; do
                echo "   $line"
            done
        fi
        echo ""
        read -p "Press ENTER to start (or Ctrl+C to cancel)... "
        echo ""
    else
        echo "💡 REMINDER: Use container path when prompting ${PROCESS_LABEL}"
        echo ""
        echo "   ${PROCESS_LABEL} sees:"
        echo "   ✅ $CONTAINER_PATH/yourfile.py"
        echo ""
        echo "   NOT your host path:"
        echo "   ❌ $PROJECT_DIR/yourfile.py"
        if [ ${#EXTRA_MOUNT_LINES[@]} -gt 0 ]; then
            echo ""
            echo "📂 Extra mounts:"
            for line in "${EXTRA_MOUNT_LINES[@]}"; do
                echo "   $line"
            done
        fi
        echo ""
        read -p "Press ENTER to start (or Ctrl+C to cancel)... "
        echo ""
    fi

    echo "Starting ${PROCESS_LABEL} in isolated Docker container..."
    echo "Press Ctrl+C to exit"
    echo "================================================================"
    echo ""
fi

# Setup monitoring if enabled
STATS_LOG=""
MONITOR_PID=""
if [ "$ENABLE_MONITORING" = true ]; then
    # Generate unique log filename with project name and timestamp
    PROJECT_NAME=$(basename "$PROJECT_DIR")
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    STATS_LOG="$CACHE_DIR/docker-stats-${PROJECT_NAME}-${TIMESTAMP}.log"
    echo "📊 Resource monitoring enabled"
    echo ""

    # Detect if running in tmux
    if [ -n "$TMUX" ]; then
        echo "💡 TIP: You're in tmux! Open a split pane to watch stats:"
        echo '   Ctrl+b then %  (or Ctrl+b then ")  - split pane'
        echo "   tail -f $STATS_LOG"
        echo ""
    else
        echo "💡 To view live stats, open another terminal and run:"
        echo "   tail -f $STATS_LOG"
        echo ""
    fi

    echo "   Stats are being logged to:"
    echo "   $STATS_LOG"
    echo ""
    echo "================================================================"
    echo ""
fi

# Build resource flags for Docker
RESOURCE_FLAGS=""
if [ -n "$MEMORY_LIMIT" ]; then
    RESOURCE_FLAGS="$RESOURCE_FLAGS --memory=$MEMORY_LIMIT"
fi
if [ -n "$CPU_LIMIT" ]; then
    RESOURCE_FLAGS="$RESOURCE_FLAGS --cpus=$CPU_LIMIT"
fi
if [ -n "$PIDS_LIMIT" ]; then
    RESOURCE_FLAGS="$RESOURCE_FLAGS --pids-limit=$PIDS_LIMIT"
fi
if [ "$GPU_ENABLED" != "false" ] && [ -n "$GPU_ENABLED" ]; then
    RESOURCE_FLAGS="$RESOURCE_FLAGS --gpus=$GPU_ENABLED"
fi

# Start background monitoring if enabled
if [ "$ENABLE_MONITORING" = true ]; then
    {
        # Wait for container to be running
        for i in {1..30}; do
            if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                break
            fi
            sleep 0.5
        done

        # Start monitoring
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "==================================================================" > "$STATS_LOG"
            echo "📊 Resource Monitoring - Started $(date)" >> "$STATS_LOG"
            echo "==================================================================" >> "$STATS_LOG"
            echo "" >> "$STATS_LOG"

            # Run docker stats with formatting
            docker stats "$CONTAINER_NAME" \
                --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}\t{{.PIDs}}" \
                >> "$STATS_LOG" 2>&1
        fi
    } &
    MONITOR_PID=$!
fi

# Build host access flag if enabled
HOST_ACCESS_FLAG=""
if [ "$ALLOW_HOST_SERVICES" = true ]; then
    HOST_ACCESS_FLAG="--add-host=host.docker.internal:host-gateway"
fi

# Build docker run flags based on mode
if [ "$HEADLESS_MODE" = true ]; then
    DOCKER_RUN_FLAGS="-i --rm"
else
    DOCKER_RUN_FLAGS="-it --rm"
fi

# Build port mapping flag (skip in headless mode)
PORT_FLAG=""
if [ "$HEADLESS_MODE" != true ]; then
    PORT_FLAG="-p $PORT:3000"
fi

# Determine the command to run
if [ ${#CUSTOM_CMD[@]} -gt 0 ]; then
    CONTAINER_CMD=("${CUSTOM_CMD[@]}")
else
    CONTAINER_CMD=("claude")
fi

# Record start time for status file
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# In headless mode, tee stdout to a temp file so we can parse status after exit.
# We filter for only the lines we need: the result event and file-modifying tool calls.
STREAM_CAPTURE_FILE=""
if [ "$HEADLESS_MODE" = true ]; then
    STREAM_CAPTURE_FILE=$(mktemp /tmp/sandbox-stream-capture.XXXXXX)
fi

# Run Docker with host user UID/GID to prevent permission issues
# Files created by the process will be owned by you, not root
# Each project gets a unique container path for isolated permissions/sessions
_run_docker() {
    docker run $DOCKER_RUN_FLAGS \
        --name "$CONTAINER_NAME" \
        $RESOURCE_FLAGS \
        --user "$(id -u):$(id -g)" \
        -e HOME=/home/claude \
        $HOST_ACCESS_FLAG \
        $PORT_FLAG \
        -v "$PROJECT_DIR:$CONTAINER_PATH:rw" \
        $EXTRA_MOUNT_FLAGS \
        -v "$CACHE_DIR/pip:/cache/pip:rw" \
        -v "$CACHE_DIR/npm:/cache/npm:rw" \
        -v "$CONFIG_DIR:/home/claude:rw" \
        -e PIP_CACHE_DIR=/cache/pip \
        -e NPM_CONFIG_CACHE=/cache/npm \
        -e GIT_AUTHOR_NAME="$GIT_NAME" \
        -e GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
        -e GIT_COMMITTER_NAME="$GIT_NAME" \
        -e GIT_COMMITTER_EMAIL="$GIT_EMAIL" \
        -w "$CONTAINER_PATH" \
        claude-code-sandbox \
        "${CONTAINER_CMD[@]}"
}

if [ -n "$STREAM_CAPTURE_FILE" ]; then
    if [ -n "$LOG_FILE" ]; then
        # Headless with --log-file: tee to both the log file and the filtered capture file
        _run_docker | tee "$LOG_FILE" >(grep -E '"type":"result"|"name":"Write"|"name":"Edit"' > "$STREAM_CAPTURE_FILE")
    else
        # Headless: tee stdout, capturing only the result line and file-modifying tool calls
        _run_docker | tee >(grep -E '"type":"result"|"name":"Write"|"name":"Edit"' > "$STREAM_CAPTURE_FILE")
    fi
    DOCKER_EXIT_CODE=${PIPESTATUS[0]}
    # Wait for process substitution to finish writing
    sleep 0.2
else
    _run_docker
    DOCKER_EXIT_CODE=$?
fi

# Record end time
FINISHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write status files for headless/programmatic use
# Files go in .claude/ (already gitignored by Claude Code)
if [ "$HEADLESS_MODE" = true ]; then
    mkdir -p "$PROJECT_DIR/.claude"
    echo "$DOCKER_EXIT_CODE" > "$PROJECT_DIR/.claude/.sandbox-exit-code"

    # Build .sandbox-status.json by merging script-known fields with parsed stream-json
    # Uses python3 to parse the result line and extract file paths from tool_use events
    _build_status_json() {
        local capture_file="$1"

        python3 -c "
import json, sys

# Script-known fields passed as arguments
script_data = {
    'container_name': sys.argv[1],
    'started_at': sys.argv[2],
    'finished_at': sys.argv[3],
    'exit_code': int(sys.argv[4]),
    'command': sys.argv[5].split('\x1f') if sys.argv[5] else [],
    'project_dir': sys.argv[6],
    'container_path': sys.argv[7],
    'resource_limits': {
        'preset': sys.argv[8] or None,
        'memory': sys.argv[9] or None,
        'cpus': sys.argv[10] or None,
        'pids': sys.argv[11] or None,
    },
    'headless': True,
}

# Read captured lines (result event + Write/Edit tool_use events)
capture_file = sys.argv[12] if len(sys.argv) > 12 else ''
lines = []
if capture_file:
    try:
        with open(capture_file) as f:
            lines = f.readlines()
    except (IOError, OSError):
        pass

# Parse the result line
parsed = {}
for line in lines:
    try:
        obj = json.loads(line)
        if obj.get('type') == 'result':
            parsed = obj
    except (json.JSONDecodeError, ValueError):
        pass

# Extract file paths from Write/Edit tool_use events
files_changed = set()
for line in lines:
    try:
        obj = json.loads(line)
        if obj.get('type') != 'assistant':
            continue
        for block in obj.get('message', {}).get('content', []):
            if block.get('type') == 'tool_use' and block.get('name') in ('Write', 'Edit'):
                fp = block.get('input', {}).get('file_path')
                if fp:
                    files_changed.add(fp)
    except (json.JSONDecodeError, ValueError):
        pass

# Merge all fields
status = {
    'container_name': script_data['container_name'],
    'session_id': parsed.get('session_id'),
    'started_at': script_data['started_at'],
    'finished_at': script_data['finished_at'],
    'exit_code': script_data['exit_code'],
    'duration_ms': parsed.get('duration_ms'),
    'num_turns': parsed.get('num_turns'),
    'cost_usd': parsed.get('total_cost_usd'),
    'result_text': parsed.get('result'),
    'files_changed': sorted(files_changed) if files_changed else None,
    'command': script_data['command'],
    'project_dir': script_data['project_dir'],
    'container_path': script_data['container_path'],
    'resource_limits': script_data['resource_limits'],
    'headless': True,
    'log_file': sys.argv[13] if len(sys.argv) > 13 and sys.argv[13] else None,
    'error': parsed.get('result', '') if parsed.get('is_error') else '',
}

json.dump(status, sys.stdout, indent=2)
print()
" \
            "$CONTAINER_NAME" \
            "$STARTED_AT" \
            "$FINISHED_AT" \
            "$DOCKER_EXIT_CODE" \
            "$(IFS=$'\x1f'; echo "${CONTAINER_CMD[*]}")" \
            "$PROJECT_DIR" \
            "$CONTAINER_PATH" \
            "$PRESET" \
            "$MEMORY_LIMIT" \
            "$CPU_LIMIT" \
            "$PIDS_LIMIT" \
            "$STREAM_CAPTURE_FILE" \
            "$LOG_FILE"
    }

    # Determine status file path: --status-file overrides, otherwise default to .claude/
    _STATUS_OUTPUT="${STATUS_FILE:-$PROJECT_DIR/.claude/.sandbox-status.json}"

    if command -v python3 &>/dev/null; then
        _build_status_json > "$_STATUS_OUTPUT" 2>/dev/null
    fi

    # Clean up temp file
    [ -f "$STREAM_CAPTURE_FILE" ] && rm -f "$STREAM_CAPTURE_FILE"
fi

# Stop monitoring if it was running
if [ -n "$MONITOR_PID" ]; then
    kill $MONITOR_PID 2>/dev/null
    wait $MONITOR_PID 2>/dev/null
fi

if [ "$HEADLESS_MODE" != true ]; then
    echo ""
    echo "================================================================"
fi

if [ $DOCKER_EXIT_CODE -ne 0 ] && [ $DOCKER_EXIT_CODE -ne 130 ]; then
    # Non-zero exit that's not Ctrl+C (130)
    echo "❌ Docker failed to start"
    echo "================================================================"
    echo ""

    # Check for port conflict first (most common issue)
    if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "address already in use\|bind.*failed"; then
        echo "💡 PORT CONFLICT DETECTED"
        echo ""
        echo "Port $PORT is already in use on your system."
        echo ""
        echo "Solutions:"
        echo "   1) The script should auto-select ports, but this one was taken"
        echo "   2) Run with a different port: $0 --port <number>"
        echo "   3) Find what's using the port: lsof -i :$PORT"
        echo ""
    # Check for GPU error (common issue)
    elif [ "$GPU_ENABLED" != "false" ] && [ -n "$GPU_ENABLED" ]; then
        echo "💡 GPU ERROR DETECTED"
        echo ""
        echo "Your system may not have:"
        echo "   • NVIDIA GPU available"
        echo "   • nvidia-docker runtime installed"
        echo "   • Proper GPU drivers configured"
        echo ""
        echo "Quick fix options:"
        echo ""
        echo "   1) Rerun and choose 'n' to saved settings, then pick a preset"
        echo "      without GPU (Light/Medium/Heavy/Unlimited)"
        echo ""
        echo "   2) Rerun and choose 'edit', then disable GPU access"
        echo ""
        echo "   3) Run with: $0 --unlimited"
        echo ""
    else
        echo "💡 TROUBLESHOOTING"
        echo ""
        echo "Common issues:"
        echo "   • Resource limits too high for your system"
        echo "   • Docker daemon not running"
        echo "   • Insufficient system resources"
        echo ""
        echo "Try:"
        echo "   1) Rerun with: $0 --unlimited"
        echo "   2) Check Docker status: docker ps"
        echo "   3) Review resource limits and try lower values"
        echo ""
    fi

    if [ -f "$RESOURCE_CONF" ] || [ -n "$MEMORY_LIMIT" ] || [ -n "$CPU_LIMIT" ] || [ -n "$PIDS_LIMIT" ]; then
        echo "Settings used in this run:"
        [ -n "$MEMORY_LIMIT" ] && echo "   Memory: $MEMORY_LIMIT" || echo "   Memory: Unlimited"
        [ -n "$CPU_LIMIT" ] && echo "   CPUs: $CPU_LIMIT cores" || echo "   CPUs: Unlimited"
        [ -n "$PIDS_LIMIT" ] && echo "   Max Processes: $PIDS_LIMIT" || echo "   Max Processes: Unlimited"
        [ "$GPU_ENABLED" != "false" ] && echo "   GPU: Enabled ($GPU_ENABLED)" || echo "   GPU: Disabled"
        echo ""
    fi

    echo "================================================================"
    exit $DOCKER_EXIT_CODE
fi

if [ "$HEADLESS_MODE" != true ]; then
    echo "${PROCESS_LABEL} session ended."
    echo "Docker container '$CONTAINER_NAME' removed."
    echo ""
fi

# Show monitoring summary if it was enabled
if [ "$ENABLE_MONITORING" = true ] && [ -f "$STATS_LOG" ]; then
    echo "================================================================"
    echo "📊 RESOURCE USAGE SUMMARY"
    echo "================================================================"
    echo ""

    # Get the last few stats entries (excluding header)
    if tail -n 5 "$STATS_LOG" | grep -q "%"; then
        echo "Final resource usage:"
        echo ""
        tail -n 6 "$STATS_LOG" | head -n 6
        echo ""
        echo "Full stats saved to:"
        echo "  $STATS_LOG"
    else
        echo "⚠️  No stats collected (container may have exited too quickly)"
        echo ""
        echo "Stats log location:"
        echo "  $STATS_LOG"
    fi
    echo ""
    echo "================================================================"
    echo ""
fi

if [ "$HEADLESS_MODE" != true ]; then
    echo "Your project files are preserved at:"
    echo "  $PROJECT_DIR"
    echo "================================================================"
fi
