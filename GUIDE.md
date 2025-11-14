# Claude Code Sandbox Usage Guide

> **Prerequisites:** Docker installed and repository cloned. See [README.md](README.md) for quickstart setup - it has everything you need to get started.

> **About isolation:** This sandbox uses Docker to provide complete system isolation. See [SECURITY.md](SECURITY.md) for how it works.

---

## Table of Contents

1. [Usage](#usage)
2. [Resource Limits](#resource-limits)
3. [Monitoring](#monitoring)
4. [What Persists](#what-persists)
5. [Troubleshooting](#troubleshooting)
6. [Advanced Configuration](#advanced-configuration)

---

## Usage

### Starting Claude Code

```bash
cd ~/myproject
run-claude-sandboxed.sh

# Or specify path
run-claude-sandboxed.sh ~/myproject
```

> **First run:** You'll get a link to authenticate via browser (one-time)
> **Subsequent runs:** Starts immediately with saved preferences

### Stopping

**Normal exit (recommended):**

Press `Ctrl+C` in the terminal running the script.

The script automatically:

- Stops Claude Code gracefully
- Stops resource monitoring (if enabled)
- Removes the Docker container (your project files and cache persist)
- Shows final resource usage (if monitoring was enabled)

> **Note:** This only removes the container, not the Docker image or cached data. See [Reset Everything](#reset-everything) to clear cached data or [Updating Claude Code](#updating-claude-code) to rebuild the image.

You'll see:

```
Claude Code session ended.
Docker container removed.
```

**Force stop (if terminal is frozen):**

```bash
# From another terminal
docker stop claude-sandboxed-session
```

**Check if still running:**

```bash
docker ps
```

### Known Limitation: Drag-and-Drop Images

Dragging images into the terminal doesn't work in sandbox mode (uses host path instead of container path).

**Workaround:**

```bash
# Copy images to project first
mkdir -p tmp
cp ~/Downloads/screenshot.png tmp/

# Then reference in Claude
You: "What UI improvements can you suggest based on /sandboxed_home-user-myproject/tmp/screenshot.png?"

Alternatively, you can "lazy prompt" by referring to the filename in tmp/ without the full container path (often works):

You: "What UI improvements should we make? See screenshot.png in tmp dir"
```

---

## Resource Limits

Control memory, CPU, and GPU usage per project to prevent Claude Code from exhausting your system resources. Useful when running intensive tasks (large builds, ML training) or working on a resource-constrained machine.

**Settings are saved per-project.** When you return to a project, you'll be prompted:

```
Use saved settings? [Y/n/edit]:
```

- **Y** (or Enter) - Use saved settings
- **n** - Use unlimited resources
- **edit** - Modify settings or choose different preset

### Presets

| Preset        | Memory | CPUs | Processes | GPU | Best For                  |
| ------------- | ------ | ---- | --------- | --- | ------------------------- |
| **light**     | 1GB    | 1    | 50        | No  | Simple scripts            |
| **medium**    | 2GB    | 2    | 100       | No  | Typical dev work          |
| **heavy**     | 4GB    | 4    | 200       | No  | Builds, large projects    |
| **ml**        | 8GB    | 4    | 100       | Yes | Machine learning          |
| **unlimited** | None   | None | None      | No  | No restrictions (default) |

### Usage

```bash
# Interactive (prompts for preset)
run-claude-sandboxed.sh ~/myproject

# Use presets
run-claude-sandboxed.sh --preset heavy ~/androidbuilder
run-claude-sandboxed.sh --preset ml ~/pytorchproject

# Custom limits
run-claude-sandboxed.sh --memory 4g --cpus 4 ~/myproject

# GPU support (requires NVIDIA GPU + drivers)
run-claude-sandboxed.sh --gpu all ~/mlproject
```

> **Settings saved:** Per-project in `~/devtools/claude-code-sandbox/cache/claude-config/resources/`

---

## Monitoring

Real-time monitoring tracks Docker container resource usage during Claude Code sessions.

### Enabling Monitoring

```bash
# Enable monitoring with --monitor flag
./run-claude-sandboxed.sh --monitor ~/myproject

# Combine with resource limits
./run-claude-sandboxed.sh --preset heavy --monitor ~/androidbuilder
./run-claude-sandboxed.sh --memory 4g --cpus 4 --monitor ~/myproject
```

### Viewing Live Stats

When monitoring is enabled, the script tells you how to view stats:

```
📊 Resource monitoring enabled

💡 To view live stats, open another terminal and run:
   tail -f ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log

   Stats are being logged to:
   ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log

================================================================
```

> **Note:** Log files are named `docker-stats-{project}-{timestamp}.log` so each project and session gets its own log file. Logs are never overwritten.

**Option 1: Separate Terminal**

```bash
# Use the exact path shown by the script
tail -f ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log
```

**Option 2: tmux Split Pane (Recommended)**

If you're running in tmux, the script detects it and suggests:

```bash
# Split pane horizontally
Ctrl+b then "

# Or split vertically
Ctrl+b then %

# In the new pane - use the path shown by the script
tail -f ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log
```

### Monitored Metrics

The monitoring system tracks:

| Metric        | Description                 | Example         |
| ------------- | --------------------------- | --------------- |
| **CPU %**     | CPU usage percentage        | `45.23%`        |
| **Mem Usage** | Memory used / limit         | `2.1GiB / 4GiB` |
| **Mem %**     | Memory percentage           | `52.5%`         |
| **Net I/O**   | Network bytes sent/received | `1.2kB / 3.4kB` |
| **Block I/O** | Disk bytes read/written     | `10MB / 5MB`    |
| **PIDs**      | Number of processes         | `23`            |

### Stats Format

The log file contains timestamped entries:

```
==================================================================
📊 Resource Monitoring - Started Mon Jan  1 10:30:15 UTC 2025
==================================================================

CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O         PIDS
45.23%    2.1GiB / 4GiB         52.5%     1.2kB / 3.4kB     10MB / 5MB        23
46.12%    2.2GiB / 4GiB         55.0%     1.5kB / 4.1kB     12MB / 6MB        25
...
```

### Post-Session Summary

When your Claude Code session ends, a summary is displayed:

```
================================================================
Claude Code session ended.
Docker container removed.

================================================================
📊 RESOURCE USAGE SUMMARY
================================================================

Final resource usage:

CPU %     MEM USAGE / LIMIT     MEM %     NET I/O           BLOCK I/O         PIDS
48.50%    2.3GiB / 4GiB         57.5%     2.1kB / 5.2kB     15MB / 8MB        24

Full stats saved to:
  ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log

================================================================

Your project files are preserved at:
  /home/user/myproject
================================================================
```

### Use Cases

**Debugging Memory Issues:**

```bash
# Enable monitoring with memory limits
./run-claude-sandboxed.sh --memory 4g --monitor ~/myproject

# Watch memory usage in real-time (use path shown by script)
tail -f ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log

# If memory approaches limit, consider:
# - Increasing limit: ./run-claude-sandboxed.sh --memory 8g ~/myproject
# - Optimizing code to use less memory
```

**Verifying CPU Usage:**

```bash
# Set CPU limits and monitor
./run-claude-sandboxed.sh --cpus 2 --monitor ~/myproject

# Check if hitting CPU limit (100% = fully using allocated CPUs)
# If consistently at 100%, might benefit from more CPUs
```

**Understanding Build Performance:**

```bash
# Monitor resource-intensive build
./run-claude-sandboxed.sh --preset heavy --monitor ~/androidapp

# Analyze stats to see:
# - Peak memory usage during gradle build
# - CPU spikes during compilation
# - Disk I/O patterns
```

### Stats Log Location

Stats are saved to:

```
~/devtools/claude-code-sandbox/cache/docker-stats-{project}-{timestamp}.log
```

Example:

```
~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log
```

**Each session creates a new log file** with the project name and timestamp. Logs are never overwritten, allowing you to compare resource usage across different sessions.

### Tips

**1. Continuous Monitoring with tmux**

```bash
# Create tmux session
tmux new -s claude-dev

# Split pane
Ctrl+b then "

# Top pane: Run Claude
./run-claude-sandboxed.sh --monitor ~/myproject

# Bottom pane: Watch stats (use path shown by script)
tail -f ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log
```

**2. Monitoring Without Limits**

```bash
# Monitor unlimited resources
./run-claude-sandboxed.sh --unlimited --monitor ~/myproject
```

**3. Retrospective Analysis**

```bash
# Run with monitoring
./run-claude-sandboxed.sh --monitor ~/myproject

# After session ends, analyze the log
less ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log

# Find peak memory usage
grep "GiB" ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-*.log | sort -k4 -hr | head -1
```

---

## What Persists

The Docker sandbox is **completely self-contained**. You don't need Claude Code installed on your system - everything runs inside the container. When the container stops, all your data persists in mounted volumes on your host machine.

### What Gets Stored

Claude Code stores data in `~/devtools/claude-code-sandbox/cache/claude-config/` which gets mounted into the Docker container:

- **Authentication** - Login credentials, API tokens
- **User Preferences** - Theme, subscription choice
- **Project Permissions** - "Allow all git operations" choices
- **Session History** - Full conversation history per project (stored in `~/devtools/claude-code-sandbox/cache/claude-config/.claude/projects/`)
- **Command History** - Previous commands (stored in `~/devtools/claude-code-sandbox/cache/claude-config/.claude/history.jsonl`)
- **Package Caches** - npm/pip downloads (stored in `~/devtools/claude-code-sandbox/cache/pip/` and `~/devtools/claude-code-sandbox/cache/npm/`)

> **Everything persists!** When you restart, Claude remembers your preferences, permissions, and history.

### Per-Project Isolation

Each project gets a unique container path based on its location, ensuring complete isolation:

```bash
~/companyapp/     →  /sandboxed_home-user-companyapp/
~/personalsite/   →  /sandboxed_home-user-personalsite/
```

Benefits:

- Separate permissions per project
- Separate session history per project
- Different security settings for trusted vs untrusted code

### Custom Agents and Slash Commands

When you create custom agents or slash commands using `/agents`, there are **two storage locations**:

#### 1. Project-Level (Survives --fresh)

**Location:** `.claude/agents/` or `.claude/commands/` **in _your project directory_**

Example: `~/myproject/.claude/agents/my-agent.md`

**Characteristics:**

- ✅ Lives in your actual project folder (outside sandbox)
- ✅ Survives `--fresh` flag (never deleted)
- ✅ Can be committed to git for team collaboration
- ✅ Shared with anyone who clones the repo

**When to use:** Team agents, project-specific workflows, version-controlled configurations

#### 2. Personal/User-Level (Deleted by --fresh)

**Claude Code shows:** `~/.claude/agents/` or `~/.claude/commands/`
**Actually stored at:** `~/devtools/claude-code-sandbox/cache/claude-config/.claude/agents/`

**Characteristics:**

- ❌ Lives in sandbox cache (gets deleted by `--fresh`)
- ❌ Not visible in _your project directory_
- ❌ Personal to you only (not shared with team)

**When to use:** Personal agents, private workflows, user-specific preferences

> **Important:** Claude Code's UI displays container paths like `~/.claude/`, which actually map to the sandbox cache on your host. These are deleted when you run `--fresh`.

## Troubleshooting

### Port Conflicts

**Error:** `address already in use` or `failed to bind host port`

The default authentication port (3377) is already in use by another service.

**Solutions:**

**Option 1: Use a different port**

```bash
./run-claude-sandboxed.sh --port 3378
```

**Option 2: Find and stop the conflicting service**

```bash
# Find what's using the port
lsof -i :3377

# Or use netstat
netstat -tulpn | grep 3377
```

**Option 3: Change default port permanently**
Edit `run-claude-sandboxed.sh` and change `PORT="3377"` to your preferred port.

### Docker Access

#### Installing Docker (First Time)

**Don't have Docker yet?**

**Ubuntu/Debian:**

```bash
# Quick install
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add yourself to docker group
sudo usermod -aG docker $USER
newgrp docker
```

**macOS:**
Download and install [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/)

**Other platforms or detailed instructions:**
See [official Docker installation guide](https://docs.docker.com/engine/install/)

#### What You Need

The `run-claude-sandboxed.sh` script runs docker commands, so your user needs docker access.

**Most common setup (personal dev box with sudo):**

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Corporate/shared environments:**
If you don't have sudo rights, ask your system administrator to add you to the docker group or provide docker access.

#### Why This Matters for Security

While docker group access provides host-level access to Docker, this sandbox adds container-level security:

- Containers run as your user ID (not root)
- Only your project directory is accessible
- No privileged mode
- Ephemeral containers (auto-removed)

See [SECURITY.md](SECURITY.md) for complete details.

### Git Identity Error

Configure git on your host:

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

### Authentication Issues

If browser doesn't open, copy the URL from terminal output and paste in browser.

### Reset Everything

Reset the Claude Code Sandbox to factory state. This clears all cached data, authentication, and settings while preserving your project files.

#### Using --fresh Flag

The easiest method is the `--fresh` flag, which prompts for confirmation:

```bash
./run-claude-sandboxed.sh --fresh
```

**You'll see a confirmation prompt before any data is deleted:**

```
================================================================
⚠️  CLAUDE CODE SANDBOX - FRESH START
================================================================

This will reset ONLY the Claude Code Sandbox tool (not system-wide Claude Code).

This will delete:
  • Claude credentials and session history (sandbox only)
  • Saved configuration settings (sandbox only)
  • Package caches inside the Docker container (pip, npm)

Location: ~/devtools/claude-code-sandbox/cache/

✅ Your project files are safe - they will NOT be deleted
✅ System-wide Claude Code installation (if any) is NOT affected
✅ System pip/npm caches are NOT affected

You will need to re-authenticate with your Anthropic account.

Are you sure you want to continue? [y/N]:
```

#### What Gets Deleted

When you reset, `~/devtools/claude-code-sandbox/cache/` is removed, which contains:

- **Anthropic authentication** - Your Claude subscription or API account credentials
- **Claude Code settings** - Tool permissions, MCP servers, plugins, and custom commands
- **Session data** - Conversation history stored per project in `~/devtools/claude-code-sandbox/cache/claude-config/.claude/projects/`, command history in `~/devtools/claude-code-sandbox/cache/claude-config/.claude/history.jsonl`
- **Package caches** - npm/pip downloads for faster reinstalls (speeds up subsequent package installations)
- **Resource configuration** - Memory/CPU/GPU settings for all projects

> **What's safe:**
>
> - ✅ Your project files (never touched)
> - ✅ System-wide Claude Code installation (if you have one)
> - ✅ System-level pip/npm caches
> - ✅ Docker image (you keep the built sandbox image)

#### Manual Reset

If you prefer manual control or need to clean up a stuck container:

```bash
# Navigate to sandbox directory
cd ~/devtools/claude-code-sandbox

# Stop any running container
docker stop claude-sandboxed-session 2>/dev/null

# Remove all cached data
rm -rf cache/*

# Rebuild Docker image (optional - only if you changed Dockerfile)
make build
```

#### Partial Resets

> **⚠️ Advanced users only:** For most cases, use `--fresh` flag instead. Partial resets require understanding the cache structure.

**Clear only package caches (keep authentication and settings):**

```bash
cd ~/devtools/claude-code-sandbox
rm -rf cache/pip/* cache/npm/*
```

**Clear only resource configurations (keep everything else):**

```bash
cd ~/devtools/claude-code-sandbox
rm -rf cache/claude-config/resources/*
```

**What gets deleted:**

- **Authentication**: `cache/claude-config/.claude/.credentials.json` (OAuth token)
- **User preferences**: `cache/claude-config/.claude.json` (theme, settings, project configurations)
- **Conversation history**: `cache/claude-config/.claude/projects/` (per-project conversation data)
- **Command history**: `cache/claude-config/.claude/history.jsonl` (previous commands)
- **Todo items**: `cache/claude-config/.claude/todos/` (active todo lists)
- **Personal agents**: `cache/claude-config/.claude/agents/` (user-level custom agents)
- **Personal slash commands**: `cache/claude-config/.claude/commands/` (user-level custom commands)
- **Package caches**: `cache/pip/` and `cache/npm/`
- **Resource configs**: `cache/claude-config/resources/` (memory/CPU settings per project)

**What does NOT get deleted:**

- **Project agents**: `.claude/agents/` **in _your project directory_** (e.g., `~/myproject/.claude/agents/`)
- **Project slash commands**: `.claude/commands/` **in _your project directory_**
- **Your project files**: Everything in _your project directory_ stays untouched

**To clear selectively:**

```bash
# Clear only package caches (keep auth and conversations)
rm -rf ~/devtools/claude-code-sandbox/cache/pip/*
rm -rf ~/devtools/claude-code-sandbox/cache/npm/*

# Clear only conversations (keep auth and preferences)
rm -rf ~/devtools/claude-code-sandbox/cache/claude-config/.claude/projects/*
rm -f ~/devtools/claude-code-sandbox/cache/claude-config/.claude/history.jsonl
```

#### When to Use Reset

**Use `--fresh` when:**

- Switching to a different Claude account
- Authentication is broken or stuck
- You want to start completely clean
- Troubleshooting persistent issues

**Use manual cache clearing when:**

- Running low on disk space (package caches can get large)
- Want to test fresh package installations
- Debugging package-specific issues

**Don't need to reset when:**

- Updating Claude Code version (use `make update` instead)
- Switching between projects (they're already isolated)
- Changing resource limits (just rerun with new flags)

---

## Advanced Configuration

### Command-Line Flags

The `run-claude-sandboxed.sh` script supports various flags for customization:

**Port Configuration:**

```bash
# Use custom authentication port (default: 3377)
./run-claude-sandboxed.sh --port 3378
```

**Resource Limits:**

```bash
# Preset configurations
./run-claude-sandboxed.sh --preset medium
./run-claude-sandboxed.sh --preset heavy
./run-claude-sandboxed.sh --preset ml

# Custom limits
./run-claude-sandboxed.sh --memory 4g --cpus 4 --pids 200
./run-claude-sandboxed.sh --gpu all

# No limits
./run-claude-sandboxed.sh --unlimited
```

**Monitoring:**

```bash
# Enable resource monitoring
./run-claude-sandboxed.sh --monitor

# Combine with other flags
./run-claude-sandboxed.sh --preset heavy --monitor --port 3380
```

**Other Options:**

```bash
# Skip version update check
./run-claude-sandboxed.sh --skip-update-check

# Reset everything (prompts for confirmation)
./run-claude-sandboxed.sh --fresh
```

### Updating Claude Code

The script automatically checks for updates from Anthropic's official npm registry on startup and prompts you to rebuild if needed. This ensures you always have access to the latest official Claude Code release. For manual control:

**Check for updates:**

```bash
cd ~/devtools/claude-code-sandbox
make check-update
```

**Update to latest version:**

```bash
make update
# Prompts for confirmation, then rebuilds with --no-cache
```

**Force rebuild (without checking version):**

```bash
make rebuild
# Useful when: Docker cache issues, want to ensure fresh packages
```

**Manual rebuild:**

```bash
docker build --no-cache -t claude-code-sandbox .
```

**Remove image and cleanup:**

```bash
make clean
# Warning: Removes the claude-code-sandbox image, requires rebuild
```

**Skip update check when running:**

```bash
./run-claude-sandboxed.sh --skip-update-check
```

**See all available make commands:**

```bash
make help
```
