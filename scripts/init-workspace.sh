#!/bin/bash
# Initialize workspace with proper Claude Code configuration
# This script runs at container startup to set up tracing and hooks

set -e

# Start Xvfb virtual display for Playwright (headless browser)
if ! pgrep -x Xvfb > /dev/null; then
    Xvfb :99 -screen 0 1280x720x24 &
    sleep 1
    echo "Started Xvfb virtual display on :99"
fi

WORKSPACE_DIR="${HOME}/workspace"
CLAUDE_DIR="${WORKSPACE_DIR}/.claude"

# Create .claude directory in workspace if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Stop hook runtime budget: Langfuse ingest can take a long time, then curl waits up to SUPERVISOR_TIMEOUT.
# Claude Code kills the whole hook if JSON "timeout" is exceeded — must be > curl max-time + tracing work.
SUPERVISOR_TIMEOUT_SEC="${SUPERVISOR_TIMEOUT:-3600}"
STOP_HOOK_EXTRA_SEC="${STOP_HOOK_EXTRA_SEC:-1200}"
STOP_HOOK_CMD_TIMEOUT="$((SUPERVISOR_TIMEOUT_SEC + STOP_HOOK_EXTRA_SEC))"

# SearXNG URL - default to host.docker.internal for Docker Desktop (Mac/Windows)
# Can be overridden via SEARXNG_URL environment variable
SEARXNG_URL="${SEARXNG_URL:-http://host.docker.internal:8888}"

# Update ~/.claude.json with MCP server config
# MCP servers must be in ~/.claude.json, NOT ~/.claude/settings.json
CLAUDE_JSON="${HOME}/.claude.json"
if [ -f "$CLAUDE_JSON" ]; then
    # Read existing config and add MCP server for this workspace
    # Using Python for reliable JSON manipulation
    python3 << PYEOF
import json
import os

claude_json_path = "${CLAUDE_JSON}"
workspace_path = "${WORKSPACE_DIR}"
searxng_url = "${SEARXNG_URL}"
mcp_server_path = os.path.expandvars("${HOME}/.claude/mcp-servers/searxng/index.js")

# Read existing config
with open(claude_json_path, 'r') as f:
    config = json.load(f)

# Ensure projects dict exists
if 'projects' not in config:
    config['projects'] = {}

# Ensure workspace entry exists
if workspace_path not in config['projects']:
    config['projects'][workspace_path] = {}

# Add MCP server config for this workspace
config['projects'][workspace_path]['mcpServers'] = {
    "searxng": {
        "type": "stdio",
        "command": "node",
        "args": [mcp_server_path],
        "env": {
            "SEARXNG_URL": searxng_url
        }
    }
}

# Write updated config
with open(claude_json_path, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Added SearXNG MCP server to {claude_json_path} for workspace {workspace_path}")
PYEOF
fi

# Generate PROJECT-LEVEL settings.json with hooks configuration
# Project-level takes precedence over user-level, so hooks MUST be here
# NOTE: MCP servers go in ~/.claude.json (handled separately below)
# NOTE: One Stop hook only — langfuse_stop_hook.sh runs Langfuse then supervisor in order.
#       Claude Code runs multiple Stop commands in PARALLEL; split hooks would not guarantee order.
# NOTE: PreToolUse hook blocks image reads to prevent multimodal errors with local LLMs.
cat > "${CLAUDE_DIR}/settings.json" << EOF
{
  "permissions": {
    "allow": ["*"],
    "deny": ["WebSearch", "WebFetch", "EnterPlanMode", "TodoWrite"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/.claude/hooks/block_image_read.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/.claude/hooks/langfuse_stop_hook.sh",
            "timeout": ${STOP_HOOK_CMD_TIMEOUT}
          }
        ]
      }
    ]
  },
  "env": {
    "MAX_THINKING_TOKENS": "0",
    "TRACE_TO_LANGFUSE": "${TRACE_TO_LANGFUSE:-false}",
    "LANGFUSE_PUBLIC_KEY": "${LANGFUSE_PUBLIC_KEY:-}",
    "LANGFUSE_SECRET_KEY": "${LANGFUSE_SECRET_KEY:-}",
    "LANGFUSE_HOST": "${LANGFUSE_HOST:-http://localhost:3000}",
    "LANGFUSE_PROJECT": "${LANGFUSE_PROJECT:-claude-code}",
    "LANGFUSE_DEBUG": "${LANGFUSE_DEBUG:-false}",
    "MAX_CONTINUE_CYCLES": "${MAX_CONTINUE_CYCLES:-100}",
    "SUPERVISOR_URL": "${SUPERVISOR_URL:-http://supervisor:8080}",
    "SUPERVISOR_TIMEOUT": "${SUPERVISOR_TIMEOUT:-3600}",
    "STOP_HOOK_EXTRA_SEC": "${STOP_HOOK_EXTRA_SEC:-1200}",
    "SUPERVISOR_AUTONOMY_APPEND": "${SUPERVISOR_AUTONOMY_APPEND:-true}"
  }
}
EOF

echo "Created ${CLAUDE_DIR}/settings.json with hooks, MCP servers, and tracing configuration"
echo "SearXNG MCP server configured at: ${SEARXNG_URL}"

# Copy CLAUDE.md to workspace if it doesn't exist
if [ ! -f "${WORKSPACE_DIR}/CLAUDE.md" ] && [ -f "${HOME}/.claude/CLAUDE.md" ]; then
    cp "${HOME}/.claude/CLAUDE.md" "${WORKSPACE_DIR}/CLAUDE.md"
    echo "Copied CLAUDE.md to workspace"
fi

# Ensure the hooks state directory exists
mkdir -p "${HOME}/.claude/state"

# Verify hook scripts are executable
chmod +x "${HOME}/.claude/hooks/langfuse_stop_hook.sh" 2>/dev/null || true
chmod +x "${HOME}/.claude/hooks/block_image_read.sh" 2>/dev/null || true

echo "Workspace initialization complete"
echo "PreToolUse hook: ${HOME}/.claude/hooks/block_image_read.sh (blocks image reads)"
echo "Stop hook: ${HOME}/.claude/hooks/langfuse_stop_hook.sh (Langfuse then supervisor)"
echo "Settings: ${CLAUDE_DIR}/settings.json"

# Check if there's an original task to work on
TASK_FILE="${WORKSPACE_DIR}/.original_task"
if [ -f "$TASK_FILE" ]; then
    TASK_CONTENT=$(cat "$TASK_FILE")

    # Create TASK.md that Claude will see and act on
    cat > "${WORKSPACE_DIR}/TASK.md" << TASKEOF
# YOUR TASK

Complete this task autonomously:

---
${TASK_CONTENT}
---

Start working on this immediately. The supervisor will verify your work when you're done.
TASKEOF

    echo ""
    echo "=========================================="
    echo "TASK TO COMPLETE:"
    echo "=========================================="
    echo "$TASK_CONTENT"
    echo "=========================================="
    echo ""
    echo "Copy and paste the task above into Claude, or type: Read TASK.md and complete it"
    echo ""
fi
