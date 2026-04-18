#!/bin/bash
# Run Claude Code with isolated workspace and external supervisor
#
# Usage:
#   ./run.sh                              # Uses 'default' workspace
#   ./run.sh myproject                    # Uses 'myproject' workspace
#   ./run.sh myproject "Build a todo app" # With initial task
#
# Multi-Instance Support (instance names and ports auto-generated):
#   ./run.sh proj1 "Build a todo app"    # agent-a1b2..., ports 23000, 25000...
#   ./run.sh proj2 "Build a chat app"    # agent-e5f6..., ports 43000, 45000...
#   PORT_PREFIX=6 ./run.sh proj3 "Build API"  # explicit ports 63000, 65000...
#
# Remote Supervisor (run on different machine, e.g., DGX Spark):
#   SKIP_LOCAL_SUPERVISOR=true SUPERVISOR_URL=http://dgx-spark:8080 ./run.sh myproj
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

# Instance identification (for multi-instance deployments)
# Generate random instance name if not specified (allows multiple parallel runs)
if [ -z "$INSTANCE_NAME" ]; then
    INSTANCE_NAME="agent-$(head -c 4 /dev/urandom | xxd -p)"
fi

# Compute hash from instance name for deterministic port assignment
INSTANCE_HASH=$(echo -n "$INSTANCE_NAME" | md5sum | cut -c1-4)
INSTANCE_HASH_NUM=$((16#$INSTANCE_HASH))

# Port prefix for multi-instance - single digit prepended to container ports
# Example: PORT_PREFIX=2 → 23000, 25000, 28000, 28080
# Example: PORT_PREFIX=3 → 33000, 35000, 38000, 38080
# Max is 5 (58080 < 65535, but 68000 > 65535), so range is 2-5
if [ -z "$PORT_PREFIX" ]; then
    PORT_PREFIX=$((2 + (INSTANCE_HASH_NUM % 4)))
fi

# Container naming prefix
CONTAINER_PREFIX="${CONTAINER_PREFIX:-claude}"

# Remote supervisor mode (skip local supervisor container)
SKIP_LOCAL_SUPERVISOR="${SKIP_LOCAL_SUPERVISOR:-false}"
SUPERVISOR_URL="${SUPERVISOR_URL:-http://supervisor:8080}"

# Supervisor external port - also derived from instance if not set
if [ -z "$SUPERVISOR_EXTERNAL_PORT" ]; then
    # Use same hash, different offset range (8080-8119)
    SUPERVISOR_EXTERNAL_PORT=$((8080 + (INSTANCE_HASH_NUM % 40)))
fi

# Export SKIP_LOCAL_SUPERVISOR for docker-compose conditional profiles
export SKIP_LOCAL_SUPERVISOR

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
echo "  Instance: $INSTANCE_NAME"
echo "  Agent workspace: $WORKSPACE_PATH"
echo "  Supervisor workspace: $SUPERVISOR_WORKSPACES"
echo "  Task storage (immutable): $TASK_STORAGE"
echo "  Ports: ${PORT_PREFIX}3000, ${PORT_PREFIX}5000, ${PORT_PREFIX}8000, ${PORT_PREFIX}8080"
if [ "$SKIP_LOCAL_SUPERVISOR" = "true" ]; then
    echo "  Supervisor: REMOTE ($SUPERVISOR_URL)"
else
    echo "  Supervisor: LOCAL (port $SUPERVISOR_EXTERNAL_PORT)"
fi
if [ -n "$ORIGINAL_TASK" ]; then
    echo "  Task: ${ORIGINAL_TASK:0:100}..."
fi
echo ""

# Export for docker-compose
export WORKSPACE_PATH
export SUPERVISOR_WORKSPACES
export TASK_STORAGE
export ORIGINAL_TASK
export INSTANCE_NAME
export PORT_PREFIX
export CONTAINER_PREFIX
export SUPERVISOR_URL
export SUPERVISOR_EXTERNAL_PORT

# Docker Compose project name for isolation (allows multiple stacks)
export COMPOSE_PROJECT_NAME="${CONTAINER_PREFIX}-${INSTANCE_NAME}"

# Run with supervisor or agent-only (remote supervisor)
# --service-ports: publish ports defined in docker-compose.yml
# ORIGINAL_TASK env var is passed to container and used by entrypoint
if [ "$SKIP_LOCAL_SUPERVISOR" = "true" ]; then
    echo "Running agent-only mode (using remote supervisor at $SUPERVISOR_URL)"
    docker compose run --rm --service-ports --no-deps agent
else
    docker compose run --rm --service-ports agent
fi
