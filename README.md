# Claude Autopilot Sandbox

Run Claude Code CLI autonomously in a Docker sandbox with your own local LLM. 100% local execution with full tool access for long-running, unattended task completion.

## Features

- **100% Local** - Uses your own LLM (LM Studio, Ollama, vLLM, etc.)
- **Autonomous Operation** - External supervisor agent validates task completion
- **Multi-Instance** - Run multiple agents in parallel with auto-generated ports
- **Vision Capabilities** - Screenshot and analyze UIs, verify web apps visually
- **Full Sandbox** - Claude has unrestricted access inside the container
- **Makefile Workflow** - Simple commands for setup, build, run, and management

## Quick Start

```bash
# 1. Clone and configure
git clone <repository-url>
cd claude-autopilot-sandbox

# 2. Interactive setup wizard
make setup

# 3. Build containers
make build

# 4. Run with a task
make run W=myproject T="Build a todo app with React"
```

## Makefile Commands

Run `make help` for all available commands:

### Setup
```bash
make setup          # Interactive wizard to create/edit .env
make env            # Show current config (secrets hidden)
make test           # Test LLM server connection
make build          # Build Docker images
make build-clean    # Build with no cache
```

### Running Agents
```bash
# Simple task
make run W=myproject T="Build a todo app"

# Complex task from file (for prompts with quotes/special chars)
cat > task.txt << 'EOF'
Build a "complex" app with special requirements...
EOF
make run W=myproject TF=task.txt

# Interactive mode (no initial task)
make run W=myproject
```

### Management
```bash
make ps             # List running containers
make status         # Show all instances and workspaces
make logs           # Follow logs (all containers)
make logs C=agent   # Follow specific container logs
make stop           # Stop all containers
make stop I=agent-abc123  # Stop specific instance
```

### Debugging
```bash
make shell          # Shell into running agent container
make shell-supervisor  # Shell into supervisor container
```

### Cleanup
```bash
make clean          # Stop and remove all containers
make prune          # Remove unused images and volumes
```

## Multi-Instance Support

Run multiple agents simultaneously - each gets a unique instance name and ports automatically:

```bash
# Terminal 1
make run W=project1 T="Build a todo app"
# → Instance: agent-a1b2c3d4, Ports: 23000, 25000, 28000

# Terminal 2
make run W=project2 T="Build a chat app"
# → Instance: agent-e5f67890, Ports: 43000, 45000, 48000

# Terminal 3
make run W=project3 T="Build an API"
# → Instance: agent-12345678, Ports: 53000, 55000, 58000
```

Each instance is fully isolated with its own:
- Container names (`claude-agent-<instance>`, `claude-supervisor-<instance>`)
- Network (`claude-<instance>_agentnet`)
- Port mappings (auto-generated prefix 2-5)
- Workspace directories

### Port Mapping

Port prefix (2-5) is auto-generated and prepended to container ports:

| Prefix | React/Node | Flask | Django | General |
|--------|------------|-------|--------|---------|
| 2 | 23000 | 25000 | 28000 | 28080 |
| 3 | 33000 | 35000 | 38000 | 38080 |
| 4 | 43000 | 45000 | 48000 | 48080 |
| 5 | 53000 | 55000 | 58000 | 58080 |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  HOST (Makefile / run.sh)                                                   │
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
              ┌──────────────────────────────────────┐
              │  Your LLM Backend                    │
              │  (LM Studio, Ollama, vLLM, etc.)     │
              │                                      │
              │  All containers use same LLM_HOST    │
              │  (can override per-component)        │
              └──────────────────────────────────────┘
```

## Configuration

### Setup Wizard

The easiest way to configure is the interactive wizard:

```bash
make setup
```

This guides you through all settings and creates/updates your `.env` file:
- LLM backend (host, port, model)
- Vision model configuration
- Resource limits
- Langfuse tracing (agent and supervisor)
- Supervisor settings

### Environment Variables

All settings in `.env`:

```env
# LLM Backend (required)
LLM_HOST=192.168.1.100          # Your LLM server
LLM_PORT=11234
LLM_AUTH_TOKEN=lmstudio
LLM_MODEL=your-model-name

# Vision Model
VISION_MODEL=qwen/qwen3-vl-4b

# Resource Limits
MEMORY_LIMIT=16G
MEMORY_RESERVATION=2G

# Workspace
WORKSPACE_NAME=default
WORKSPACE_BASE=/path/to/workspaces  # Optional, defaults to ./workspaces

# Supervisor Configuration
SUPERVISOR_MAX_LOOPS=20         # Max evaluation rounds
SUPERVISOR_TIMEOUT=3600         # Timeout per evaluation (seconds)
STOP_HOOK_EXTRA_SEC=1200        # Extra time for Langfuse flush
SUPERVISOR_AUTONOMY_APPEND=true # Add "keep working" nudge to feedback
```

### LLM Host Overrides

By default, all components use `LLM_HOST`. Override individually if needed:

```env
# Main agent uses LLM_HOST (default)

# Supervisor on different GPU/machine
SUPERVISOR_LLM_HOST=other-gpu.local
SUPERVISOR_LLM_PORT=11234

# Vision model on different GPU/machine
VISION_HOST=vision-gpu.local
VISION_PORT=11234
```

### Langfuse Tracing

Track agent and supervisor sessions separately:

```env
# Agent tracing
TRACE_TO_LANGFUSE=true
LANGFUSE_PUBLIC_KEY=pk-lf-xxx
LANGFUSE_SECRET_KEY=sk-lf-xxx
LANGFUSE_HOST=http://host.docker.internal:3000
LANGFUSE_PROJECT=claude-code

# Supervisor tracing (separate project)
SUPERVISOR_TRACE_TO_LANGFUSE=true
SUPERVISOR_LANGFUSE_PUBLIC_KEY=pk-lf-xxx
SUPERVISOR_LANGFUSE_SECRET_KEY=sk-lf-xxx
SUPERVISOR_LANGFUSE_PROJECT=claude-supervisor
```

## How the Supervisor Works

The supervisor is an **external Claude Code agent** that evaluates task completion:

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
│  1. Reads original task (immutable)   │
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
├── Makefile               # Main interface - run 'make help'
├── .env.example           # Configuration template
├── .env                   # Your configuration (gitignored)
├── run.sh                 # Run script (called by Makefile)
├── docker-compose.yml     # Service definitions
├── Dockerfile             # Agent container
├── Dockerfile.base        # Shared base image
├── supervisor/
│   ├── Dockerfile         # Supervisor container
│   ├── app.py             # Flask API
│   └── SUPERVISOR_PROMPT.md
├── scripts/
│   ├── init-workspace.sh  # Agent workspace init
│   └── setup-wizard.sh    # Interactive setup
├── skills-backup/         # Skills (copied into agent)
├── hooks-backup/          # Hooks (copied into agent)
├── agents-backup/         # Subagents (copied into agent)
├── claude-backup/
│   └── CLAUDE.md          # Instructions for agent
├── workspaces/            # Created at runtime (gitignored)
└── docs/
    ├── ARCHITECTURE.md    # Detailed architecture docs
    └── TRACING.md         # Langfuse setup guide
```

## Troubleshooting

### Test LLM Connection
```bash
make test
```

### View Current Config
```bash
make env
```

### Build Fails
```bash
# Full rebuild
make build-clean
```

### Cannot Connect to LLM

1. Verify LLM is running: `curl http://<LLM_HOST>:<LLM_PORT>/v1/models`
2. Run `make setup` to verify settings
3. Ensure LLM is accessible from Docker (use machine IP, not localhost)

### Agent Stuck in Loop

The supervisor has a max loop limit (default 20). Adjust with:
```env
SUPERVISOR_MAX_LOOPS=30
```

### Port Conflicts

Ports are auto-generated (prefix 2-5). If you need specific ports:
```bash
PORT_PREFIX=3 make run W=myproject T="task"
```

### exFAT Filesystem Issues

Store workspaces on APFS/HFS+ drive:
```env
WORKSPACE_BASE=/Users/yourusername/claude-workspaces
```

## Security

Both containers are secure sandboxes:
- **Isolated** - Cannot access host filesystem (except workspace)
- **Non-root** - Run as unprivileged users
- **Memory limited** - Prevents runaway processes
- **Supervisor read-only** - Cannot modify agent's work
- **Immutable task** - Neither can change the original request

## License

[Your license here]
