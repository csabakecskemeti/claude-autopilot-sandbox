#!/bin/bash
# Initialize workspace with proper Claude Code configuration
# This script runs at container startup to set up tracing and hooks

set -e

WORKSPACE_DIR="${HOME}/workspace"
CLAUDE_DIR="${WORKSPACE_DIR}/.claude"

# Create .claude directory in workspace if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Generate PROJECT-LEVEL settings.json with hooks configuration
# Project-level takes precedence over user-level, so hooks MUST be here
cat > "${CLAUDE_DIR}/settings.json" << EOF
{
  "permissions": {
    "allow": ["*"],
    "deny": ["WebSearch", "EnterPlanMode"]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/.claude/hooks/langfuse_stop_hook.sh",
            "timeout": 60
          }
        ]
      }
    ]
  },
  "env": {
    "TRACE_TO_LANGFUSE": "${TRACE_TO_LANGFUSE:-false}",
    "LANGFUSE_PUBLIC_KEY": "${LANGFUSE_PUBLIC_KEY:-}",
    "LANGFUSE_SECRET_KEY": "${LANGFUSE_SECRET_KEY:-}",
    "LANGFUSE_HOST": "${LANGFUSE_HOST:-http://localhost:3000}",
    "LANGFUSE_PROJECT": "${LANGFUSE_PROJECT:-claude-code}",
    "LANGFUSE_DEBUG": "${LANGFUSE_DEBUG:-false}"
  }
}
EOF

echo "Created ${CLAUDE_DIR}/settings.json with hooks and tracing configuration"

# Ensure the hooks state directory exists
mkdir -p "${HOME}/.claude/state"

# Verify hook script is executable
chmod +x "${HOME}/.claude/hooks/langfuse_stop_hook.sh" 2>/dev/null || true

echo "Workspace initialization complete"
echo "Hook script: ${HOME}/.claude/hooks/langfuse_stop_hook.sh"
echo "Settings: ${CLAUDE_DIR}/settings.json"
