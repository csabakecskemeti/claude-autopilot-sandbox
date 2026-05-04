# Agent-Based Supervisor - Implementation Complete

## Overview

The supervisor uses **Claude Code CLI** (same as agent) to evaluate task completion. This gives the supervisor full capabilities to read files, analyze code, and even run commands to verify the implementation.

## Container Architecture

Both agent and supervisor share a common base image (`claude-sandbox`) for consistency:

```
┌─────────────────────────────────────────────────────────────────┐
│  Dockerfile.base → claude-sandbox:latest                        │
│  - Ubuntu 24.04                                                 │
│  - Python 3, Node.js                                            │
│  - Playwright + Chromium + Xvfb                                 │
│  - Common tools (git, curl, jq, etc.)                           │
│  - Flask, langfuse, etc.                                        │
└─────────────────────────────────────────────────────────────────┘
              │                              │
              ▼                              ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│  Dockerfile → agent      │    │  supervisor/Dockerfile   │
│  - Claude CLI            │    │  - Claude CLI            │
│  - Skills, hooks         │    │  - Flask API             │
│  - Agent CLAUDE.md       │    │  - Eval prompt           │
│  - Autonomous mode       │    │  - Read-only workspace   │
└──────────────────────────┘    └──────────────────────────┘
```

### Build Order

```bash
# Build everything (recommended)
./build.sh

# Or build individually
./build.sh base       # Just the base image
./build.sh agent      # Base + agent
./build.sh supervisor # Base + supervisor
./build.sh --no-cache # Rebuild without cache
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  HOST                                                                       │
│                                                                             │
│  Agent Workspace: $WORKSPACE_BASE/myproject/                                │
│  Supervisor Workspaces: $WORKSPACE_BASE/myproject-supervisor/TURN1/         │
│                                         $WORKSPACE_BASE/myproject-supervisor/TURN2/
│                                         ...                                 │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       │ Volume mounts
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Supervisor Container                                                       │
│                                                                             │
│  Mounts:                                                                    │
│    /workspace           → Agent's workspace (READ-ONLY)                     │
│    /supervisor-workspaces → Supervisor turn workspaces (READ-WRITE)         │
│                                                                             │
│  POST /evaluate                                                             │
│  │                                                                          │
│  ├─► 1. Check/increment loop counter                                        │
│  │      - If >= MAX_SUPERVISOR_LOOPS → force allow with warning             │
│  │                                                                          │
│  ├─► 2. Prepare supervisor workspace                                        │
│  │      - Create TURN{n} directory                                          │
│  │                                                                          │
│  ├─► 3. Build supervisor prompt                                             │
│  │      - Load template from SUPERVISOR_PROMPT.md                           │
│  │      - Include original task                                             │
│  │                                                                          │
│  ├─► 4. Run Claude Code CLI                                                 │
│  │      claude --dangerously-skip-permissions \                             │
│  │             --allowedTools '*' \                                         │
│  │             --model "$LLM_MODEL" \                                       │
│  │             -p "$PROMPT"                                                 │
│  │                                                                          │
│  ├─► 5. Parse JSON from stdout                                              │
│  │                                                                          │
│  └─► 6. Return to stop hook                                                 │
│         {status: "complete"|"not_complete", message: "..."}                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Implemented Files

| File | Purpose |
|------|---------|
| `Dockerfile.base` | Shared base image (claude-sandbox) |
| `Dockerfile` | Agent container (uses claude-sandbox) |
| `supervisor/Dockerfile` | Supervisor container (uses claude-sandbox) |
| `supervisor/app.py` | Flask API with Claude Code evaluation |
| `supervisor/SUPERVISOR_PROMPT.md` | Evaluation prompt template |
| `supervisor/supervisor_stop_hook.sh` | Langfuse tracing (never blocks) |
| `supervisor/CLAUDE.md` | Instructions for supervisor agent |
| `supervisor/settings.json` | Claude settings with hooks |
| `docker-compose.yml` | Service configuration |
| `build.sh` | Build script (base → agent/supervisor) |
| `run.sh` | Run script (creates workspaces, starts containers) |
| `.env.example` | Environment variable template |

## Configuration

### Environment Variables

All supervisor-related settings use the `SUPERVISOR_` prefix for clarity.

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERVISOR_MAX_LOOPS` | `20` | Max evaluations before forcing stop |
| `SUPERVISOR_TIMEOUT` | `3600` | Timeout for supervisor evaluation (1 hour default) |
| `LLM_MODEL` | (inherited) | Model for supervisor (same as agent) |
| `SUPERVISOR_TRACE_TO_LANGFUSE` | `false` | Enable supervisor tracing |
| `SUPERVISOR_LANGFUSE_PROJECT` | `claude-supervisor` | Langfuse project for supervisor |
| `SUPERVISOR_LANGFUSE_PUBLIC_KEY` | - | Supervisor Langfuse public key |
| `SUPERVISOR_LANGFUSE_SECRET_KEY` | - | Supervisor Langfuse secret key |
| `AGENT_LANGFUSE_PUBLIC_KEY` | - | Agent's Langfuse key (for trace access) |
| `AGENT_LANGFUSE_SECRET_KEY` | - | Agent's Langfuse key (for trace access) |
| `AGENT_LANGFUSE_PROJECT` | - | Agent's Langfuse project |

### Supervisor Langfuse Credentials

Separate project for supervisor traces:
- **Project**: `claude-autopilot-sandbox-supervisor`
- **Public Key**: `pk-lf-47b668d7-f4f7-415e-9453-892c2e0060ea`
- **Secret Key**: `sk-lf-6d8d5882-f8a7-43bd-93be-3ba45c9ef397`

## How It Works

### 1. Agent Stops → Stop Hook Triggers

When the agent tries to stop, the stop hook calls the supervisor API:

```bash
curl -s http://supervisor:8080/evaluate
```

### 2. Supervisor Evaluates

The supervisor:
1. Reads the original task from `/workspace/.original_task`
2. Loads the evaluation prompt from `SUPERVISOR_PROMPT.md`
3. Runs Claude Code CLI with the prompt
4. Parses JSON from Claude's stdout

### 3. Response Format

Claude outputs plain text with a status keyword. No JSON parsing required - simpler and more robust.

```
status: complete

[Explanation of what was built and why it's complete]
```

or

```
status: not_complete

[Explanation of what's missing]

Next steps:
1. Fix X
2. Add Y
```

The Flask app looks for "status: complete" or "status: not_complete" keywords.
The raw output is passed directly to the agent as feedback.

### 4. Stop Hook Decision

- **complete** → Stop hook exits 0 (agent allowed to stop)
- **not_complete** → Stop hook exits 1 + outputs feedback (agent continues)

## Workspace Structure

### Agent Workspace (mounted at /workspace)
```
$WORKSPACE_BASE/myproject/
├── .original_task           # Original user request (written by run.sh)
├── .claude/                 # Agent's Claude state
├── src/                     # Agent's code
└── ...
```

### Supervisor Workspaces (isolated per turn)
```
$WORKSPACE_BASE/myproject-supervisor/
├── .loop_count              # Current evaluation count
├── TURN1/
│   ├── .claude/             # Claude Code state for this turn
│   ├── prompt.txt           # Prompt sent to supervisor
│   ├── supervisor_stdout.txt # Full Claude output
│   └── response.json        # Parsed response
├── TURN2/
│   └── ...
└── TURN{n}/
    └── ...
```

## Testing

### Build and Start

```bash
docker compose build supervisor
docker compose up supervisor -d
```

### Test Health Check

```bash
curl http://localhost:8080/health
```

### Test Evaluation

```bash
# First create a workspace with a task
mkdir -p workspaces/test
echo "Build a simple hello world app" > workspaces/test/.original_task

# Run evaluation
curl http://localhost:8080/evaluate
```

### Reset Loop Counter

```bash
curl -X POST http://localhost:8080/reset
```

## Flow Diagram

```
User starts: ./run.sh myproject "Build a todo app"
         │
         ▼
    ┌─────────────┐
    │   run.sh    │
    │             │
    │ 1. Create workspace dirs
    │ 2. Write .original_task
    │ 3. Reset loop counter
    │ 4. docker compose run agent
    └─────────────┘
         │
         ▼
    ┌─────────────┐
    │   Agent     │
    │  Container  │
    │             │
    │ Works on task...
    │ Tries to stop
    └──────┬──────┘
           │ Stop hook triggers
           ▼
    ┌─────────────┐
    │ Stop Hook   │
    │             │
    │ curl supervisor:8080/evaluate
    └──────┬──────┘
           │
           ▼
    ┌─────────────┐
    │ Supervisor  │
    │  Container  │
    │             │
    │ 1. Read .original_task
    │ 2. Run Claude -p "evaluate..."
    │ 3. Parse JSON from stdout
    │ 4. Return {status, message}
    └──────┬──────┘
           │
           ▼
    ┌─────────────┐
    │ Stop Hook   │
    │             │
    │ status == "complete"?
    │   YES → exit 0 (stop allowed)
    │   NO  → exit 1 + feedback (continue)
    └─────────────┘
```

## Evaluation Guidelines

The supervisor prompt (`SUPERVISOR_PROMPT.md`) instructs Claude to:

### Mark as COMPLETE if:
- Core functionality is implemented
- Code compiles/parses without errors
- Main requirements are satisfied
- Minor issues (formatting, comments, edge cases) are OK

### Mark as NOT COMPLETE if:
- Significant features are missing
- Code has syntax/compilation errors
- Implementation doesn't match the request
- Critical bugs that prevent basic functionality

### Be Pragmatic:
- Don't be overly strict
- 80% complete with working core is often "complete"
- Focus on: Does it WORK? Does it match the REQUEST?

## Loop Limit Protection

To prevent infinite loops:
1. Loop counter tracked in `/supervisor-workspaces/.loop_count`
2. Default limit: 20 evaluations (`MAX_SUPERVISOR_LOOPS`)
3. When limit reached, supervisor returns "complete" with warning
4. Counter reset by `run.sh` on new runs

## Tracing

Supervisor has optional Langfuse tracing to a separate project:
- Traces supervisor's evaluation reasoning
- Never blocks supervisor exit (stop hook always exits 0)
- Configured via `TRACE_SUPERVISOR_TO_LANGFUSE=true`

This allows reviewing supervisor decisions separately from agent work.
