#!/bin/bash
# Initialize workspace with proper Claude Code configuration
# This script runs at container startup to set up tracing and hooks

set -e

# Start Xvfb for headless browser support (Playwright MCP)
if ! pgrep -x Xvfb > /dev/null; then
    Xvfb :99 -screen 0 1920x1080x24 &
    export DISPLAY=:99
    echo "Started Xvfb on display :99"
fi

WORKSPACE_DIR="${HOME}/workspace"
CLAUDE_DIR="${WORKSPACE_DIR}/.claude"

# Create .claude directory in workspace if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Generate PROJECT-LEVEL settings.json with hooks and MCP server configuration
# Project-level takes precedence over user-level, so hooks MUST be here
cat > "${CLAUDE_DIR}/settings.json" << EOF
{
  "permissions": {
    "allow": ["*"],
    "deny": ["WebSearch", "WebFetch", "EnterPlanMode", "mcp__playwright__browser_screenshot"]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${HOME}/.claude/hooks/langfuse_stop_hook.sh",
            "timeout": 300
          }
        ]
      }
    ]
  },
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp"],
      "env": {
        "DISPLAY": ":99"
      }
    }
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

# Add Playwright MCP server via CLI (settings.json mcpServers doesn't work)
# This registers it in ~/.claude.json which Claude Code actually reads
if ! claude mcp list 2>/dev/null | grep -q "playwright"; then
    echo "Adding Playwright MCP server..."
    claude mcp add playwright --env DISPLAY=:99 -- npx @playwright/mcp 2>/dev/null || true
fi

echo "Workspace initialization complete"
echo "Hook script: ${HOME}/.claude/hooks/langfuse_stop_hook.sh"
echo "Settings: ${CLAUDE_DIR}/settings.json"
