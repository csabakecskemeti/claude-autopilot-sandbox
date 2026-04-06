#!/bin/bash
# Initialize workspace for Vanilla Claude Code
# Sets up tracing hooks, Xvfb for browser automation

set -e

# Start Xvfb virtual display for Playwright (headless browser)
if ! pgrep -x "Xvfb" > /dev/null; then
    Xvfb :99 -screen 0 1280x720x24 &
    sleep 1
    echo "Started Xvfb virtual display on :99"
fi

WORKSPACE_DIR="${HOME}/workspace"
CLAUDE_DIR="${WORKSPACE_DIR}/.claude"

# Create .claude directory in workspace
mkdir -p "$CLAUDE_DIR"

# Generate PROJECT-LEVEL settings.json with hooks configuration
# NOTE: Native tools (WebSearch, WebFetch, etc.) are ALLOWED in vanilla version
cat > "${CLAUDE_DIR}/settings.json" << EOF
{
  "permissions": {
    "allow": ["*"],
    "deny": []
  },
  "hooks": {
    "Stop": [
      {
        "matcher": "",
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
  "env": {
    "TRACE_TO_LANGFUSE": "${TRACE_TO_LANGFUSE:-false}",
    "LANGFUSE_PUBLIC_KEY": "${LANGFUSE_PUBLIC_KEY:-}",
    "LANGFUSE_SECRET_KEY": "${LANGFUSE_SECRET_KEY:-}",
    "LANGFUSE_HOST": "${LANGFUSE_HOST:-http://localhost:3000}",
    "LANGFUSE_PROJECT": "${LANGFUSE_PROJECT:-claude-vanilla}",
    "LANGFUSE_DEBUG": "${LANGFUSE_DEBUG:-false}"
  }
}
EOF

echo "Created ${CLAUDE_DIR}/settings.json"

# Copy CLAUDE.md to workspace if it doesn't exist
if [ ! -f "${WORKSPACE_DIR}/CLAUDE.md" ]; then
    cp "${HOME}/.claude/CLAUDE.md" "${WORKSPACE_DIR}/CLAUDE.md"
    echo "Copied CLAUDE.md to workspace"
fi

# Ensure the hooks state directory exists
mkdir -p "${HOME}/.claude/state"

# Verify hook script is executable
chmod +x "${HOME}/.claude/hooks/langfuse_stop_hook.sh" 2>/dev/null || true

echo "Workspace initialization complete (vanilla mode)"
echo "Native tools enabled: WebSearch, WebFetch, TodoWrite, EnterPlanMode"
echo "Browser automation: Playwright with Chromium (Xvfb on :99)"
