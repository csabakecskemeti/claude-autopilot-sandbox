# Claude Autopilot Sandbox

Run Claude Code CLI autonomously in a Docker sandbox with your own local LLM. 100% local execution with full tool access for long-running, unattended task completion.

## Features

- **100% Local** - Uses your own LLM (LM Studio, Ollama, vLLM, etc.)
- **Autonomous Operation** - External supervisor agent validates task completion
- **Vision Capabilities** - Screenshot and analyze UIs, verify web apps visually
- **Full Sandbox** - Claude has unrestricted access inside the container
- **Isolated Workspaces** - Run multiple projects simultaneously

## Quick Start

```bash
# 1. Clone and configure
git clone <repository-url>
cd claude-autopilot-sandbox
cp .env.example .env
# Edit .env with your LLM settings

# 2. Build containers
./build.sh

# 3. Run with a task
./run.sh myproject "Build a todo app with React"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  HOST (run.sh controls everything)                                          │
│                                                                             │
│  ./workspaces/myproject/            → Agent's workspace                     │
│  ./workspaces/myproject-supervisor/ → Supervisor's workspaces (per turn)    │
│  ./workspaces/myproject-task/       → IMMUTABLE task storage                │
└─────────────────────────────────────────────────────────────────────────────┘
              │                         │                    │
              │ (rw)                    │ (rw)               │ (ro to both)
              ▼                         ▼                    ▼
┌──────────────────────────────┐    ┌──────────────────────────────┐
│  Agent Container             │    │  Supervisor Container        │
│                              │    │                              │
│  /home/claude/workspace (rw) │    │  /supervisor-workspaces (rw) │
│  /task (READ-ONLY)           │    │  /workspace (READ-ONLY)      │
│                              │    │  /task (READ-ONLY)           │
│  - Claude Code CLI           │───►│                              │
│  - Full tool access          │    │  - Claude Code CLI           │
│  - Skills, hooks             │    │  - Flask API (:8080)         │
│  - Autonomous mode           │    │  - Evaluates task completion │
│                              │◄───│  - Returns feedback          │
│  Stop hook calls supervisor  │    │  - Same capabilities         │
└──────────────────────────────┘    └──────────────────────────────┘
              │                                      │
              └──────────────┬───────────────────────┘
                             │
                    HTTP (OpenAI-compatible API)
                             │
              ┌──────────────────────────────┐
              │  Your LLM Backend            │
              │  (LM Studio, Ollama, etc.)   │
              └──────────────────────────────┘
```

**Key Security Properties:**
- Agent cannot modify supervisor's code or workspace
- Supervisor cannot modify agent's code (read-only access)
- Neither can modify the original task (immutable, Docker-enforced)
- Only the supervisor decides when the task is "complete"

**Both containers share the same base image (`claude-sandbox`)** with:
- Ubuntu 24.04, Python 3, Node.js
- Playwright + Chromium for browser automation
- Vision model access for screenshot analysis
- Full Claude Code CLI capabilities

## Building

```bash
# Build all containers (recommended)
./build.sh

# Build with no cache (full rebuild)
./build.sh --no-cache

# Build specific targets
./build.sh base        # Just the base image
./build.sh agent       # Base + agent
./build.sh supervisor  # Base + supervisor
```

The build script automatically builds in the correct order:
1. `claude-sandbox:latest` (shared base image)
2. Agent container
3. Supervisor container

## Running

```bash
# Basic usage - interactive mode
./run.sh myproject

# With initial task (autonomous mode)
./run.sh myproject "Build a Flask API with user authentication"

# Default workspace
./run.sh
```

Each run creates:
- `./workspaces/<name>/` - Agent's workspace (your code)
- `./workspaces/<name>-supervisor/` - Supervisor's evaluation workspaces

### Important: Switching Workspaces

The supervisor container mounts the workspace read-only. **When switching to a different workspace, you must restart the supervisor** to mount the new workspace path.

```bash
# CORRECT: Stop everything, then start new workspace
docker compose down
./run.sh newproject "Build something new"

# WRONG: Don't try to reuse running supervisor with different workspace
# The supervisor would still be looking at the old workspace!
```

**Why?** The supervisor's volume mounts are set at container start:
```
/workspace → ./workspaces/<name>/          (read-only)
/supervisor-workspaces → ./workspaces/<name>-supervisor/
```

If you skip `docker compose down`, the supervisor stays mounted to the previous workspace and will evaluate the wrong code.

### Resuming Work on Same Workspace

If you're continuing work on the **same** workspace, you can keep the supervisor running:

```bash
# First session
./run.sh myproject "Start building feature X"
# ... agent works, you exit with Ctrl+C ...

# Continue same workspace - supervisor already has correct mount
./run.sh myproject "Continue with feature X"
```

### Quick Reference

| Scenario | Command |
|----------|---------|
| New workspace | `docker compose down && ./run.sh newname "task"` |
| Same workspace (continue) | `./run.sh samename "continue task"` |
| Same workspace (fresh start) | `./run.sh samename "new task"` |
| Check running containers | `docker compose ps` |
| View supervisor logs | `docker logs claude-supervisor` |

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```env
# LLM Backend (required)
LLM_HOST=192.168.1.100          # IP of machine running LM Studio
LLM_PORT=11234
LLM_AUTH_TOKEN=lmstudio
LLM_MODEL=your-model-name

# Vision Model (optional - for screenshot analysis)
VISION_MODEL=qwen/qwen3-vl-4b

# Resource Limits
MEMORY_LIMIT=16G
MEMORY_RESERVATION=2G

# Workspace base (use internal drive on macOS to avoid exFAT issues)
# WORKSPACE_BASE=/Users/yourusername/claude-workspaces
```

### Supervisor Configuration

```env
# Supervisor evaluation limits
SUPERVISOR_MAX_LOOPS=20         # Max evaluation rounds before forcing stop
SUPERVISOR_TIMEOUT=3600         # Timeout per evaluation (seconds) - 1 hour for complex tasks

# Supervisor's own Langfuse tracing (optional)
SUPERVISOR_TRACE_TO_LANGFUSE=false
SUPERVISOR_LANGFUSE_PUBLIC_KEY=pk-lf-xxx
SUPERVISOR_LANGFUSE_SECRET_KEY=sk-lf-xxx
SUPERVISOR_LANGFUSE_PROJECT=claude-supervisor
```

### Langfuse Tracing (Optional)

Track agent sessions in Langfuse:

```env
TRACE_TO_LANGFUSE=true
LANGFUSE_PUBLIC_KEY=pk-lf-xxx
LANGFUSE_SECRET_KEY=sk-lf-xxx
LANGFUSE_HOST=http://host.docker.internal:3000
LANGFUSE_PROJECT=claude-code
```

## How the Supervisor Works

The supervisor is an **external Claude Code agent** that evaluates whether the main agent has completed its task:

```
Agent works on task
        │
        ▼
Agent tries to stop
        │
        ▼
Stop hook calls supervisor API
        │
        ▼
┌───────────────────────────────────────┐
│  Supervisor Agent                     │
│                                       │
│  1. Reads original task               │
│  2. Explores agent's workspace        │
│  3. Analyzes code, runs tests         │
│  4. Determines: complete or not?      │
│  5. Returns feedback                  │
└───────────────────────────────────────┘
        │
        ▼
   ┌────┴────┐
   │         │
complete  not_complete
   │         │
   ▼         ▼
 STOP    Agent continues
         with feedback
```

**Key features:**
- Same capabilities as agent (can read files, run tests, use browser)
- READ-ONLY access to agent workspace (can't modify agent's code)
- Isolated workspaces per evaluation turn
- Max loop limit prevents infinite loops (default: 20)

## Accessing Web Apps

When the agent runs a web server, access it from your browser with **+20000 port offset**:

| Agent says | Access from host |
|------------|------------------|
| `http://localhost:3000` | `http://localhost:23000` |
| `http://localhost:5000` | `http://localhost:25000` |
| `http://localhost:8000` | `http://localhost:28000` |
| `http://localhost:8080` | `http://localhost:28080` |

## Skills

Skills are invoked with `/skillname` syntax:

| Skill | Description |
|-------|-------------|
| `/plan` | Create implementation plan |
| `/tasks` | Track task progress |
| `/vision` | Image analysis, UI verification, OCR |
| `/webfetch` | Fetch and analyze URLs |
| `/memory` | Persistent memory across sessions |
| `/notes` | Note-taking system |

## File Structure

```
claude-autopilot-sandbox/
├── .env.example           # Configuration template
├── .env                   # Your configuration (gitignored)
├── build.sh               # Build script (builds base → agent → supervisor)
├── run.sh                 # Run script (creates workspaces, starts containers)
├── docker-compose.yml     # Service definitions
├── Dockerfile.base        # Shared base image (claude-sandbox)
├── Dockerfile             # Agent container
├── supervisor/
│   ├── Dockerfile         # Supervisor container
│   ├── app.py             # Flask API
│   ├── SUPERVISOR_PROMPT.md # Evaluation prompt
│   └── ...
├── scripts/
│   └── init-workspace.sh  # Agent workspace initialization
├── skills-backup/         # Skills (copied into agent image)
├── hooks-backup/          # Hooks (copied into agent image)
├── agents-backup/         # Subagents (copied into agent image)
├── claude-backup/
│   └── CLAUDE.md          # Instructions for agent
├── workspaces/            # Created at runtime (gitignored)
│   ├── myproject/         # Agent workspace
│   └── myproject-supervisor/ # Supervisor workspaces
└── docs/
    ├── AGENT_SUPERVISOR_PLAN.md  # Supervisor architecture details
    └── TRACING.md         # Langfuse setup guide
```

## Troubleshooting

### Build fails

```bash
# Ensure base image is built first
./build.sh base

# Then build the rest
./build.sh
```

### Cannot connect to LLM

1. Verify LLM is running: `curl http://<LLM_HOST>:<LLM_PORT>/v1/models`
2. Check `.env` settings
3. Ensure LLM is accessible from Docker (use machine IP, not localhost)

### Supervisor health check fails

```bash
# Check supervisor logs
docker logs claude-supervisor

# Test supervisor API manually
curl http://localhost:8080/health  # Won't work - internal only
docker exec claude-supervisor curl http://localhost:8080/health
```

### Agent stuck in loop

The supervisor has a max loop limit (default 20). If reached, it forces completion with a warning. Adjust with:

```env
SUPERVISOR_MAX_LOOPS=30
```

### Supervisor evaluating wrong workspace

If the supervisor approves incomplete work or reports wrong files, you probably switched workspaces without restarting:

```bash
# Fix: Always stop containers when switching workspaces
docker compose down
./run.sh newworkspace "task"
```

The supervisor mounts the workspace at startup. Switching workspaces requires a restart.

### Cannot access web app from browser

1. Add 20000 to the port
2. Ensure server binds to `0.0.0.0`, not `127.0.0.1`
3. Restart container if port mappings changed

### exFAT filesystem issues

Store workspaces on an internal APFS/HFS+ drive:

```env
WORKSPACE_BASE=/Users/yourusername/claude-workspaces
```

## Security

Both containers are secure sandboxes:
- **Isolated** - Cannot access host filesystem (except workspace)
- **Non-root** - Run as unprivileged users
- **Memory limited** - Prevents runaway processes
- **Supervisor read-only** - Cannot modify agent's work

## License

[Your license here]
