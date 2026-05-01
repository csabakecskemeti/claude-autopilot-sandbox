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

# 4. Start shared services
make searxng-start      # Web search
make supervisor-start   # Task validator

# 5. Run with a task
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

### Runtime Overrides

Any `.env` variable can be overridden per-run:

```bash
# Agent 1 on default LLM
make run W=proj1 T="task 1"

# Agent 2 on different LLM
LLM_HOST=dgx-spark-2.local make run W=proj2 T="task 2"

# Agent 3 on yet another LLM
LLM_HOST=192.168.1.200 LLM_MODEL=llama-70b make run W=proj3 T="task 3"
```

### Alternate Env Files

Create separate configurations for different setups:

```bash
# Clone .env to a new file
make env-clone E=.env-dgx2

# Edit .env-dgx2 with different LLM_HOST, model, etc.

# Run using the alternate config
make run W=myproject ENV=.env-dgx2 T="task"
```

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
│  ./workspaces/                                                              │
│    ├── proj1/         → Agent 1 workspace (rw)                              │
│    ├── proj1-task/    → Agent 1 task (immutable)                            │
│    ├── proj2/         → Agent 2 workspace (rw)                              │
│    ├── proj2-task/    → Agent 2 task (immutable)                            │
│    └── ...                                                                  │
└─────────────────────────────────────────────────────────────────────────────┘
              │                                            │
              ▼                                            ▼
┌─────────────────────────────┐              ┌────────────────────────────────┐
│  Agent Container 1          │              │  Shared Supervisor Container   │
│  /home/claude/workspace     │──────────────│                                │
│  /task (ro)                 │   HTTP POST  │  /workspaces (ro - all agents) │
│                             │   /evaluate  │  /supervisor-workspaces (rw)   │
│  Claude Code CLI + Skills   │◄─────────────│                                │
└─────────────────────────────┘              │  Flask API (:8080)             │
                                             │  Evaluates: proj1, proj2, ...  │
┌─────────────────────────────┐              │                                │
│  Agent Container 2          │──────────────│  Stop hook sends:              │
│  /home/claude/workspace     │              │  {workspace, task, instance}   │
│  /task (ro)                 │◄─────────────│                                │
│                             │              └────────────────────────────────┘
│  Claude Code CLI + Skills   │                            │
└─────────────────────────────┘                            │
              │                                            │
              └────────────────────┬───────────────────────┘
                                   │
                          HTTP (OpenAI-compatible API)
                                   │
              ┌────────────────────────────────────────────┐
              │  Your LLM Backend                          │
              │  (LM Studio, Ollama, vLLM, etc.)           │
              └────────────────────────────────────────────┘
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

The supervisor is a **shared Claude Code agent** that validates task completion for all running agents:

```
                        ┌─────────────────────────────────────┐
                        │  Shared Supervisor (1 instance)     │
                        │                                     │
Agent 1 ──POST──────────│  Receives: workspace=proj1          │
                        │  Evaluates /workspaces/proj1        │
                        │  Returns: complete | not_complete   │
                        │                                     │
Agent 2 ──POST──────────│  Receives: workspace=proj2          │
                        │  Evaluates /workspaces/proj2        │
                        │  Instance-isolated loop counts      │
                        └─────────────────────────────────────┘
```

**Evaluation flow:**
1. Agent tries to stop → Stop hook calls `POST /evaluate`
2. Hook sends `{workspace, task, instance}` to identify which agent
3. Supervisor creates isolated workspace for this evaluation turn
4. Runs Claude Code CLI to explore agent's work
5. Returns `complete` (allow stop) or `not_complete` (block with feedback)
6. Agent continues with feedback until task is complete

**Key features:**
- **Shared service** - One supervisor serves multiple agents
- **Instance isolation** - Separate loop counts per agent
- Same capabilities as agent (can read files, run tests)
- READ-ONLY access to agent workspaces (can't modify)
- Max loop limit prevents infinite loops (default: 20)

## Skills

Skills are invoked with `/skillname` syntax:

| Skill | Description |
|-------|-------------|
| `/plan` | Create implementation plan |
| `/tasks` | Track task progress |
| `/vision` | Image analysis, UI verification, OCR |
| `/webfetch` | Fetch and analyze URLs |
| `/websearch` | Web search via SearXNG (see below) |
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

## Web Search (SearXNG)

Self-hosted meta-search engine for reliable, free web search:

```bash
# Option 1: Standalone (recommended)
make searxng-start              # Start once, keep running
make run W=myproject T="task"   # Agent connects via host network

# Option 2: Integrated
make run W=myproject T="task" SEARXNG=1   # SearXNG starts with agent
```

**Features:**
- Aggregates from Bing, DuckDuckGo, Startpage, and more
- If one engine blocks, others still work
- Fast (~1-2 seconds per query)
- MCP tool `web_search` auto-configured in agent

**Management:**
```bash
make searxng-test     # Test search API
make searxng-status   # Check health and engines
make searxng-stop     # Stop standalone service
```

See `docs/SEARXNG.md` for full documentation.

## Supervisor

The supervisor is a shared service that validates task completion for all agents.

### Running Modes

**Standalone (recommended)** - One supervisor serves multiple agents:
```bash
make supervisor-start              # Start once, keep running
make run W=proj1 T="task 1"        # Agent 1 uses shared supervisor
make run W=proj2 T="task 2"        # Agent 2 uses same supervisor
```

**Embedded** - Supervisor starts with each agent (legacy behavior):
```bash
make run W=myproject T="task" SUPERVISOR=1
```

### Management Commands
```bash
make supervisor-start    # Start shared supervisor
make supervisor-stop     # Stop supervisor
make supervisor-status   # Check health and loop counts
make supervisor-logs     # Follow supervisor logs
make supervisor-build    # Rebuild supervisor image
```

### How It Works

1. Agent works on task
2. Agent tries to stop → Stop hook calls supervisor API
3. Supervisor creates isolated workspace for this evaluation
4. Supervisor runs Claude Code CLI to analyze agent's work
5. Returns `complete` (allow stop) or `not_complete` (block with feedback)
6. If not complete, agent continues with supervisor's feedback
7. Loop until complete or max loops reached (default: 20)

### Configuration

```env
SUPERVISOR_MAX_LOOPS=20     # Max evaluation rounds before force-allow
SUPERVISOR_TIMEOUT=3600     # Timeout per evaluation (seconds)
SUPERVISOR_PORT=8080        # External port for shared supervisor
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
