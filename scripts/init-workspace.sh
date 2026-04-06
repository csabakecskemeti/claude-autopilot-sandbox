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

# Generate PROJECT-LEVEL settings.json with hooks configuration
# Project-level takes precedence over user-level, so hooks MUST be here
# NOTE: One Stop hook only — langfuse_stop_hook.sh runs Langfuse then supervisor in order.
#       Claude Code runs multiple Stop commands in PARALLEL; split hooks would not guarantee order.
# NOTE: Using Python Playwright (not MCP) - called via Bash tool, no MCP config needed
cat > "${CLAUDE_DIR}/settings.json" << EOF
{
  "permissions": {
    "allow": ["*"],
    "deny": ["WebSearch", "WebFetch", "EnterPlanMode", "TodoWrite"]
  },
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/.claude/hooks/langfuse_stop_hook.sh",
            "timeout": 3600
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
    "SUPERVISOR_TIMEOUT": "${SUPERVISOR_TIMEOUT:-3600}"
  }
}
EOF

echo "Created ${CLAUDE_DIR}/settings.json with hooks and tracing configuration"

# Copy CLAUDE.md to workspace if it doesn't exist
if [ ! -f "${WORKSPACE_DIR}/CLAUDE.md" ] && [ -f "${HOME}/.claude/CLAUDE.md" ]; then
    cp "${HOME}/.claude/CLAUDE.md" "${WORKSPACE_DIR}/CLAUDE.md"
    echo "Copied CLAUDE.md to workspace"
fi

# Ensure the hooks state directory exists
mkdir -p "${HOME}/.claude/state"

# Verify hook script is executable
chmod +x "${HOME}/.claude/hooks/langfuse_stop_hook.sh" 2>/dev/null || true

echo "Workspace initialization complete"
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
