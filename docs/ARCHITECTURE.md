# Technical Architecture

This document explains the technical design of Claude Autopilot Sandbox, the rationale behind key decisions, and how the components work together.

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [System Architecture](#system-architecture)
3. [Agent-Supervisor Model](#agent-supervisor-model)
4. [Stop Hook Mechanism](#stop-hook-mechanism)
5. [Security Model](#security-model)
6. [Configuration Decisions](#configuration-decisions)
7. [Tracing Architecture](#tracing-architecture)
8. [Known Limitations](#known-limitations)

---

## Design Philosophy

### Core Problem

When running an autonomous coding agent, a fundamental challenge emerges: **how do you know when the agent is actually done?**

An LLM-based agent might:
- Think it's done when it's not (premature completion)
- Get stuck in a loop without making progress
- Produce code that doesn't actually work
- Self-report completion without verification

### Solution: External Validation

The key insight is that **the agent cannot be trusted to evaluate its own work**. Just as a developer shouldn't approve their own pull requests, an autonomous agent shouldn't decide when it's "done."

This led to the **agent-supervisor architecture**:

```
Agent (untrusted) → Stop Hook → Supervisor (trusted) → Feedback Loop
```

The supervisor is:
- External to the agent (separate container)
- Cannot be modified by the agent
- Has read-only access to the agent's work
- Uses the same capabilities (Claude Code CLI) to evaluate

### Why Not a Simple Script?

Early iterations used a Python-based supervisor with static checks (file exists, HTTP 200, etc.). This approach had significant limitations:

1. **Brittle rules**: Hard to specify all success criteria upfront
2. **No semantic understanding**: Can't evaluate if code is "correct"
3. **High maintenance**: Every new task type needs new rules

Using Claude Code CLI as the supervisor means:
- **Semantic evaluation**: LLM understands code and requirements
- **Flexible**: Works for any task type without configuration
- **Same capabilities**: Can run tests, check logs, use vision

---

## System Architecture

### Container Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  HOST (run.sh)                                                              │
│                                                                             │
│  ./workspaces/myproject/            → Agent's workspace                     │
│  ./workspaces/myproject-supervisor/ → Supervisor's turn workspaces          │
│  ./workspaces/myproject-task/       → IMMUTABLE task storage                │
│       └── original_task             (written once by run.sh, never modified)│
└─────────────────────────────────────────────────────────────────────────────┘
              │                         │                         │
              │ bind mount (rw)         │ bind mount (rw)         │ bind mount (ro)
              ▼                         ▼                         ▼
┌──────────────────────────────┐    ┌──────────────────────────────┐
│  Agent Container             │    │  Supervisor Container        │
│  claude-agent                │    │  claude-supervisor           │
│                              │    │                              │
│  /home/claude/workspace (rw) │    │  /workspace (ro)             │
│  /task (READ-ONLY)           │    │  /supervisor-workspaces (rw) │
│  ~/.claude/hooks/            │    │  /task (READ-ONLY)           │
│  ~/.claude/skills/           │    │                              │
│                              │    │  Flask API on :8080          │
│  Claude Code CLI             │    │  Claude Code CLI (-p mode)   │
└──────────────────────────────┘    └──────────────────────────────┘
              │                                      │
              └──────────────────────────────────────┘
                         Docker network: agentnet
```

**Three-way isolation:**
1. **Agent workspace** - Agent has full read-write, supervisor has read-only
2. **Supervisor workspace** - Supervisor has read-write for evaluation work, agent has no access
3. **Task storage** - Both have read-only, only host can write (immutable)

### Why Two Containers?

**Isolation**: The supervisor must be tamper-proof. Even if the agent has root access inside its container, it cannot:
- Modify the supervisor's code
- Change the supervisor's decision logic
- Access the supervisor's filesystem

**Different access patterns**:
- Agent needs read-write to build code
- Supervisor needs read-only to prevent tampering with evidence

### Shared Base Image

Both containers use the same base image (`claude-sandbox:latest`) because:
1. **Consistency**: Same tools available for evaluation
2. **Capability parity**: Supervisor can do anything agent can do
3. **Build efficiency**: One base to maintain

---

## Agent-Supervisor Model

### Why Agent-Based Supervisor?

The supervisor itself is a Claude Code agent running in print mode (`-p` flag). This choice enables:

1. **Full evaluation capability**: Can read files, run tests, analyze code
2. **Semantic understanding**: Understands requirements, not just syntax
3. **Tool access**: Same tools as agent (Bash, Read, Write, Glob, Grep)
4. **Vision capability**: Can screenshot and verify UIs
5. **Flexible reasoning**: Adapts to any task type

### Evaluation Flow

```
1. Agent tries to stop
2. Stop hook triggers
3. Hook calls POST /evaluate on supervisor
4. Supervisor Flask API:
   a. Creates isolated workspace for this turn
   b. Loads original task from /workspace/.original_task
   c. Builds evaluation prompt
   d. Runs: claude -p --model $LLM_MODEL "$PROMPT"
   e. Parses output for "status: complete" or "status: not_complete"
   f. Returns JSON response
5. Stop hook:
   - If complete → allows stop
   - If not_complete → blocks with feedback message
6. Agent receives feedback, continues working
```

### Turn Isolation

Each supervisor evaluation gets its own workspace (`/supervisor-workspaces/TURN1/`, `TURN2/`, etc.). This:
- Prevents state leakage between evaluations
- Provides audit trail of each evaluation
- Allows debugging by examining turn outputs

### Output Format

The supervisor is instructed to output in a simple format:

```
status: complete|not_complete

[explanation and next steps]
```

No complex JSON parsing - just keyword matching. This is intentional:
- Local LLMs may produce malformed JSON
- Simple keyword matching is robust
- Human-readable output for debugging

---

## Stop Hook Mechanism

### How Claude Code Hooks Work

Claude Code CLI supports hooks - scripts that run on specific events. The `Stop` hook runs when Claude tries to stop (exit/complete).

**Official Documentation**: https://code.claude.com/docs/en/hooks

### Hook Input

Stop hooks receive JSON on stdin with session information:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/.claude/projects/.../session.jsonl",
  "cwd": "/workspace",
  "permission_mode": "default",
  "hook_event_name": "Stop"
}
```

### Hook Output and Feedback Injection

**Critical insight**: Hooks can only send information back to Claude **when blocking the stop**. When allowing the stop, no feedback reaches the agent.

#### Output Fields (from official docs)

| Field | Description |
|-------|-------------|
| `decision` | `"block"` prevents Claude from stopping and continues the conversation |
| `reason` | **Shown to Claude** when `decision` is `"block"` |
| `additionalContext` | **String added to Claude's context** when blocking |

#### Two Ways to Block

**Option 1: JSON with exit 0 (recommended)**

```bash
jq -n --arg reason "Tests failed" --arg context "Fix auth.js and rerun npm test" '{
    decision: "block",
    reason: $reason,
    hookSpecificOutput: {
        hookEventName: "Stop",
        additionalContext: $context
    }
}'
exit 0
```

Effects:
- ❌ Prevents agent from stopping
- ✅ `reason` → shown to Claude
- ✅ `additionalContext` → injected into Claude's context

**Option 2: Exit code 2 (fallback)**

```bash
echo "Fix tests before finishing" >&2
exit 2
```

Effects:
- ❌ Blocks completion
- ⚠️ Sends unstructured feedback via stderr
- 🤖 Claude may react, but less reliably

### Our Implementation

A **single** Stop hook, **`langfuse_stop_hook.sh`**, runs **sequentially**: (1) optional Langfuse ingest, (2) supervisor `POST /evaluate`. Only step (2) may print `{decision,reason}` to stdout when blocking.

Claude Code runs **multiple** Stop commands **in parallel** if listed separately ([hooks docs](https://code.claude.com/docs/en/hooks)), so Langfuse and the supervisor gate are **not** split into two settings entries — order would not be guaranteed.

```bash
# Simplified tail (after Langfuse): supervisor gate
RESPONSE=$(curl -s --max-time "$SUPERVISOR_TIMEOUT" -X POST "$SUPERVISOR_URL/evaluate")
STATUS=$(echo "$RESPONSE" | jq -r '.status')
MESSAGE=$(echo "$RESPONSE" | jq -r '.message')
if [ "$STATUS" = "complete" ]; then
    exit 0
else
    jq -n --arg reason "$MESSAGE" '{decision: "block", reason: $reason}'
    exit 0
fi
```

### The Feedback Loop

This creates a programmable "review gate" that can redirect the agent:

```
Agent thinks it's done → tries to stop
                ↓
        Stop hook fires
                ↓
    Hook calls supervisor API
                ↓
    Supervisor evaluates workspace
                ↓
┌─────────────────────────────────────────┐
│ If complete:                            │
│   exit 0 (no JSON) → agent stops        │
├─────────────────────────────────────────┤
│ If not complete:                        │
│   {                                     │
│     "decision": "block",                │
│     "reason": "short status",           │
│     "hookSpecificOutput": {             │
│       "additionalContext": "detailed    │
│         instructions for next steps"    │
│     }                                   │
│   }                                     │
│   exit 0 → agent continues with context │
└─────────────────────────────────────────┘
```

### Why Not a Separate Hook?

The Langfuse tracing and supervisor validation are in the same hook because:
1. Both need to run on stop
2. Tracing should happen before validation
3. Single hook simplifies configuration

### Timeout Considerations

The `SUPERVISOR_TIMEOUT` (default: 1 hour) must be long enough for:
- Complex evaluations
- Running test suites
- Vision verification
- LLM response time

The curl timeout in the hook matches this value to prevent premature timeout.

---

## Security Model

### Trust Boundaries

| Component | Trust Level | Can Modify | Can Access |
|-----------|-------------|------------|------------|
| Agent | Untrusted | Own workspace | Own workspace, supervisor API |
| Supervisor | Trusted | Own workspace | Agent workspace (read-only) |
| Stop Hook | Trusted | Nothing | Session info, supervisor API |
| Host | Trusted | Everything | Everything |

### Why Agent is Untrusted

The agent has full capabilities inside its container:
- Root access (via sudo)
- Full filesystem access
- Network access
- Can install packages

This is intentional - autonomous coding requires flexibility. But it means:
- Agent could fake logs or test results
- Agent could modify its own code
- Agent could try to bypass completion checks

### Supervisor Read-Only Access

The supervisor mounts the agent workspace as **read-only**:

```yaml
volumes:
  - ${WORKSPACE_PATH}:/workspace:ro
```

This ensures:
- Supervisor sees authentic state
- Agent can't tamper with evidence after evaluation starts
- Evaluation is based on actual artifacts

### Task Tamper Protection

The original task is stored in an **immutable host folder** mounted read-only to both containers:

```
Host:       ./workspaces/myproject-task/original_task
Agent:      /task/original_task  (read-only mount)
Supervisor: /task/original_task  (read-only mount)
```

**Why this is truly tamper-proof:**

1. **Docker enforces read-only mounts at the kernel level**
2. No amount of `sudo`, `chmod`, or privilege escalation inside containers can write to `:ro` mounts
3. Only the host (run.sh) can modify the task directory
4. Both agent and supervisor see the same immutable task

**Flow:**
1. `run.sh` writes task to `./workspaces/myproject-task/original_task` on host
2. Docker mounts this directory as `/task:ro` in both containers
3. Supervisor reads from `/task/original_task` (guaranteed authentic)
4. Agent cannot change requirements; supervisor cannot be tricked

### What Agent Cannot Do

Even with root access, the agent cannot:
1. **Modify supervisor container**: Separate container, no access
2. **Bypass stop hook**: Hook is in separate config, runs automatically
3. **Fake supervisor response**: Curl to external service, can't intercept
4. **Disable validation**: Settings copied at container build time

### Loop Limits

Two safety mechanisms prevent infinite loops:

1. **`MAX_CONTINUE_CYCLES`** (default: 100): Stop hook tracks how many times it's blocked the agent
2. **`SUPERVISOR_MAX_LOOPS`** (default: 20): Supervisor tracks evaluation rounds

When limits are reached, the system forces completion with a warning.

---

## Configuration Decisions

### Default Timeout: 1 Hour

`SUPERVISOR_TIMEOUT=3600` (1 hour) was chosen because:
- Complex evaluations can take time (running full test suites)
- Local LLMs are slower than cloud APIs
- Vision verification adds latency
- Better to wait than timeout prematurely

### Evaluation Loops: 20 Max

`SUPERVISOR_MAX_LOOPS=20` balances:
- Giving agent enough chances to complete
- Preventing infinite loops on impossible tasks
- Reasonable session length

### Why Separate Langfuse Projects?

Agent and supervisor have separate Langfuse projects:
- **Agent project**: Track actual work, tool usage, decisions
- **Supervisor project**: Track evaluations, feedback quality

This separation allows:
- Independent analysis of each component
- Different retention policies
- Cleaner trace organization

---

## Tracing Architecture

### What Gets Traced

**Agent traces** (LANGFUSE_PROJECT):
- User prompts
- LLM generations
- Tool calls (Read, Write, Bash, etc.)
- Token usage

**Supervisor traces** (SUPERVISOR_LANGFUSE_PROJECT):
- Evaluation prompts
- Supervisor reasoning
- Completion decisions

### Trace Structure

```
Session (conversation)
└── Trace (one turn)
    ├── Generation (LLM response)
    │   └── usage: input/output tokens
    └── Spans (tool calls)
        ├── Read: file content
        ├── Bash: command output
        └── ...
```

### Why Langfuse?

- Self-hostable (runs locally)
- Compatible with OpenAI trace format
- Good visualization for debugging
- Supports session grouping

---

## Multi-Instance Deployment

### Running Multiple Agents Simultaneously

You can run multiple agent+supervisor pairs on the same machine. Each run automatically generates a unique instance name:

```bash
# Terminal 1: Auto-generates instance name (e.g., agent-a1b2c3d4)
./run.sh project1 "Build a todo app"

# Terminal 2: Another auto-generated instance
./run.sh project2 "Build a chat app"

# Terminal 3: Explicit instance name with custom port prefix
INSTANCE_NAME=worker3 PORT_PREFIX=5 ./run.sh project3 "Build an API"
```

### Instance Isolation

Each instance gets:
- **Unique container names**: `claude-agent-worker2`, `claude-supervisor-worker2`
- **Isolated network**: Via Docker Compose project name
- **Separate ports**: PORT_OFFSET controls all external ports
- **Independent workspaces**: Each project gets its own workspace folder

### Port Mapping

Port prefix (single digit) is prepended to container ports. Auto-generated from instance name hash (2-5, max 5 since 68000 > 65535):

```
PORT_PREFIX=2:
  - 23000 → container:3000 (Node.js/React)
  - 25000 → container:5000 (Flask)
  - 28000 → container:8000 (Django/FastAPI)
  - 28080 → container:8080 (General web)

PORT_PREFIX=5:
  - 53000 → container:3000
  - 55000 → container:5000
  - etc.
```

### Remote Supervisor Mode

For distributed deployments (e.g., running agent on one machine, supervisor on DGX Spark):

**On supervisor machine (DGX Spark):**
```bash
# Run supervisor only
docker compose up supervisor
# Exposed on port 8080 (or SUPERVISOR_EXTERNAL_PORT)
```

**On agent machine:**
```bash
# Run agent pointing to remote supervisor
SKIP_LOCAL_SUPERVISOR=true \
SUPERVISOR_URL=http://dgx-spark:8080 \
./run.sh myproject "Build feature X"
```

### Different LLM Backends

Supervisor can use a different LLM backend than the agent:

```bash
# Agent uses local LM Studio, supervisor uses DGX
LLM_HOST=localhost \
SUPERVISOR_LLM_HOST=dgx-spark \
SUPERVISOR_LLM_PORT=8000 \
./run.sh myproject "Build app"
```

This is useful when:
- Supervisor needs a larger/better model
- Load balancing across multiple GPUs
- Using specialized models for evaluation

### Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTANCE_NAME` | (random) | Unique identifier for this instance |
| `PORT_PREFIX` | (2-5) | Single digit prepended to container ports |
| `CONTAINER_PREFIX` | claude | Prefix for container names |
| `SKIP_LOCAL_SUPERVISOR` | false | Use remote supervisor instead |
| `SUPERVISOR_URL` | http://supervisor:8080 | Remote supervisor URL |
| `SUPERVISOR_EXTERNAL_PORT` | 8080 | Port to expose supervisor on |
| `SUPERVISOR_LLM_HOST` | (LLM_HOST) | LLM backend for supervisor |
| `SUPERVISOR_LLM_PORT` | (LLM_PORT) | LLM port for supervisor |

---

## Known Limitations

### 1. Hook Timeout

Claude Code may have a built-in hook timeout (undocumented). If supervisor evaluation exceeds this, the hook might be killed regardless of our curl timeout.

**Mitigation**: Keep evaluations reasonably fast, use efficient prompts.

### 2. Local LLM Quality

The supervisor's judgment is only as good as the underlying LLM. Smaller models may:
- Miss subtle bugs
- Approve incomplete work
- Reject valid completions

**Mitigation**: Use capable models, tune supervisor prompts.

### 3. Single Workspace per Session

The supervisor mounts the workspace at startup. Switching workspaces requires restarting containers.

**Mitigation**: Document this clearly, use `docker compose down` when switching.

### 4. No Snapshot Isolation

The supervisor evaluates live workspace state. If agent modifies files during evaluation, results may be inconsistent.

**Mitigation**: Evaluation happens when agent is stopped (waiting for response).

### 5. Resource Contention

Both containers share the same LLM backend. During evaluation, agent is blocked but LLM serves supervisor.

**Mitigation**: Use LM Studio parallel mode for concurrent requests.

### 6. Multi-Instance GPU Contention

When running multiple instances, all agents share the same LLM backend which has limited GPU memory.

**Mitigation**:
- Use separate LLM backends per instance (e.g., different machines)
- Configure supervisor to use different backend with `SUPERVISOR_LLM_HOST`
- Stagger task starts to avoid concurrent heavy workloads

---

## Future Improvements

### Potential Enhancements

1. **Snapshot-based evaluation**: Copy workspace to temp dir before evaluation
2. **Multi-model evaluation**: Use different LLM for supervisor
3. **Structured output**: Fine-tune models for consistent JSON
4. **Incremental evaluation**: Only check changed files
5. **Human-in-the-loop**: Escalate uncertain evaluations

### Research Questions

1. Can we use consensus (multiple supervisor calls) for reliability?
2. Should supervisor have access to agent's Langfuse traces?
3. Can we detect and prevent agent attempts to game the system?

---

## References

- [Claude Code Hooks Documentation](https://docs.anthropic.com/claude-code)
- [Docker Compose Volumes](https://docs.docker.com/compose/compose-file/compose-file-v3/#volumes)
- [Langfuse Self-Hosting](https://langfuse.com/docs/deployment/self-host)
