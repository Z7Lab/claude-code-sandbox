# Headless & Automation Guide

> Run the sandbox programmatically — no TTY, no prompts, structured output for scripts, CI, and dispatchers.
>
> **For interactive usage**, see [GUIDE.md](GUIDE.md). For security details, see [SECURITY.md](SECURITY.md).

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [How Headless Differs from Interactive](#how-headless-differs-from-interactive)
3. [Status Files](#status-files)
   - [.sandbox-exit-code](#sandbox-exit-code)
   - [.sandbox-status.json](#sandbox-statusjson)
   - [Schema Reference](#schema-reference)
4. [Stream Logging (`--log-file`)](#stream-logging---log-file)
5. [Multi-Instance & Naming](#multi-instance--naming)
   - [Auto-Naming](#auto-naming)
   - [Deterministic Naming with --name](#deterministic-naming-with---name)
   - [Collision Behavior](#collision-behavior)
6. [Mounting Knowledge Docs](#mounting-knowledge-docs)
   - [Per-Invocation with --mount](#per-invocation-with---mount)
   - [Persistent with mounts.conf](#persistent-with-mountsconf)
   - [Telling the Agent About Mounted Docs](#telling-the-agent-about-mounted-docs)
7. [Custom Commands](#custom-commands)
8. [Safety Rules](#safety-rules)
9. [stream-json Output](#stream-json-output)
10. [Integration Patterns](#integration-patterns)
    - [Bash Scripting](#bash-scripting)
    - [Python Dispatcher](#python-dispatcher)
    - [Crash Recovery](#crash-recovery)
11. [Caveats & Limitations](#caveats--limitations)

---

## Quick Start

```bash
# Run a prompt headlessly (whitelist the tools the job needs)
./run-claude-sandboxed.sh --headless ~/myproject -- \
    claude -p "fix the tests" \
    --output-format stream-json --verbose \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"

# Or blanket-allow all tools (simpler but less precise):
#   --dangerously-skip-permissions

# Check the result
cat ~/myproject/.claude/.sandbox-exit-code        # 0, 130, or error code
cat ~/myproject/.claude/.sandbox-status.json      # structured JSON (requires python3 on host)
```

Headless mode suppresses all interactive prompts, UX banners, and version checks. The container runs without a TTY and without the OAuth port mapping, giving a tighter security posture.

> **Important:** Headless Claude use requires `--allowedTools` or `--dangerously-skip-permissions`. Without one of these, tool calls are denied (no TTY to prompt for approval). Docker provides the real isolation layer — see [Tool permissions in headless mode](#tool-permissions-in-headless-mode) and [SECURITY.md](SECURITY.md#headless-mode-and-tool-permissions) for details.

---

## How Headless Differs from Interactive

| Behavior | Interactive (default) | Headless (`--headless`) |
|---|---|---|
| TTY allocation | `-it` (interactive + TTY) | `-i` only (no TTY) |
| OAuth port mapping | `-p $PORT:3000` | Not mapped |
| UX banners / welcome text | Shown | Suppressed |
| Interactive prompts | Prompted | Destructive ops refused (see [Safety Rules](#safety-rules)) |
| Resource limits (when no flags given) | Prompted | Unlimited (no limits) |
| Version update check | Runs (unless `--skip-update-check`) | Skipped |
| Resource limit prompts | Shown (unless flags provided) | Skipped |
| Exit code file | Not written | Written to `$PROJECT_DIR/.claude/.sandbox-exit-code` |
| Status file | Not written | Written to `$PROJECT_DIR/.claude/.sandbox-status.json` |
| Container naming | `claude-sandbox-{project}-{port}` | `claude-sandbox-{project}-{random}` (8 hex chars) |
| Port scan | Scans 3377–3476 for free port | Skipped (port not mapped) |

Resource limits default to **unlimited** in headless mode. Pass `--preset` or explicit limit flags if you need constraints:

```bash
./run-claude-sandboxed.sh --headless --preset heavy ~/myproject
./run-claude-sandboxed.sh --headless --memory 4g --cpus 4 ~/myproject
```

---

## Status Files

Headless mode writes two files after the container exits. By default they go to the project directory (both are in `.gitignore`). For orchestrators running concurrent jobs against the same project directory, use `--status-file` to write to a per-job path instead.

### .sandbox-exit-code

A single integer — the process exit code:

```
0       success
130     interrupted (SIGINT / Ctrl+C)
1+      error
```

Always written. No dependencies.

```bash
EXIT_CODE=$(cat ~/myproject/.claude/.sandbox-exit-code)
```

### .sandbox-status.json

Structured JSON combining metadata the script knows (container name, timing, resource limits) with fields parsed from the Claude Code stream-json output (session ID, cost, turns, result text).

**Requires `python3` on the host.** If python3 is not available, this file is not written — `.sandbox-exit-code` still works as a fallback.

Example:

```json
{
  "container_name": "claude-sandbox-myproject-a3f9b2c1",
  "session_id": "f8a8c44b-8a71-4f9c-908c-2b694a5072c9",
  "started_at": "2026-03-15T14:30:00Z",
  "finished_at": "2026-03-15T14:35:22Z",
  "exit_code": 0,
  "duration_ms": 4505,
  "num_turns": 1,
  "cost_usd": 0.1048,
  "result_text": "Done. Added the comment at the top of main.py.",
  "files_changed": [
    "/sandboxed_home-user-myproject/main.py"
  ],
  "command": ["claude", "-p", "add a comment to main.py", "--output-format", "stream-json", "--verbose"],
  "project_dir": "/home/user/myproject",
  "container_path": "/sandboxed_home-user-myproject",
  "resource_limits": {
    "preset": "heavy",
    "memory": "4g",
    "cpus": "4",
    "pids": "200"
  },
  "headless": true,
  "log_file": null,
  "error": ""
}
```

### Schema Reference

| Field | Source | Description |
|-------|--------|-------------|
| `container_name` | Script | Docker container name |
| `session_id` | stream-json | Claude Code session ID (for resume). `null` if not running Claude or parse fails |
| `started_at` | Script | UTC ISO 8601 timestamp when `docker run` began |
| `finished_at` | Script | UTC ISO 8601 timestamp when container exited |
| `exit_code` | Script | Process exit code (0=success, 130=interrupted, other=error) |
| `duration_ms` | stream-json | Claude Code API duration in milliseconds. `null` for custom commands |
| `num_turns` | stream-json | Number of Claude conversation turns. `null` for custom commands |
| `cost_usd` | stream-json | Total API cost in USD. `null` for custom commands |
| `result_text` | stream-json | Claude's final response text. `null` for custom commands |
| `files_changed` | stream-json | Sorted list of file paths modified by Write/Edit tool calls, or `null` if none |
| `command` | Script | The command that ran inside the container |
| `project_dir` | Script | Host project directory path |
| `container_path` | Script | Container-side project path |
| `resource_limits` | Script | Object with `preset`, `memory`, `cpus`, `pids` (`null` values = unlimited) |
| `headless` | Script | Always `true` (only written in headless mode) |
| `log_file` | Script | Path to the full NDJSON stream log, or `null` if `--log-file` was not used |
| `error` | stream-json | Error text if `is_error` was true, empty string otherwise |

**"Source" column explained:**

- **Script** — the shell script knows this directly (container metadata, timing, flags)
- **stream-json** — parsed from the last `"type":"result"` line of Claude Code's `--output-format stream-json --verbose` stdout. These fields are `null` when running custom commands (not Claude) or if parsing fails

### Custom Status File Path (`--status-file`)

By default, `.sandbox-status.json` is written to the project's `.claude/` directory. When running multiple concurrent jobs against the **same** project directory, the last job to exit overwrites the file. Use `--status-file` to write to a per-job path instead:

```bash
./run-claude-sandboxed.sh --headless --status-file /tmp/status-job-42.json ~/myproject
```

**Typical orchestrator pattern:**

```python
import tempfile, os

# Create a unique status file per job
fd, status_path = tempfile.mkstemp(
    prefix=f"sandbox-status-{container_name}-",
    suffix=".json"
)
os.close(fd)

cmd = [
    "./run-claude-sandboxed.sh", "--headless",
    "--name", f"job-{job_id}",
    "--status-file", status_path,
    project_dir
]

# After job finishes, read and clean up
status = json.loads(Path(status_path).read_text())
Path(status_path).unlink()
```

`.sandbox-exit-code` is always written to `.claude/` regardless of `--status-file` (it's a simple fallback that doesn't have the same concurrency concern since it's a single integer, and the last writer's value is still a valid exit code).

---

## Stream Logging (`--log-file`)

Save the full stream-json output to a file for post-execution audit, debugging, or dispatcher consumption. The log is NDJSON format (one JSON object per line) — the same stream that flows to stdout, written to a file in parallel.

```bash
./run-claude-sandboxed.sh --headless --log-file /tmp/job-42.ndjson ~/myproject -- \
    claude -p "fix the tests" \
    --output-format stream-json --verbose \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"
```

**Key details:**

- Only available in headless mode (ignored with a warning otherwise)
- The stream still flows to stdout in real time — `--log-file` adds a copy, it doesn't redirect
- The log file path is recorded in `.sandbox-status.json` (`log_file` field) so dispatchers can find it
- Combine with `--status-file` for fully isolated per-job output:

```bash
./run-claude-sandboxed.sh --headless \
    --status-file /tmp/status-job-42.json \
    --log-file /tmp/log-job-42.ndjson \
    ~/myproject -- \
    claude -p "fix the tests" --output-format stream-json --verbose \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"
```

**Typical orchestrator pattern:**

```python
import tempfile, os

log_path = tempfile.mktemp(prefix=f"sandbox-log-{job_id}-", suffix=".ndjson")
status_path = tempfile.mktemp(prefix=f"sandbox-status-{job_id}-", suffix=".json")

cmd = [
    "./run-claude-sandboxed.sh", "--headless",
    "--name", f"job-{job_id}",
    "--status-file", status_path,
    "--log-file", log_path,
    project_dir
]

# After job finishes:
# - status_path has structured metadata
# - log_path has the full NDJSON stream for replay/audit
```

---

## Multi-Instance & Naming

### Auto-Naming

In headless mode, each launch gets a unique container name using a random 8-character hex suffix:

```
claude-sandbox-myproject-a3f9b2c1
claude-sandbox-myproject-7e2d4f10
claude-sandbox-myproject-bc91a053
```

This is safe for concurrent launches — no coordination needed:

```bash
./run-claude-sandboxed.sh --headless ~/myproject &
./run-claude-sandboxed.sh --headless ~/myproject &
./run-claude-sandboxed.sh --headless ~/myproject &
```

The container name is recorded in `.sandbox-status.json` (`container_name` field). Since containers are removed on exit (`--rm`), the status file is the only way to discover the auto-generated name after the fact.

### Deterministic Naming with --name

For tracking containers by a known name (correlating with job IDs, `docker logs`, `docker stop`):

```bash
./run-claude-sandboxed.sh --headless --name "job-${JOB_ID}" ~/myproject
# Container: claude-sandbox-job-42
```

**You are responsible for uniqueness when using `--name`.** If the name already exists, headless mode errors out (see below).

### Collision Behavior

| Scenario | Result |
|----------|--------|
| Auto-naming (no `--name`) | Random suffix — effectively no collisions |
| `--name job-42`, name doesn't exist | Works fine |
| `--name job-42`, name already exists (running or stopped) | **Exit code 1** — refuses to auto-remove |

Headless mode **never** auto-removes an existing container. This prevents silently killing another job's running sandbox.

To clean up a stale container programmatically:

```bash
docker rm -f "claude-sandbox-job-42" 2>/dev/null
```

---

## Mounting Knowledge Docs

Mount organizational knowledge docs, coding standards, or reference materials into the sandbox so the agent can access them alongside the project files. Docs appear as a subdirectory of the project inside the container — readable with `Read`, searchable with `Glob`/`Grep`.

### Per-Invocation with `--mount`

Pass `--mount` to mount a host directory for a single run:

```bash
./run-claude-sandboxed.sh --headless \
    --mount ~/docs/coding-standards:knowledge_docs:ro \
    ~/myproject -- \
    claude -p "refactor auth module following our coding standards" \
    --output-format stream-json --verbose \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"
```

Format: `/host/path:relative/path[:mode]` — mode defaults to `ro` (read-only).

The docs appear at `./knowledge_docs/` inside the container, relative to the project root.

### Persistent with `mounts.conf`

For docs that should be available in every sandbox run, add an entry to `mounts.conf`:

```bash
cp mounts.conf.example mounts.conf
```

Then add:

```
~/docs/coding-standards|knowledge_docs|ro
```

Format: `host_path|relative_path|mode` (pipe-delimited). See `mounts.conf.example` for more examples.

`mounts.conf` entries apply to all projects — both interactive and headless. Changes take effect on the next run.

### Telling the Agent About Mounted Docs

The mount alone isn't enough — the agent needs to know the docs exist. Include a pointer in the task prompt:

```bash
claude -p "Organizational knowledge docs are mounted read-only at ./knowledge_docs/.
Use 'Glob knowledge_docs/**/*.md' to discover available references.
Key docs: style-guide.md, api-conventions.md

Now: refactor the auth module following our coding standards." \
    --output-format stream-json --verbose \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"
```

For dispatchers, append the knowledge pointer to the task prompt programmatically:

```python
knowledge_hint = """
Organizational knowledge docs are available at ./knowledge_docs/.
Use `Glob knowledge_docs/**/*.md` to discover references.
"""

full_prompt = f"{knowledge_hint}\n\n{user_task}"
```

**Concurrent safety:** Multiple sandbox instances can share the same `--mount` source directory safely. Read-only mounts (`ro`) have no write contention. Each instance has its own container and its own `--status-file` / `--log-file` paths — the shared mount doesn't interfere.

---

## Custom Commands

Use `--` to run a different command inside the sandbox instead of `claude`:

```bash
# Run a Python script
./run-claude-sandboxed.sh --headless ~/myproject -- python3 my_script.py

# Run a shell command
./run-claude-sandboxed.sh --headless ~/myproject -- bash -c "npm test && npm run build"
```

When using custom commands:

- Version checks are automatically skipped (not relevant)
- The stream-json fields in `.sandbox-status.json` (`session_id`, `cost_usd`, `num_turns`, `result_text`) will be `null` since the output isn't Claude Code stream-json format
- All sandbox features (volumes, user mapping, resource limits, extra mounts) apply unchanged

---

## Safety Rules

Headless mode **refuses** destructive operations that would normally prompt for confirmation. Instead of auto-confirming, it exits with code 1:

- **`--fresh`** (wipes cache/credentials): refused — run `--fresh` interactively
- **Container name collision**: refused — use `--name <unique>` or remove the existing container first

This prevents silent data loss in CI/automation pipelines.

---

## stream-json Output

When running `claude -p "prompt" --output-format stream-json --verbose`, Claude Code emits newline-delimited JSON (NDJSON). Each line is a complete JSON object with a `type` field.

**Key event types:**

| Type | When | Contains |
|------|------|----------|
| `system` (subtype `init`) | First line | `session_id`, `tools`, `model`, `claude_code_version` |
| `assistant` | During generation | Model response content, tool use |
| `result` | Last line | `session_id`, `exit_code`, `duration_ms`, `num_turns`, `total_cost_usd`, `result` text, `is_error` |

**The script only parses the last `result` line.** In headless mode, stdout is `tee`'d through a ring buffer (last 50 lines) to a temp file. After the container exits, the script greps for `"type":"result"` and passes it to python3 for JSON extraction. The temp file is cleaned up afterward.

**Important:** `--output-format stream-json` requires `--verbose` when used with `-p` (headless print mode). Without `--verbose`, Claude Code will error.

**The stream still flows to stdout in real time.** The `tee` is transparent — if your dispatcher reads stdout (e.g., for real-time progress), it gets the full stream. The temp file is just for post-exit parsing.

---

## Integration Patterns

### Bash Scripting

```bash
#!/bin/bash

# Launch and wait
./run-claude-sandboxed.sh --headless --preset heavy ~/myproject -- \
    claude -p "fix the tests" \
    --output-format stream-json --verbose \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"

# Check exit code
EXIT_CODE=$(cat ~/myproject/.claude/.sandbox-exit-code)
if [ "$EXIT_CODE" -ne 0 ]; then
    echo "Failed with exit code $EXIT_CODE"
    exit 1
fi

# Read structured result (if python3 was available)
if [ -f ~/myproject/.claude/.sandbox-status.json ]; then
    python3 -c "
import json
status = json.load(open('$HOME/myproject/.claude/.sandbox-status.json'))
print(f\"Cost: \${status['cost_usd']}, Turns: {status['num_turns']}\")
"
fi
```

### Python Dispatcher

```python
import json
import subprocess
from pathlib import Path

def run_sandbox(project_dir: str, prompt: str, name: str = None) -> dict:
    cmd = ["./run-claude-sandboxed.sh", "--headless"]
    if name:
        cmd += ["--name", name]
    cmd += [project_dir, "--",
            "claude", "-p", prompt,
            "--output-format", "stream-json", "--verbose",
            "--allowedTools", "Read,Write,Edit,Bash,Glob,Grep"]

    proc = subprocess.run(cmd, capture_output=False)

    # Read status file
    status_file = Path(project_dir) / ".claude" / ".sandbox-status.json"
    if status_file.exists():
        return json.loads(status_file.read_text())

    # Fallback to exit code only
    exit_file = Path(project_dir) / ".claude" / ".sandbox-exit-code"
    return {"exit_code": int(exit_file.read_text().strip())}

result = run_sandbox("/home/user/myproject", "fix the failing tests", name="fix-tests")
print(f"Exit: {result['exit_code']}, Session: {result.get('session_id')}")
```

### Crash Recovery

If your dispatcher/orchestrator crashes while a sandbox is running, the container finishes independently (it's a detached Docker process from the host's perspective). When it exits:

- `.claude/.sandbox-exit-code` is written
- `.claude/.sandbox-status.json` is written (if python3 available)
- The container is removed (`--rm`)

On restart, your dispatcher can scan project directories for status files to recover results:

```python
from pathlib import Path
import json

def recover_results(project_dirs: list[str]) -> list[dict]:
    results = []
    for proj in project_dirs:
        status = Path(proj) / ".claude" / ".sandbox-status.json"
        if status.exists():
            results.append(json.loads(status.read_text()))
    return results
```

The status file persists until overwritten by the next headless run against the same project directory.

---

## Caveats & Limitations

### `files_changed` extraction

`files_changed` is populated by parsing `assistant` events in the stream for Write/Edit tool_use calls. It captures `file_path` from the tool input. This means:

- Only Write and Edit tool calls are tracked (not Bash commands that may modify files)
- Paths are container paths (e.g., `/sandboxed_home-user-myproject/src/app.py`)
- If no Write/Edit calls occurred, the field is `null`
- If your real-time stream parser also tracks files, it may have a more complete picture (e.g., Bash-based file modifications)

### Same project directory, multiple concurrent instances

If you launch multiple headless instances against the **same project directory**, they all write to the same `.claude/.sandbox-exit-code` and (by default) `.claude/.sandbox-status.json`. The last one to exit wins. Solutions:

- **Use `--status-file`** to write each job's status to a unique path (recommended for orchestrators)
- Use different project directories per job (already isolated)
- Read the status file immediately after each job finishes

### python3 required for `.sandbox-status.json`

The status file is built by an inline python3 script on the host. If python3 is not installed, only `.claude/.sandbox-exit-code` is written. The container itself doesn't need python3 (it has it in the image), but the host does for post-exit parsing.

### Tool permissions in headless mode

Claude Code's permission system prompts the user before executing tool calls (Write, Edit, Bash, etc.). In headless mode there's no TTY to show prompts, so tool calls are denied by default. You need one of these approaches:

**Option 1: `--allowedTools`** (recommended) — explicit whitelist of permitted tools:

```bash
./run-claude-sandboxed.sh --headless ~/myproject -- \
    claude -p "fix the bug" --output-format stream-json --verbose \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep"
```

**Option 2: `--dangerously-skip-permissions`** — blanket allow all tools:

```bash
./run-claude-sandboxed.sh --headless ~/myproject -- \
    claude -p "fix the bug" --output-format stream-json --verbose \
    --dangerously-skip-permissions
```

`--allowedTools` is more precise — you control exactly which tools the job can use. `--dangerously-skip-permissions` is the simpler catch-all. Either works; without one of them, tool calls will be denied.

**Available tools** (from Claude Code v2.1.76 `system` init event — this list may change between versions; the init event in stream-json output always contains the current set):

| Tool | Purpose |
|------|---------|
| `Read` | Read file contents |
| `Write` | Create or overwrite files |
| `Edit` | Modify files (search/replace) |
| `Bash` | Run shell commands (covers curl, git, npm, pip, etc.) |
| `Glob` | Find files by name pattern |
| `Grep` | Search file contents by regex |
| `WebFetch` | Fetch a URL |
| `WebSearch` | Web search |
| `NotebookEdit` | Edit Jupyter notebook cells |
| `Task`, `TaskOutput`, `TaskStop` | Launch and manage sub-agent tasks |
| `TodoWrite` | Create/update task lists |
| `ToolSearch` | Look up deferred tools |
| `Skill` | Invoke slash commands |
| `AskUserQuestion` | Prompt the user (won't work headless — avoid) |
| `EnterPlanMode`, `ExitPlanMode` | Toggle planning mode |
| `EnterWorktree`, `ExitWorktree` | Git worktree isolation |
| `CronCreate`, `CronDelete`, `CronList` | Scheduled tasks |

**Common whitelist for typical coding jobs:**

```
--allowedTools "Read,Write,Edit,Bash,Glob,Grep"
```

Add `WebFetch` or `WebSearch` if the job needs internet access. Add `Task,TaskOutput,TaskStop` if using sub-agents.

**Why both approaches are safe in the sandbox:** The "dangerous" in the flag name refers to running on a bare host where Claude would have unrestricted access to your filesystem, SSH keys, etc. Inside the Docker sandbox, kernel-level isolation already constrains what Claude can access — only the mounted project directory and caches. The permission system is redundant with Docker's isolation, so skipping it doesn't reduce security.

Neither flag is needed when running custom commands (e.g., `-- python3 script.py`) since those don't go through Claude's permission system.

### `--max-turns` for session length control

`--max-turns N` limits how many tool-call rounds Claude Code can make before the session stops. Each "turn" is one cycle of: Claude thinks → calls a tool → gets the result → thinks again.

```bash
./run-claude-sandboxed.sh --headless ~/myproject -- \
    claude -p "fix the tests" --output-format stream-json --verbose \
    --dangerously-skip-permissions --max-turns 20
```

When the limit is reached, the session ends with `stop_reason: "max_turns"` in the stream-json result event. The exit code is still 0 (not an error — the agent simply ran out of steps).

**Choosing a value:**

| Task type | Suggested max-turns | Why |
|-----------|-------------------|-----|
| Simple file edit, add a comment | 5-10 | 2-3 turns for read + edit + verify |
| Standard coding task | 15-20 | Read files, plan, implement, test |
| Complex multi-file refactoring | 25-35 | Many files to read, edit, cross-reference |
| Open-ended research + implementation | 30-50 | Agent needs room to explore and iterate |

**Without `--max-turns`:** Claude Code runs until it decides it's done (`stop_reason: "end_turn"`) or hits an error. For automated/orchestrated use, always set a limit to prevent runaway sessions.

**Prompt tip for orchestrators:** If your agent needs to perform a signaling action after its main work (e.g., calling an API to report completion), put that step early in the prompt — before optional verification steps. This ensures the signal fires even if the agent runs out of turns during polish.

### `--resume` for multi-turn headless sessions

By default, each headless invocation (`claude -p "..."`) is a standalone session — no memory of previous runs. Use `--resume SESSION_ID` to continue a previous session:

```bash
# Turn 1: analyze the project (session ID auto-generated)
./run-claude-sandboxed.sh --headless ~/myproject -- \
    claude -p "Analyze the project architecture" \
    --output-format stream-json --verbose \
    --dangerously-skip-permissions

# Read the session ID from the status file
SESSION=$(python3 -c "import json; print(json.load(open('myproject/.claude/.sandbox-status.json'))['session_id'])")

# Turn 2: resume the same session in a new container
./run-claude-sandboxed.sh --headless ~/myproject -- \
    claude -p "Now implement the refactoring we discussed" \
    --resume "$SESSION" \
    --output-format stream-json --verbose \
    --dangerously-skip-permissions
```

On turn 2, Claude Code loads the full conversation history from turn 1. The agent remembers what it read, decided, and wrote — no need to re-read everything.

**Where sessions are stored:** `~/.claude/projects/{project-path}/` as JSONL files. In the sandbox, this maps to `cache/claude-config/.claude/projects/-sandboxed-{path}/`. The cache directory is a Docker volume mount, so **sessions survive container restarts.**

**How to get the session ID:** Read it from:
- `.claude/.sandbox-status.json` → `session_id` field (after container exits)
- The stream-json `result` event → `session_id` field (during execution)
- The stream-json `system` init event → `session_id` field (at start)

**Important:** `--session-id "custom-name"` does NOT work for resume — it requires a UUID and cannot reuse a completed session. Always use `--resume` with the UUID from the previous run.

**When to resume vs start fresh:**

| Scenario | Approach |
|----------|----------|
| Agent ran out of turns, needs to finish | `--resume SESSION_ID` — avoids re-reading everything |
| Continuing a multi-step task | `--resume SESSION_ID` — agent keeps its reasoning |
| Starting a different task on the same project | No resume — new session, different context |
| Starting work on a new project | No resume — fresh session |

**Verified:** `--resume` works with `-p` (headless) across Docker container relaunches. The agent retains full context from previous turns including tool results, reasoning, and file contents read.

### Agent prompts that curl external APIs may trigger safety refusal

Claude Code has a safety heuristic that detects prompt injection patterns. If the agent's task prompt tells it to:

1. Contact an external API with an authentication token
2. Read instructions from the response
3. Modify files based on those instructions

Claude Code may refuse the entire prompt as a suspected injection attack, even though the instructions are legitimate. The symptom is a 1-turn session where the agent says "I'm not going to follow these instructions" and exits.

**This happens with curl-based agent coordination** — e.g., telling an agent to `curl -H "X-Token: ..." http://platform/agent/messages` and then act on what it reads. The pattern of "fetch remote commands and execute them" is exactly what prompt injection looks like.

**Fix: use MCP instead of curl.** MCP tools are registered at startup as trusted capabilities. Claude Code does not apply prompt injection heuristics to its own registered MCP tools. An agent calling `platform.read_messages()` via MCP is safe; an agent running `curl ... | act on result` in the prompt may be refused.

If MCP is not available, mitigate by:
- Including the full context directly in the prompt instead of telling the agent to fetch it
- Avoiding patterns where the agent fetches instructions from an API and then executes them
- Keeping auth tokens out of the visible prompt text (use environment variables)

### `--verbose` required for stream-json

Claude Code requires `--verbose` when combining `-p` with `--output-format stream-json`. Without it, the CLI exits with an error. Make sure your commands include both flags.

### Authentication must happen interactively first

Headless mode does not map the OAuth port (`-p $PORT:3000`), so the browser-based authentication flow cannot complete. You must authenticate interactively at least once before using headless mode. Credentials are stored in the cache directory and reused across sessions.

### Detecting completion

**The only definitive signal that a sandbox job is done is the Docker container exiting.** Do not rely on stream-json events.

The stream-json `result` event (with `stop_reason: "end_turn"` or `"max_turns"`) means the Claude API session ended, but:
- A tool call may still be executing (e.g., a long `Bash` command or file write)
- The sandbox script's post-exit logic (status file writing, cleanup) runs after Claude exits
- The container can be actively modifying files for minutes after the `result` event

**For orchestrators / dispatchers:**

```bash
# Definitive: wait for container to exit
docker wait "claude-sandbox-myproject-abc123"

# Or poll for container disappearance
while docker ps --filter "name=claude-sandbox-myproject-abc123" --format "{{.Names}}" | grep -q .; do
    sleep 5
done

# THEN read status files
cat ~/myproject/.claude/.sandbox-exit-code
cat ~/myproject/.claude/.sandbox-status.json
```

**Do not trust** the stream-json `result` event as "process finished." Use it for progress monitoring only.

### Container is ephemeral

Containers use `--rm` and are deleted on exit. You cannot `docker inspect` or `docker logs` a container after it finishes. The status file and log file (if `--log-file` was used) are the only post-exit records. If you need the full stream log, use `--log-file` to persist it, or capture stdout/stderr from the process.

### Claude Code hangs during MCP initialization

If Claude Code produces no stream-json output at all (just the resource banner, then nothing for minutes), the most likely cause is an MCP server that breaks the SSE streaming protocol during connection.

**Symptoms:**
- Container starts and prints resource limits, then hangs indefinitely
- No `system` init event in stream-json output
- `curl` to the MCP SSE endpoint works fine from inside the container
- Python MCP client connects and discovers tools from the host

**Common cause:** ASGI middleware on the MCP server that wraps the SSE `send` callback. SSE in ASGI works by sending `http.response.body` chunks with `more_body=True`. If middleware intercepts these chunks (e.g., to inspect response content), it can break the streaming protocol. Claude Code's MCP client connects but never receives the first SSE event, causing it to hang during initialization.

**How to diagnose:**
1. Test the MCP server from the host with a Python MCP client — if it works there but not from Claude Code in the sandbox, the issue is in how the server handles the SSE transport
2. Check if the MCP server has any ASGI middleware wrapping the SSE response
3. Look for `send` callback wrappers, response interceptors, or auth middleware that inspects response bodies

**Fix:** MCP servers should not wrap or intercept the SSE `send` callback. Auth tokens should be extracted from the request (URL query params, headers) and mapped to sessions without touching the response stream.
