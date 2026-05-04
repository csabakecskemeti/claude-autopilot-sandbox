# Auto-Continue Mechanism (External Supervisor)

This document explains how the system enforces task completion through an external supervisor container.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Agent Container (claude-agent)                                  │
│  - Full filesystem access to /home/claude/workspace              │
│  - Runs Claude Code CLI                                          │
│  - Can build apps, run services, modify files                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ Stop Hook (when Claude tries to stop)
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Stop Hook (langfuse_stop_hook.sh)                               │
│  1. Send traces to Langfuse                                      │
│  2. Call supervisor API: POST http://supervisor:8080/evaluate    │
│  3. If "complete" → allow stop                                   │
│  4. If "not_complete" → block with feedback message              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         │ HTTP API
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Supervisor Container (claude-supervisor)                        │
│  - READ-ONLY access to /workspace                                │
│  - Cannot be modified by agent                                   │
│  - Validates:                                                    │
│    1. Static: Files exist, project structure                     │
│    2. HTTP: Services responding on ports 3000/5000/8000/8080     │
│    3. Runtime QA: Playwright browser testing                     │
└─────────────────────────────────────────────────────────────────┘
```

## Key Security Properties

1. **Agent cannot bypass validation** - Stop hook ALWAYS calls supervisor
2. **Agent cannot fake completion** - Supervisor has read-only access, cannot be modified
3. **Evidence-based completion** - App must actually run and pass QA checks
4. **Actionable feedback** - Supervisor returns specific issues and next steps

## How It Works

1. Agent works autonomously on the task
2. Agent tries to stop (thinks it's done, or needs input)
3. Stop Hook fires automatically
4. Hook calls `POST http://supervisor:8080/evaluate`
5. Supervisor checks:
   - `.original_task` file for requirements
   - Static validation (code files exist)
   - HTTP validation (server responding)
   - Runtime QA (Playwright browser tests)
6. Supervisor returns:
   - `{"status": "complete", "message": "..."}` → agent can stop
   - `{"status": "not_complete", "message": "..."}` → agent must continue
7. If blocked, feedback message is sent TO Claude explaining issues

## Validation Checks

### 1. Static Validation
- Code files exist (`.py`, `.js`, `.ts`, etc.)
- Project files present (`package.json`, `requirements.txt`, etc.)
- Documentation exists

### 2. HTTP Validation
- Checks ports: 3000, 5000, 8000, 8080
- Verifies HTTP 200 response

### 3. Runtime QA (Playwright)
- Opens browser to app URL
- Waits for page load
- Checks for content
- Looks for error indicators
- Takes screenshot

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SUPERVISOR_URL` | `http://supervisor:8080` | Supervisor API endpoint |
| `MAX_CONTINUE_CYCLES` | `100` | Safety limit before forcing stop |
| `QA_TIMEOUT` | `30` | Playwright timeout in seconds |

### Files

| File | Location | Purpose |
|------|----------|---------|
| `langfuse_stop_hook.sh` | `~/.claude/hooks/` | Stop hook script |
| `.original_task` | workspace | Task description for verification |
| `.original_task_hash` | workspace | Task hash for integrity |

## Running

```bash
# Start with workspace name
./run.sh myproject

# Start with workspace name and task description
./run.sh myproject "Build a todo app with React and Express"
```

The task description is saved to `.original_task` for supervisor verification.

## Debugging

Check supervisor logs:
```bash
docker compose logs supervisor
```

Check hook logs (inside agent container):
```bash
cat ~/.claude/state/hook.log
```

Test supervisor manually:
```bash
docker exec claude-supervisor curl -s http://localhost:8080/evaluate | jq .
```

## Safety Mechanisms

### 1. `stop_hook_active` Flag
Prevents infinite loops where hook blocks itself repeatedly.

### 2. Cycle Counter
After 100 blocked attempts (configurable), allows stop regardless.

### 3. Health Check
Supervisor container must be healthy before agent starts.

## Related Documentation

- [NEW_SUPERVISOR_MODEL.md](../NEW_SUPERVISOR_MODEL.md) - Architecture specification
- [SUPERVISOR_IMPROVEMENTS.md](./SUPERVISOR_IMPROVEMENTS.md) - Investigation findings
- [TRACING.md](./TRACING.md) - Langfuse tracing setup
