#!/bin/bash
# Initialize workspace - runtime setup only
#
# CONFIG HARDENING: settings.json and CLAUDE.md generation has been moved to
# run.sh on the host. These files are now mounted read-only to prevent the
# agent from modifying hooks/settings to bypass guardrails.
# See: docs/CONFIG_HARDENING_PLAN.md

set -e

WORKSPACE_DIR="${HOME}/workspace"
CLAUDE_DIR="${WORKSPACE_DIR}/.claude"

# Start Xvfb virtual display for Playwright (headless browser)
if ! pgrep -x Xvfb > /dev/null; then
    Xvfb :99 -screen 0 1280x720x24 &
    sleep 1
    echo "Started Xvfb virtual display on :99"
fi

# =============================================================================
# Verify protected files are mounted (security check)
# =============================================================================
echo "Verifying protected config files..."

if [ ! -f "${CLAUDE_DIR}/settings.json" ]; then
    echo "ERROR: settings.json not mounted - run via 'make worker' for security"
    echo "Falling back to unprotected mode (for development only)"
    # Create full settings if not mounted (development/debug mode)
    # Uses same config as run.sh generate_settings_json() with default timeouts
    mkdir -p "$CLAUDE_DIR"

    # Calculate stop hook timeout (same logic as run.sh)
    SUPERVISOR_TIMEOUT_SEC="${SUPERVISOR_TIMEOUT:-3600}"
    STOP_HOOK_EXTRA_SEC="${STOP_HOOK_EXTRA_SEC:-1200}"
    STOP_HOOK_CMD_TIMEOUT="$((SUPERVISOR_TIMEOUT_SEC + STOP_HOOK_EXTRA_SEC))"

    cat > "${CLAUDE_DIR}/settings.json" << FALLBACK_EOF
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
FALLBACK_EOF
fi

if [ ! -f "${WORKSPACE_DIR}/CLAUDE.md" ]; then
    echo "WARNING: CLAUDE.md not mounted - behavioral instructions may be missing"
    # Copy from source if available
    if [ -f "${HOME}/.claude/CLAUDE.md" ]; then
        cp "${HOME}/.claude/CLAUDE.md" "${WORKSPACE_DIR}/CLAUDE.md"
        echo "Copied CLAUDE.md from source (unprotected fallback)"
    fi
fi

# Check if files are read-only (mounted correctly)
if touch "${CLAUDE_DIR}/settings.json" 2>/dev/null; then
    echo "WARNING: settings.json is writable - security hardening not active"
else
    echo "✓ settings.json is read-only (protected)"
fi

if touch "${WORKSPACE_DIR}/CLAUDE.md" 2>/dev/null; then
    echo "WARNING: CLAUDE.md is writable - security hardening not active"
else
    echo "✓ CLAUDE.md is read-only (protected)"
fi

# =============================================================================
# MCP Server Configuration (still done at runtime)
# TODO: Consider moving this to host for full protection
# =============================================================================
SEARXNG_URL="${SEARXNG_URL:-http://host.docker.internal:8888}"
CLAUDE_JSON="${HOME}/.claude.json"

if [ -f "$CLAUDE_JSON" ]; then
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

print(f"Configured SearXNG MCP server: {searxng_url}")
PYEOF
fi

# =============================================================================
# Workspace initialization complete
# =============================================================================
echo ""
echo "Workspace initialization complete"
echo "  Settings: ${CLAUDE_DIR}/settings.json"
echo "  Instructions: ${WORKSPACE_DIR}/CLAUDE.md"
echo "  Hooks: ${HOME}/.claude/hooks/"

# Display task if present
TASK_FILE="${WORKSPACE_DIR}/.original_task"
if [ -f "$TASK_FILE" ]; then
    TASK_CONTENT=$(cat "$TASK_FILE")
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
