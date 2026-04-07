#!/bin/bash
# Run Claude Code with isolated workspace and external supervisor
#
# Usage:
#   ./run.sh                              # Uses 'default' workspace
#   ./run.sh myproject                    # Uses 'myproject' workspace
#   ./run.sh myproject "Build a todo app" # With initial task
#
# Workspaces are stored in $WORKSPACE_BASE/<name>/ (default: ./workspaces/)
# Each workspace is isolated and mapped to /home/claude/workspace in container
#
# Architecture:
#   - Agent container: Runs Claude Code with full filesystem access
#   - Supervisor container: Validates task completion (read-only access)
#   - Stop hook calls supervisor API to verify completion before allowing stop

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables from .env if present
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Command line args
WORKSPACE_NAME="${1:-${WORKSPACE_NAME:-default}}"
ORIGINAL_TASK="${2:-${ORIGINAL_TASK:-}}"

# Workspace base directory (default: ./workspaces relative to project)
WORKSPACE_BASE="${WORKSPACE_BASE:-$SCRIPT_DIR/workspaces}"

# Full workspace path
WORKSPACE_PATH="$WORKSPACE_BASE/$WORKSPACE_NAME"

# Supervisor workspace path (for turn isolation)
SUPERVISOR_WORKSPACES="$WORKSPACE_BASE/${WORKSPACE_NAME}-supervisor"

# Task storage path (immutable - mounted read-only to both containers)
TASK_STORAGE="$WORKSPACE_BASE/${WORKSPACE_NAME}-task"

# Create workspace directories if they don't exist
mkdir -p "$WORKSPACE_PATH"
mkdir -p "$SUPERVISOR_WORKSPACES"
mkdir -p "$TASK_STORAGE"

# Copy CLAUDE.md template if workspace doesn't have it
# NOTE: Use claude-backup/CLAUDE.md (autonomous agent instructions)
#       NOT ./CLAUDE.md (project development instructions)
if [ ! -f "$WORKSPACE_PATH/CLAUDE.md" ] && [ -f "./claude-backup/CLAUDE.md" ]; then
    cp "./claude-backup/CLAUDE.md" "$WORKSPACE_PATH/CLAUDE.md"
    echo "Initialized workspace '$WORKSPACE_NAME' with CLAUDE.md"
fi

# Write original task to IMMUTABLE task storage (mounted read-only to containers)
if [ -n "$ORIGINAL_TASK" ]; then
    # Write to immutable location (host controls this, containers can only read)
    echo "$ORIGINAL_TASK" > "$TASK_STORAGE/original_task"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TASK_STORAGE/created_at"
    echo "$ORIGINAL_TASK" | sha256sum | cut -d' ' -f1 > "$TASK_STORAGE/task_hash"

    # Also write a copy to agent workspace for convenience (agent can see the task)
    # But the AUTHORITATIVE version is in $TASK_STORAGE (read-only mount)
    echo "$ORIGINAL_TASK" > "$WORKSPACE_PATH/.original_task"

    echo "Original task saved to immutable storage"
fi

# Clean up any stale completion marker from previous runs
if [ -f "$WORKSPACE_PATH/.supervisor_complete" ]; then
    echo "Removing stale completion marker from previous run"
    rm -f "$WORKSPACE_PATH/.supervisor_complete"
fi

# Reset supervisor loop counter for fresh run
if [ -f "$SUPERVISOR_WORKSPACES/.loop_count" ]; then
    echo "Resetting supervisor loop counter"
    rm -f "$SUPERVISOR_WORKSPACES/.loop_count"
fi

echo "Starting Claude Code with workspace: $WORKSPACE_NAME"
echo "  Agent workspace: $WORKSPACE_PATH"
echo "  Supervisor workspace: $SUPERVISOR_WORKSPACES"
echo "  Task storage (immutable): $TASK_STORAGE"
if [ -n "$ORIGINAL_TASK" ]; then
    echo "  Task: ${ORIGINAL_TASK:0:100}..."
fi
echo ""

# Export for docker-compose
export WORKSPACE_PATH
export SUPERVISOR_WORKSPACES
export TASK_STORAGE
export ORIGINAL_TASK

# Run with supervisor (agent depends on supervisor being healthy)
# --service-ports: publish ports defined in docker-compose.yml
# ORIGINAL_TASK env var is passed to container and used by entrypoint
docker compose run --rm --service-ports agent
