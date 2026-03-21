# Langfuse Tracing Setup

This document explains how to set up tracing for Claude Code sessions using Langfuse (self-hosted).

## Overview

Tracing captures every turn of Claude Code sessions and sends them to Langfuse for:
- **Evaluation** - Analyze agent performance across tasks
- **Debugging** - See exactly what happened in each turn
- **Metrics** - Track token usage, tool calls, success rates

## Architecture

```
Claude Code Session
        ↓
   Stop Hook fires (after each response)
        ↓
   stop_hook.sh reads transcript
        ↓
   Sends trace to Langfuse API
        ↓
   Langfuse UI shows traces
```

## Prerequisites

1. **Langfuse instance** - Self-hosted at `http://localhost:3000` (or your URL)
2. **API keys** - Get from Langfuse Settings → API Keys

## Configuration

### 1. Environment Variables

Add to `.env`:

```env
# Langfuse Tracing (for agent evaluation)
TRACE_TO_LANGFUSE=true
LANGFUSE_PUBLIC_KEY=pk-lf-your-public-key
LANGFUSE_SECRET_KEY=sk-lf-your-secret-key
LANGFUSE_HOST=http://host.docker.internal:3000
LANGFUSE_PROJECT=claude-autopilot-sandbox
LANGFUSE_DEBUG=false
```

**Note:** Use `host.docker.internal` to access localhost from inside Docker.

### 2. Project-Level Settings (Critical!)

The `init-workspace.sh` script automatically creates `~/workspace/.claude/settings.json` with:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/claude/.claude/hooks/stop_hook.sh",
            "timeout": 60
          }
        ]
      }
    ]
  },
  "env": {
    "TRACE_TO_LANGFUSE": "true",
    ...
  }
}
```

**Why project-level?** Claude Code settings have precedence:
1. Project-level (`.claude/settings.json`) ← **Hooks must be here**
2. User-level (`~/.claude/settings.json`)
3. Local (`.claude/settings.local.json`)

If hooks are only in user-level settings, they get overridden by any project-level config.

### 3. The Stop Hook

Located at `~/.claude/hooks/stop_hook.sh`, this script:

1. Receives session data via stdin from Claude Code
2. Reads the transcript file
3. Parses messages into turns
4. Creates Langfuse traces with:
   - Trace per turn
   - Generations for LLM calls
   - Spans for tool uses
5. Groups by `sessionId` for conversation view

## How It Works

### Hook Input (stdin)

Claude Code passes this JSON to the Stop hook:

```json
{
  "session_id": "bf9e30e1-e1be-4409-9782-6e9a90b64caf",
  "transcript_path": "~/.claude/projects/-home-claude-workspace/bf9e30e1-e1be-4409-9782-6e9a90b64caf.jsonl",
  "stop_hook_active": false,
  "last_assistant_message": "I've completed the task..."
}
```

### Transcript Location

Session transcripts are stored at:
```
~/.claude/projects/-home-claude-workspace/<session_id>.jsonl
```

Each line is a JSON message (user, assistant, tool_use, tool_result).

### Trace Structure in Langfuse

```
Session (grouped by sessionId)
└── Turn 1 (trace)
    ├── LLM Call (generation)
    │   ├── Tool: Read (span)
    │   └── Tool: Write (span)
    └── Output
└── Turn 2 (trace)
    └── ...
```

## Debugging

### Check if hook is firing

```bash
# View hook log
docker exec $(docker ps -q -f name=claude) cat ~/.claude/state/hook.log
```

Log should show:
```
2026-03-20 12:34:56 [INFO] === Stop hook invoked ===
2026-03-20 12:34:56 [INFO] TRACE_TO_LANGFUSE=true
2026-03-20 12:34:56 [INFO] Received stdin (234 bytes): {"session_id":"...
```

### No hook.log file?

Hook isn't being triggered. Check:

1. **Project-level settings exist:**
   ```bash
   docker exec $(docker ps -q -f name=claude) cat ~/workspace/.claude/settings.json
   ```

2. **Hook script is executable:**
   ```bash
   docker exec $(docker ps -q -f name=claude) ls -la ~/.claude/hooks/stop_hook.sh
   ```

3. **Rebuild container** after changes:
   ```bash
   docker compose down
   docker compose build --no-cache
   docker compose up -d
   ```

### Hook fires but no traces in Langfuse?

Check for API errors in hook.log:
```bash
docker exec $(docker ps -q -f name=claude) grep ERROR ~/.claude/state/hook.log
```

Common issues:
- Wrong API keys
- `LANGFUSE_HOST` not accessible from container
- Langfuse not running

### Manual test

```bash
docker exec -it $(docker ps -q -f name=claude) bash -c '
export LANGFUSE_DEBUG=true
export TRACE_TO_LANGFUSE=true
echo "{\"session_id\": \"test-123\", \"transcript_path\": \"$HOME/.claude/projects/-home-claude-workspace/$(ls $HOME/.claude/projects/-home-claude-workspace/*.jsonl | head -1 | xargs basename)\"}" | bash ~/.claude/hooks/stop_hook.sh
'
```

## Files

| File | Purpose |
|------|---------|
| `.env` | Langfuse credentials (gitignored) |
| `scripts/init-workspace.sh` | Creates project-level settings at startup |
| `hooks-backup/stop_hook.sh` | Sends traces to Langfuse |
| `~/.claude/state/hook.log` | Debug log (in container) |
| `~/.claude/state/langfuse_state.json` | Tracks processed messages |

## Key Learnings

1. **Settings precedence matters** - Project-level overrides user-level, so hooks MUST be in project-level settings
2. **Use absolute paths** - `/home/claude/.claude/hooks/stop_hook.sh` not relative paths
3. **host.docker.internal** - Access host localhost from inside container
4. **Debug logging** - Set `LANGFUSE_DEBUG=true` to see detailed logs in hook.log
5. **Hook fires on every turn** - Each Claude response triggers the Stop hook

## References

- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [How to Configure Hooks](https://claude.com/blog/how-to-configure-hooks)
- [Langfuse API Documentation](https://langfuse.com/docs/api)
