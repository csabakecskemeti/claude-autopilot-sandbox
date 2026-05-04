# User Manual

## Overview

Claude Autopilot Sandbox runs Claude Code CLI in a Docker container connected to your local LLM. It operates autonomously using an **external supervisor agent** that validates task completion before allowing the agent to stop.

**Key Features:**
- 100% local execution with your own LLM
- Autonomous task completion without human intervention
- External supervisor agent prevents premature stopping
- Multi-instance support - run multiple agents in parallel
- Vision capabilities for UI testing and image analysis
- Makefile-based workflow for easy management

## Quick Start

```bash
# 1. Initial setup (interactive wizard)
make setup

# 2. Build containers
make build

# 3. Run with a task
make worker W=myproject TASK="Build a todo app with Flask"
```

## Running Agents

### Simple Task

```bash
make worker W=myproject TASK="Build a todo app"
# same: WORKER=myproject T="Build a todo app"
```

### Complex Task (from file)

For prompts with quotes or special characters:

```bash
cat > task.txt << 'EOF'
Build a "Universal" To-Do Engine with:
- React + TypeScript
- Multiple storage backends
- AI-powered task decomposition
EOF

make worker W=myproject TASKFILE=task.txt
```

### Interactive Mode

```bash
make worker W=myproject
```

## Multi-Instance Support

Run multiple agents simultaneously:

```bash
# Terminal 1
make worker W=project1 TASK="Build a todo app"
# → Worker run id under workspaces/; host ports from allocate-ports (see metadata.json)

# Terminal 2
make worker W=project2 TASK="Build a chat app"
# → Second worker run: own folder, ports from allocate-ports, own compose project
```

Each worker run gets:
- Unique container names (`<prefix>-agent-<worker_run_id>`, same for supervisor)
- Four host ports from `scripts/allocate-ports.sh` (see `metadata.json`)
- Isolated Docker network per Compose project
- Folder `workspaces/<worker_run_id>/` with `worker/`, `task/`, `supervisor/`

### Accessing Web Apps

When the agent runs a web server, access it using the displayed ports:

| Instance Port Prefix | React/Node | Flask | Django |
|---------------------|------------|-------|--------|
| 2 | localhost:23000 | localhost:25000 | localhost:28000 |
| 3 | localhost:33000 | localhost:35000 | localhost:38000 |
| 4 | localhost:43000 | localhost:45000 | localhost:48000 |
| 5 | localhost:53000 | localhost:55000 | localhost:58000 |

## Management Commands

```bash
make ps             # List running containers
make status         # Show instances and workspaces
make logs           # Follow all logs
make logs C=agent   # Follow specific container
make stop           # Pick worker to stop (or make stop W=id); make stop-all for all
make shell          # Shell into agent container
```

## Configuration

### Setup Wizard

```bash
make setup
```

Walks you through all settings:
- LLM backend (host, port, model)
- Vision model
- Resource limits
- Langfuse tracing
- Supervisor settings

### View/Test Config

```bash
make env    # Show config (secrets hidden)
make test   # Test LLM connection
```

### Key Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `LLM_HOST` | Your LLM server hostname/IP | (required) |
| `LLM_MODEL` | Model name | (required) |
| `SUPERVISOR_MAX_LOOPS` | Max evaluation rounds | 20 |
| `SUPERVISOR_TIMEOUT` | Evaluation timeout (sec) | 3600 |

### LLM Host Overrides

By default all components use `LLM_HOST`. Override individually:

```env
SUPERVISOR_LLM_HOST=other-gpu.local  # Supervisor on different machine
VISION_HOST=vision-gpu.local         # Vision model on different machine
```

## How the Supervisor Works

```
Agent works on task
        ↓
Agent tries to stop
        ↓
Stop hook calls supervisor
        ↓
Supervisor evaluates:
  - Reads original task (immutable)
  - Explores workspace (read-only)
  - Runs tests if available
  - Determines complete/not_complete
        ↓
┌───────┴───────┐
complete     not_complete
   ↓              ↓
 STOP        Continue with
             feedback
```

## Skills

The agent has access to built-in skills:

| Command | Description |
|---------|-------------|
| `/plan` | Create implementation plan |
| `/tasks` | Track task progress |
| `/vision` | Screenshot analysis, UI verification |
| `/webfetch` | Fetch and analyze URLs |
| `/memory` | Persistent memory |
| `/notes` | Note-taking |

## Troubleshooting

### LLM Connection Failed
```bash
make test  # Verify connection
make setup # Re-run wizard
```

### Agent Stuck in Loop
Increase loop limit:
```env
SUPERVISOR_MAX_LOOPS=30
```

### Port Conflicts
Explicitly set port prefix:
```bash
make worker W=myproject TASK="task"
```

### Build Issues
```bash
make build-clean  # Full rebuild
```

### View Logs
```bash
make logs           # All containers
make logs C=agent   # Just agent
```

## Architecture

```
┌──────────────────────────────┐    ┌──────────────────────────────┐
│  Agent Container             │    │  Supervisor Container        │
│                              │    │                              │
│  /workspace (read-write)     │    │  /workspace (READ-ONLY)      │
│  /task (READ-ONLY)           │    │  /supervisor-workspaces (rw) │
│                              │    │  /task (READ-ONLY)           │
│  - Claude Code CLI           │───►│                              │
│  - Full tool access          │    │  - Claude Code CLI           │
│  - Autonomous mode           │    │  - Evaluates task completion │
│                              │◄───│  - Returns feedback          │
│  Stop hook calls supervisor  │    │                              │
└──────────────────────────────┘    └──────────────────────────────┘
```

**Security:**
- Agent cannot modify supervisor
- Supervisor has read-only access to agent workspace
- Original task is immutable (Docker-enforced)
- Only supervisor decides when task is complete
