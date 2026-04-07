# User Manual

## Overview

Claude Autopilot Sandbox runs Claude Code CLI in a Docker container connected to your local LLM. It operates autonomously using an **external supervisor agent** that validates task completion before allowing the agent to stop.

**Key Features:**
- 100% local execution with your own LLM
- Autonomous task completion without human intervention
- External supervisor agent prevents premature stopping
- Vision capabilities for UI testing and image analysis
- Isolated workspaces for different projects

## Quick Start

```bash
# Basic - interactive mode
./run.sh myproject

# With task - autonomous mode
./run.sh myproject "Build a todo app with Flask"
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

**Security model:**
- Agent cannot modify supervisor's workspace
- Supervisor cannot modify agent's code (read-only access)
- Neither can modify the original task (immutable `/task` mount)
- Only the supervisor decides when the task is "complete"

When the agent tries to stop, a **stop hook** automatically calls the supervisor. The supervisor (another Claude Code instance) evaluates whether the task is complete:
- If complete → Agent can stop
- If not complete → Agent receives feedback and continues working

## The Autonomous Loop

1. **You give a task** - Pass via run.sh or type in interactive mode
2. **Claude works** - Implements the task, runs tests
3. **Claude tries to stop** - Thinks it's done
4. **Stop hook triggers** - Calls supervisor automatically
5. **Supervisor evaluates** - Reads workspace, runs tests, verifies
6. **Feedback loop** - If not complete, agent receives specific feedback
7. **Completion** - Supervisor confirms, agent stops

You don't need to keep prompting - Claude will keep working autonomously until the supervisor confirms completion.

## Workspaces

### Creating a Workspace

```bash
./run.sh new-project              # Interactive mode
./run.sh new-project "Build X"    # Autonomous mode with task
```

Each workspace is isolated:
- Host: `./workspaces/<name>/`
- Container: `/home/claude/workspace`

### Important: Switching Workspaces

The supervisor mounts the workspace at startup. **When switching workspaces, restart the supervisor:**

```bash
# Correct: Stop everything, then start new workspace
docker compose down
./run.sh newproject "task"

# Wrong: Don't reuse running supervisor with different workspace
```

### Workspace Contents

Each workspace contains:
- Your project files
- `TASK.md` - Original task (created automatically)
- `.original_task` - Task for supervisor verification
- `.vision_logs/` - Vision request logs with screenshots
- `CLAUDE.md` - Workspace instructions (auto-created)

## Vision Capabilities

Claude can see and analyze images. This is especially useful for UI testing.

### Using Vision

```bash
# Analyze an image
~/.claude/skills/vision/vision.sh analyze ./screenshot.png "Describe this UI"

# Verify UI meets requirements
~/.claude/skills/vision/vision.sh verify http://localhost:5000 "Should show login form"

# Extract text (OCR)
~/.claude/skills/vision/vision.sh ocr ./document.png
```

### Input Types

- **Local file**: `./screenshot.png`, `/path/to/image.jpg`
- **Web URL**: `http://localhost:5000` (takes screenshot automatically)
- **Image URL**: `https://example.com/photo.jpg` (downloads image)

## Available Skills

Skills are invoked with `/skillname` or via bash scripts:

| Skill | Description |
|-------|-------------|
| `/plan` | Create implementation plan |
| `/tasks` | Track task progress |
| `/vision` | Image analysis and UI verification |
| `/websearch` | Web search via Playwright |
| `/memory` | Persistent memory across sessions |
| `/browser` | Browser automation (Playwright MCP) |

## Accessing Web Apps

When the agent runs a web server, access from your browser with **+20000 port offset**:

| Agent says | Access from host |
|------------|------------------|
| `http://localhost:3000` | `http://localhost:23000` |
| `http://localhost:5000` | `http://localhost:25000` |
| `http://localhost:8000` | `http://localhost:28000` |
| `http://localhost:8080` | `http://localhost:28080` |

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```env
# LLM Backend (required)
LLM_HOST=192.168.1.100
LLM_PORT=11234
LLM_AUTH_TOKEN=lmstudio
LLM_MODEL=your-model-name

# Vision Model (optional)
VISION_MODEL=qwen/qwen3-vl-4b

# Supervisor settings
SUPERVISOR_MAX_LOOPS=20      # Max evaluation rounds
SUPERVISOR_TIMEOUT=3600      # Timeout per evaluation (1 hour default)
```

### Supervisor Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERVISOR_MAX_LOOPS` | `20` | Max evaluations before forcing stop |
| `SUPERVISOR_TIMEOUT` | `3600` | Timeout per evaluation (seconds) |

## Tested Models

### Primary LLM

| Model | Context | Notes |
|-------|---------|-------|
| `nvidia.nvidia-nemotron-3-super-120b-a12b` | 1M | Excellent for autonomous coding |

### Vision Model

| Model | Notes |
|-------|-------|
| `qwen/qwen3-vl-4b` | Fast, accurate for UI verification |

## Stopping Claude

- Press `Ctrl+C` to interrupt
- Type `exit` or `/exit` to quit
- Supervisor will confirm completion before allowing stop

## Debugging

### Check supervisor logs
```bash
docker logs claude-supervisor
```

### Check agent hook logs
```bash
docker exec claude-agent cat ~/.claude/state/hook.log
```

### Test supervisor manually
```bash
docker exec claude-supervisor curl -s http://localhost:8080/health
```

### View running containers
```bash
docker compose ps
```

## Tracing with Langfuse

Track agent sessions in Langfuse:

```env
TRACE_TO_LANGFUSE=true
LANGFUSE_PUBLIC_KEY=pk-lf-xxx
LANGFUSE_SECRET_KEY=sk-lf-xxx
LANGFUSE_HOST=http://host.docker.internal:3000
```

See [docs/TRACING.md](docs/TRACING.md) for detailed setup.

## Example: Building a Todo App

```bash
./run.sh todoapp "Build a Flask todo app with: list todos, add todo, delete todo, mark complete. Include pytest tests."
```

The agent will:
1. Create Flask app structure
2. Implement routes and templates
3. Write tests
4. Run tests to verify
5. Call supervisor for validation
6. Receive feedback if incomplete
7. Continue until supervisor approves

## Tips for Best Results

1. **Be specific** - Clear tasks get better results
2. **Let it work** - Don't interrupt the autonomous loop
3. **Use workspaces** - Isolate different projects
4. **Restart for new workspaces** - `docker compose down` before switching
5. **Check supervisor logs** - See why tasks are rejected
