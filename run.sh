#!/bin/bash
# Run Claude Code with isolated workspace
#
# Usage:
#   ./run.sh                    # Uses 'default' workspace
#   ./run.sh myproject          # Uses 'myproject' workspace
#   ./run.sh mario-game         # Uses 'mario-game' workspace
#
# Workspaces are stored in $WORKSPACE_BASE/<name>/ (default: ./workspaces/)
# Each workspace is isolated and mapped to /home/claude/workspace in container

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables from .env if present
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Command line arg overrides .env WORKSPACE_NAME
WORKSPACE_NAME="${1:-${WORKSPACE_NAME:-default}}"

# Workspace base directory (default: ./workspaces relative to project)
WORKSPACE_BASE="${WORKSPACE_BASE:-$SCRIPT_DIR/workspaces}"

# Full workspace path
WORKSPACE_PATH="$WORKSPACE_BASE/$WORKSPACE_NAME"

# Create workspace directory if it doesn't exist
mkdir -p "$WORKSPACE_PATH"

# Copy CLAUDE.md template if workspace doesn't have it
if [ ! -f "$WORKSPACE_PATH/CLAUDE.md" ] && [ -f "./CLAUDE.md" ]; then
    cp "./CLAUDE.md" "$WORKSPACE_PATH/CLAUDE.md"
    echo "Initialized workspace '$WORKSPACE_NAME' with CLAUDE.md"
fi

echo "Starting Claude Code with workspace: $WORKSPACE_NAME"
echo "  Host path: $WORKSPACE_PATH"
echo "  Container path: /home/claude/workspace"
echo ""

# Export for docker-compose
export WORKSPACE_PATH
# --service-ports: publish ports defined in docker-compose.yml
WORKSPACE_PATH="$WORKSPACE_PATH" docker compose run --rm --service-ports claude-local
