#!/bin/bash
# Run Vanilla Claude Code container
# Uses Anthropic API with native tools

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Use home directory for workspaces (external drive has mount issues with Docker)
WORKSPACES_DIR="${HOME}/vanilla_workspaces"

# Load .env if exists (before checking for API key)
if [ -f "${SCRIPT_DIR}/.env" ]; then
    set -a
    source "${SCRIPT_DIR}/.env"
    set +a
fi

# Check for API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY environment variable is required"
    echo ""
    echo "Set it with:"
    echo "  export ANTHROPIC_API_KEY=sk-ant-..."
    echo ""
    echo "Or create a .env file in this directory with:"
    echo "  ANTHROPIC_API_KEY=sk-ant-..."
    exit 1
fi

# Get workspace name from argument or use default
WORKSPACE_NAME="${1:-default}"
# Remove workspace name from args so it's not passed to claude
shift 2>/dev/null || true

# Create workspace directory
WORKSPACE_PATH="${WORKSPACES_DIR}/${WORKSPACE_NAME}"
mkdir -p "$WORKSPACE_PATH"

echo "Starting Vanilla Claude Code"
echo "  Workspace: ${WORKSPACE_NAME}"
echo "  Path: ${WORKSPACE_PATH}"
echo "  Model: ${CLAUDE_MODEL:-claude-sonnet-4-20250514}"
echo "  Tracing: ${TRACE_TO_LANGFUSE:-false}"
echo ""

# Export for docker-compose
export WORKSPACE_NAME
export WORKSPACE_PATH

# Run container
cd "$SCRIPT_DIR"
docker compose run --rm --service-ports \
    -e WORKSPACE_NAME="$WORKSPACE_NAME" \
    -e WORKSPACE_PATH="$WORKSPACE_PATH" \
    claude "$@"
