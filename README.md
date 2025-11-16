# Claude Code Sandbox

Run official [Claude Code](https://docs.anthropic.com/docs/claude-code) safely in Docker with complete system isolation.

---

## ✨ What This Does

Wraps the **official Claude Code** (always pulling the latest npm release) in Docker to provide:

- ✅ **Always up-to-date** - Uses latest official `@anthropic-ai/claude-code` from npm
- ✅ **Complete isolation** - Only your project directory is accessible
- ✅ **Resource limits** - Per-project memory/CPU/GPU control with presets
- ✅ **System protection** - No access to ~/.ssh, /etc/, or other projects, folders, or files on host system
- ✅ **Safe experimentation** - Install packages without polluting your system
- ✅ **Persistent auth** - Login once, relaunches keep you signed in
- ✅ **Flexible authentication** - Use your Claude subscription (Pro/Team) or Anthropic API account

## 🛡️ Why Docker Isolation?

Claude Code includes built-in security features, but they work at the application level. This Docker setup provides **kernel-level isolation** that cannot be bypassed, protecting against:

- Prompt injection attacks
- Compromised npm/pip packages
- Accidental destructive commands
- Credential theft attempts
- Cross-project contamination

See [SECURITY.md - Understanding the Architecture](SECURITY.md#understanding-the-architecture) for detailed explanation.

---

## 📋 Requirements

- **Docker installed** on host machine (see [GUIDE.md - Docker Access](GUIDE.md#docker-access))
  - Your user needs docker privileges to run the script. Add yourself to docker group: `sudo usermod -aG docker $USER && newgrp docker`
- **Claude subscription or Anthropic API account** (choose during first run)
- **Linux, macOS, or Windows** (with WSL2)

---

## 🚀 Quick Start

```bash
# 1. Clone and build
cd ~
mkdir -p devtools
cd devtools

git clone https://github.com/z7lab/claude-code-sandbox.git
cd claude-code-sandbox
make build

# 2. Run from any project
cd ~/myproject
~/devtools/claude-code-sandbox/run-claude-sandboxed.sh
```

> **💡 First run:** You'll get a link to authenticate via browser (Claude subscription or API account)
> **⚡ Every run after:** Starts immediately with saved preferences

> **📍 Storage location:**
> Credentials are saved in `~/devtools/claude-code-sandbox/cache/claude-config/` (on your host, but outside your project directories).
> This follows the same pattern as regular Claude Code if installed on the host (`~/.claude/`), just relocated for isolation.

### Optional: Add to PATH

**Add to `~/.bashrc` or `~/.zshrc`**

```bash
export PATH="~/devtools/claude-code-sandbox:$PATH"
```

**🔄 Then reload**

```bash
source ~/.bashrc
```

**✨ Now run from anywhere**

```bash
cd ~/myproject
run-claude-sandboxed.sh
```

---

## 💡 Usage

### Understanding the Container Environment

When you run the sandbox, your project gets a unique container path based on its location on your system.

**Path transformation example:**

```
Your computer:                 Docker container:
~/myproject/        →          /sandboxed_home-user-myproject/
  ├── src/                       ├── src/
  ├── tests/                     ├── tests/
  └── README.md                  └── README.md
```

> **Path format:** Slashes (`/`) become dashes (`-`).
> Example: if your username is `johnnyb`, then `/home/johnnyb/myproject/` → `/sandboxed_home-johnnyb-myproject`

The script shows you the container path when it starts. Use that path when talking to the sandboxed instance of Claude Code.

### Basic Workflow

**Sandbox a project**

```bash
cd ~/myproject
~/devtools/claude-code-sandbox/run-claude-sandboxed.sh
# or just the script if you've added it to your PATH
run-claude-sandboxed.sh
```

**When chatting with Claude Code inside the sandbox:**

✅ **Correct** (use the container path shown at startup):

```
You: "Fix the bug in /sandboxed_home-user-myproject/src/auth.js"
You: "Run npm test in /sandboxed_home-user-myproject/"
```

❌ **Wrong** (host paths don't exist in the container):

```
You: "Fix the bug in ~/myproject/src/auth.js"
You: "Run npm test in ~/myproject/"
```

**Exit the session:**

```bash
# Press Ctrl+C in the terminal running Claude Code in sandbox
# You'll see:
# "Claude Code session ended."
# "Docker container removed."
```

**Switch to a different project:**

```bash
cd ~/otherproject
run-claude-sandboxed.sh
```

**Each project runs in complete isolation**

---

## ⚙️ Resource Limits

Control memory, CPU, and GPU usage per project with interactive presets or command-line flags:

**Interactive (prompts for preset)**

```bash
run-claude-sandboxed.sh ~/myproject
```

**Use presets**

```bash
run-claude-sandboxed.sh --preset heavy ~/androidbuilder     # 4GB RAM, 4 CPUs
run-claude-sandboxed.sh --preset ml ~/pytorchproject        # 8GB RAM, GPU enabled
```

**Custom limits**

```bash
run-claude-sandboxed.sh --memory 4g --cpus 4 ~/myproject
```

**Presets:**

- **light** - 1GB RAM, 1 CPU (simple scripts)
- **medium** - 2GB RAM, 2 CPUs (typical dev work)
- **heavy** - 4GB RAM, 4 CPUs (builds, large projects)
- **ml** - 8GB RAM, 4 CPUs, GPU enabled (machine learning)
- **unlimited** - No limits (default)

> **💾 Settings saved:** `~/devtools/claude-code-sandbox/cache/claude-config/resources/` (per-project, reused automatically)

> **📖 See:** [GUIDE.md - Resource Limits](GUIDE.md#resource-limits) for details

---

## 📊 Resource Monitoring (Advanced)

Track CPU, memory, network, and process usage in real-time:

**Enable monitoring**

```bash
run-claude-sandboxed.sh --monitor ~/myproject
```

**With resource limits**

```bash
run-claude-sandboxed.sh --preset heavy --monitor ~/androidbuilder
```

**Viewing live stats:**

- **Open another terminal:** Use the path shown by the script (e.g., `tail -f ~/devtools/claude-code-sandbox/cache/docker-stats-myproject-20250114-013200.log`)
- Stats summary shown when session ends

> **📖 See:** [GUIDE.md - Monitoring](GUIDE.md#monitoring) for details including tmux setup

**Monitored metrics:**

- CPU usage (%)
- Memory usage (current/limit)
- Network I/O
- Disk I/O
- Process count

> **📍 Log location:** Stats are saved to `~/devtools/claude-code-sandbox/cache/docker-stats-{project}-{timestamp}.log` (in the sandbox installation directory, not your projects). Each session creates a unique log file.

> **📖 See:** [GUIDE.md - Monitoring](GUIDE.md#monitoring) for details

---

## 📁 Using tmp/ for Additional Context (Optional)

### Working with Additional Files

Claude Code running in the sandbox can only see files inside your project directory—that's the security isolation at work! If you want to share additional files like screenshots or reference documents, you'll need to copy them into your project so Claude Code in the isolated sandbox can see them. The easiest way is to create a `tmp/` folder for this. You can also use [llms.txt](https://llmstxt.org/) to provide project context—[GitIngest](https://gitingest.com) makes generating these easy.

> **💡 Note:** Custom slash commands work normally in the sandbox since they're part of your Claude Code config.
> See [GUIDE.md - Custom Agents and Slash Commands](GUIDE.md#custom-agents-and-slash-commands) for storage details.

### Setting Up tmp/

Create a `tmp/` directory (gitignore it) for content Claude Code in the sandbox can access:

- **Planning documents** - Architecture ideas, sprint notes
- **Reference docs** - API documentation, technical specs, architecture diagrams, llms.txt, etc
- **Images** - Screenshots for Claude to analyze
- **Debug outputs** - Error logs, stack traces, performance reports

### 📸 Example: Using tmp/ for Screenshots

```bash
cd ~/myproject
echo "tmp/" >> .gitignore
mkdir tmp
cp ~/Downloads/screenshot1.png tmp/
run-claude-sandboxed.sh
```

> **💡 Note:** You can add files to tmp/ before or during your session—the mounted directory updates in real-time, so Claude Code in the sandbox sees changes immediately.

**💬 Then chat with Claude Code:**

```
You: "Fix the spacing issue in /sandboxed_home-user-myproject/tmp/screenshot1.png - too much whitespace below the header"
```

### ✨ Why Use tmp/

- **Solves isolation** - Brings external files into the sandbox; stores persistent context like llms.txt
- **Clean repo** - Gitignored, keeps reference files out of version control
- **Team-friendly** - Each dev maintains their own local context

---

## 🔄 Reset Authentication & Settings

If you need to clear your sandboxed Claude Code's authentication or troubleshoot issues, use the `--fresh` flag:

```bash
run-claude-sandboxed.sh --fresh
```

This removes `~/devtools/claude-code-sandbox/cache/` which stores Claude Code's configuration:

- Authentication credentials for your Anthropic account
- Conversation history and session data (`cache/claude-config/.claude/projects/` and `cache/claude-config/.claude/history.jsonl`)
- Saved tool permissions and MCP server settings
- Package caches (pip/npm)

> **⚠️ After resetting:** You'll need to re-authenticate. Your project files, Docker image, and any system-wide Claude Code installation are never touched.

> **📖 See:** [GUIDE.md - Reset Everything](GUIDE.md#reset-everything) for complete details

---

## ❓ FAQ

**Q: Do I need to install Claude Code on my system for this to work?**

No! The Docker sandbox includes Claude Code inside the container. You don't need to install anything else. When you run `run-claude-sandboxed.sh`, it starts Claude Code in an isolated Docker environment with everything pre-installed.

**Q: I already have Claude Code installed globally. Do I need to uninstall it?**

No! The Docker sandbox runs completely independently from any global Claude Code installation. You can use both:

- Regular Claude Code: Direct system access, config in `~/.claude/`
- Docker sandbox: Isolated execution, config in `~/devtools/claude-code-sandbox/cache/claude-config/`

They don't interfere with each other and maintain separate configurations.

**Q: What happens to my settings and authentication between sessions?**

Everything persists! The sandbox stores authentication, preferences, and per-project data (conversations, permissions, settings) in `~/devtools/claude-code-sandbox/cache/claude-config/` which is mounted into the container.

> **📖 See:** [GUIDE.md - What Persists](GUIDE.md#what-persists) for details on what persists

**Q: Where are custom agents and slash commands stored?**

There are two locations:

- **Project-level** (`.claude/agents/` in your project): Survives `--fresh`, can be committed to git
- **Personal-level** (in sandbox cache): Deleted by `--fresh`, personal to you only

> **📖 See:** [GUIDE.md - Custom Agents](GUIDE.md#custom-agents-and-slash-commands) for details on when to use each

**Q: I get "port already in use" error, what do I do?**

The default authentication port (3377) is being used by another service. Run with a different port:

```bash
run-claude-sandboxed.sh --port 3378
```

> **📖 See:** [GUIDE.md - Port Conflicts](GUIDE.md#port-conflicts) for details

**Q: How do I update to the latest Claude Code version?**

The sandbox **automatically checks for updates** when you start it using multiple methods (curl, wget, npm) with network timeout handling. If a new version is available, you'll be prompted to update:

```
📦 Claude Code Update Available
   Installed version: 1.2.3
   Latest version:    1.2.4

Rebuild with latest version now? [Y/n]:
```

**You'll be prompted to backup before updates.** While the Docker rebuild shouldn't affect your cache (excluded via `.dockerignore`), you can create a timestamped safety backup:

```
~/devtools/claude-code-sandbox/cache.backup-20251116-143000/
```

This backs up your authentication, conversation history, and personal agents.

If you skip the update, the version status is shown at startup:

```
📦 Claude Code Versions:
   Installed: 1.2.3
   Latest:    1.2.4
   Status:    🔔 Update available (skipped for now)
```

**Status indicators:**

- ✅ **Up to date** - You're running the latest version
- 🔔 **Update available** - A newer version exists (you skipped updating)
- ❌ **Check failed** - Network timeout or connectivity issue (requires curl, wget, or npm installed on host machine)
- ⭐️ **Version check disabled** - Using `--skip-update-check` flag

**Manual update options:**

```bash
# Quick check for new versions of Claude Code from Anthropic
cd ~/devtools/claude-code-sandbox
make check-update

# Update to latest version
make update

# Or rebuild manually
docker build --no-cache -t claude-code-sandbox .
```

**Why can't Claude Code auto-update itself?**

Claude Code normally auto-updates via `npm i -g @anthropic-ai/claude-code`, but this doesn't work in the sandbox because:

- The Docker container is **ephemeral** (deleted when it stops via `--rm` flag)
- Updates to `/usr/local/lib/node_modules` inside the container are lost on restart
- The sandbox uses **Docker best practices**: dependencies belong in the image, not the container

To skip the automatic update check (for CI/scripts), use:

```bash
run-claude-sandboxed.sh --skip-update-check
```

---

## 📚 Documentation

- **[GUIDE.md](GUIDE.md)** - Advanced usage, troubleshooting, and configuration
- **[SECURITY.md](SECURITY.md)** - Complete security architecture and isolation

---

## 🔗 Quick Links

- [Official Claude Code Documentation](https://docs.anthropic.com/docs/claude-code)

---

## 📄 License

MIT — see [LICENSE](LICENSE)
