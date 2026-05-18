#!/bin/bash
# Run Claude Code with isolated workspace and dedicated supervisor
#
# Usage:
#   ./run.sh myproject "Build a todo app"     # With task
#   ./run.sh myproject TF=task.txt            # Task from file
#   ./run.sh myproject                         # Interactive (no task)
#   ENV=.env-dgx2 ./run.sh myproject "task"   # With specific env file
#
# Each `make worker W=<label>` creates an isolated folder (worker run id = <label>_<timestamp>):
#   $WORKSPACE_BASE/{label}_{timestamp}/
#   ├── worker/       # Agent workspace
#   ├── task/         # Immutable task storage
#   ├── supervisor/   # Supervisor workspace (visible from host)
#   └── metadata.json # Run configuration and status
#
# Architecture:
#   - Agent container: Runs Claude Code with full filesystem access
#   - Supervisor container: Dedicated per-agent, validates task completion
#   - Stop hook calls supervisor API to verify completion before allowing stop

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# CONFIG HARDENING: Generate settings.json on host (mounted read-only)
# This prevents the agent from modifying hooks/settings to bypass guardrails
# See: docs/CONFIG_HARDENING_PLAN.md
# =============================================================================
generate_settings_json() {
    local output_file="$1"
    local stop_hook_timeout="$2"

    cat > "$output_file" << SETTINGS_EOF
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
            "command": "/home/claude/.claude/hooks/block_image_read.sh",
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
            "command": "/home/claude/.claude/hooks/langfuse_stop_hook.sh",
            "timeout": ${stop_hook_timeout}
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
SETTINGS_EOF
    echo "Generated settings.json: $output_file"
}

# Generate user-level settings.json (prevents agent from creating its own)
# This blocks the gap where agent could add env vars or change deny list at user level
# MUST include skipDangerousModePermissionPrompt to avoid interactive prompt
# MUST include deny list for local LLM setup (native WebSearch/WebFetch don't work)
generate_user_settings_json() {
    local output_file="$1"

    cat > "$output_file" << 'USER_SETTINGS_EOF'
{
  "permissions": {
    "allow": ["*"],
    "deny": ["WebSearch", "WebFetch", "EnterPlanMode", "TodoWrite"]
  },
  "hooks": {},
  "env": {},
  "skipDangerousModePermissionPrompt": true
}
USER_SETTINGS_EOF
    echo "Generated user-settings.json: $output_file"
}

# Load environment variables from env file
ENV_FILE="${ENV_FILE:-${ENV:-.env}}"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
    echo "Using config: $ENV_FILE"
fi

# =============================================================================
# HARDENING LEVEL: Controls config protection (see docs/HARDENING_LEVELS.md)
#   strict (default): All config locked - production autonomous runs
#   moderate:         Guardrails locked, can create new tools - trusted dev tasks
#   permissive:       Minimal protection - debugging, agent development
# =============================================================================
HARDENING="${HARDENING:-strict}"

# Validate hardening level
case "$HARDENING" in
    strict|moderate|permissive)
        echo "Hardening level: $HARDENING"
        ;;
    *)
        echo "Error: Invalid HARDENING level: $HARDENING"
        echo "Valid options: strict, moderate, permissive"
        exit 1
        ;;
esac

# Command line args
WORKSPACE_NAME="${1:-${WORKSPACE_NAME:-default}}"
ORIGINAL_TASK="${2:-${ORIGINAL_TASK:-}}"

# Check if task is a file reference (TF=filename)
if [[ "$ORIGINAL_TASK" == TF=* ]]; then
    TASK_FILE="${ORIGINAL_TASK#TF=}"
    if [ -f "$TASK_FILE" ]; then
        ORIGINAL_TASK="$(cat "$TASK_FILE")"
    else
        echo "Error: Task file not found: $TASK_FILE"
        exit 1
    fi
fi

# Timestamp for unique folder name
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TASK_FULL_NAME="${WORKSPACE_NAME}_${TIMESTAMP}"

# Workspace base directory (default: ./workspaces relative to project)
WORKSPACE_BASE="${WORKSPACE_BASE:-$SCRIPT_DIR/workspaces}"

# Task directory (parent folder containing all task artifacts)
TASK_DIR="$WORKSPACE_BASE/$TASK_FULL_NAME"

# Subdirectories within task folder
WORKSPACE_PATH="$TASK_DIR/worker"
TASK_STORAGE="$TASK_DIR/task"
SUPERVISOR_WORKSPACES="$TASK_DIR/supervisor"
METADATA_FILE="$TASK_DIR/metadata.json"

# Container naming (based on task name, not random)
CONTAINER_PREFIX="${CONTAINER_PREFIX:-claude}"
AGENT_CONTAINER="${CONTAINER_PREFIX}-agent-${TASK_FULL_NAME}"
SUPERVISOR_CONTAINER="${CONTAINER_PREFIX}-supervisor-${TASK_FULL_NAME}"

# Allocate ports dynamically
echo "Allocating ports..."
ALLOCATED_PORTS=($(./scripts/allocate-ports.sh 4 "$WORKSPACE_BASE"))
if [ ${#ALLOCATED_PORTS[@]} -lt 4 ]; then
    echo "Error: Failed to allocate ports"
    exit 1
fi

PORT_AGENT_3000="${ALLOCATED_PORTS[0]}"
PORT_AGENT_5000="${ALLOCATED_PORTS[1]}"
PORT_AGENT_8000="${ALLOCATED_PORTS[2]}"
PORT_SUPERVISOR="${ALLOCATED_PORTS[3]}"

# SearXNG integration (external by default)
INCLUDE_SEARXNG="${INCLUDE_SEARXNG:-${SEARXNG:-false}}"
if [ "$INCLUDE_SEARXNG" = "1" ]; then
    INCLUDE_SEARXNG="true"
fi

# Create task directory structure
echo "Creating task directory: $TASK_DIR"
mkdir -p "$WORKSPACE_PATH"
mkdir -p "$WORKSPACE_PATH/.claude"
mkdir -p "$TASK_STORAGE"
mkdir -p "$SUPERVISOR_WORKSPACES"

# =============================================================================
# CONFIG HARDENING: Generate configs on host (will be mounted read-only)
# Agent cannot modify these files - kernel-enforced via Docker bind mounts
# =============================================================================

# Calculate stop hook timeout
SUPERVISOR_TIMEOUT_SEC="${SUPERVISOR_TIMEOUT:-3600}"
STOP_HOOK_EXTRA_SEC="${STOP_HOOK_EXTRA_SEC:-1200}"
STOP_HOOK_CMD_TIMEOUT="$((SUPERVISOR_TIMEOUT_SEC + STOP_HOOK_EXTRA_SEC))"

# Generate settings.json with hooks config (mounted read-only in container)
generate_settings_json "$WORKSPACE_PATH/.claude/settings.json" "$STOP_HOOK_CMD_TIMEOUT"

# Generate user-level settings.json (prevents agent from creating its own at ~/.claude/settings.json)
generate_user_settings_json "$WORKSPACE_PATH/.claude/user-settings.json"

# Copy CLAUDE.md (mounted read-only in container)
cp "./claude-backup/CLAUDE.md" "$WORKSPACE_PATH/CLAUDE.md"
echo "Copied CLAUDE.md (will be mounted read-only)"

# Write original task to IMMUTABLE task storage
if [ -n "$ORIGINAL_TASK" ]; then
    echo "$ORIGINAL_TASK" > "$TASK_STORAGE/original_task"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TASK_STORAGE/created_at"
    echo "$ORIGINAL_TASK" | sha256sum | cut -d' ' -f1 > "$TASK_STORAGE/task_hash"
    echo "$ORIGINAL_TASK" > "$WORKSPACE_PATH/.original_task"

    # Create TASK.md for easy agent access
    echo "$ORIGINAL_TASK" > "$WORKSPACE_PATH/TASK.md"
fi

# Get image info
AGENT_IMAGE="local-claude-docker-agent:latest"
AGENT_IMAGE_SHA=$(docker images --no-trunc --format '{{.ID}}' "$AGENT_IMAGE" 2>/dev/null | head -1 || echo "unknown")
SUPERVISOR_IMAGE_SHA=$(docker images --no-trunc --format '{{.ID}}' "local-claude-docker-supervisor:latest" 2>/dev/null | head -1 || echo "unknown")

# Generate metadata.json
cat > "$METADATA_FILE" << EOF
{
  "version": "1.0",
  "task": {
    "name": "$WORKSPACE_NAME",
    "full_name": "$TASK_FULL_NAME",
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "original_task": $(echo "$ORIGINAL_TASK" | jq -Rs .)
  },
  "env": {
    "file": "$ENV_FILE",
    "llm_host": "${LLM_HOST:-}",
    "llm_port": ${LLM_PORT:-11234},
    "llm_model": "${LLM_MODEL:-}",
    "hardening": "$HARDENING"
  },
  "containers": {
    "agent": {
      "name": "$AGENT_CONTAINER",
      "image": "$AGENT_IMAGE",
      "image_sha": "$AGENT_IMAGE_SHA"
    },
    "supervisor": {
      "name": "$SUPERVISOR_CONTAINER",
      "image": "local-claude-docker-supervisor:latest",
      "image_sha": "$SUPERVISOR_IMAGE_SHA"
    }
  },
  "ports": {
    "agent": {
      "3000": $PORT_AGENT_3000,
      "5000": $PORT_AGENT_5000,
      "8000": $PORT_AGENT_8000
    },
    "supervisor": {
      "8080": $PORT_SUPERVISOR
    }
  },
  "paths": {
    "task_dir": "$TASK_DIR",
    "worker": "$WORKSPACE_PATH",
    "task": "$TASK_STORAGE",
    "supervisor": "$SUPERVISOR_WORKSPACES"
  },
  "status": {
    "state": "starting",
    "start_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "stop_time": null,
    "exit_code": null
  }
}
EOF

echo ""
echo "=========================================="
echo "Task: $TASK_FULL_NAME"
echo "=========================================="
echo "  Config: $ENV_FILE"
echo "  Hardening: $HARDENING"
echo "  LLM: ${LLM_HOST:-localhost}:${LLM_PORT:-11234} (${LLM_MODEL:-default})"
echo ""
echo "  Folders:"
echo "    Worker:     $WORKSPACE_PATH"
echo "    Task:       $TASK_STORAGE"
echo "    Supervisor: $SUPERVISOR_WORKSPACES"
echo "    Metadata:   $METADATA_FILE"
echo ""
echo "  Ports:"
echo "    Agent:      $PORT_AGENT_3000, $PORT_AGENT_5000, $PORT_AGENT_8000"
echo "    Supervisor: $PORT_SUPERVISOR"
echo ""
echo "  Containers:"
echo "    Agent:      $AGENT_CONTAINER"
echo "    Supervisor: $SUPERVISOR_CONTAINER"
echo ""
if [ "$INCLUDE_SEARXNG" = "true" ]; then
    echo "  SearXNG: INTEGRATED"
else
    echo "  SearXNG: EXTERNAL (host.docker.internal:8888)"
fi
if [ -n "$ORIGINAL_TASK" ]; then
    echo ""
    echo "  Task: ${ORIGINAL_TASK:0:100}..."
fi
echo "=========================================="
echo ""

# Export for docker-compose
export WORKSPACE_PATH
export WORKSPACE_NAME="$TASK_FULL_NAME"
export SUPERVISOR_WORKSPACES
export TASK_STORAGE
export ORIGINAL_TASK
export AGENT_CONTAINER
export SUPERVISOR_CONTAINER
export PORT_AGENT_3000
export PORT_AGENT_5000
export PORT_AGENT_8000
export PORT_SUPERVISOR
export SUPERVISOR_URL="http://supervisor:8080"

# Docker Compose project name for isolation
export COMPOSE_PROJECT_NAME="${CONTAINER_PREFIX}-${TASK_FULL_NAME}"

# Update metadata status to running
jq '.status.state = "running"' "$METADATA_FILE" > "$METADATA_FILE.tmp" && mv "$METADATA_FILE.tmp" "$METADATA_FILE"

# Build compose command with hardening overlay (supervisor always included, searxng optional)
COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.${HARDENING}.yml"
if [ "$INCLUDE_SEARXNG" = "true" ]; then
    COMPOSE_CMD="$COMPOSE_CMD --profile searxng"
fi

# Run agent with dedicated supervisor (background mode with auto-attach)
echo "Starting agent and supervisor in background..."
$COMPOSE_CMD up -d

# Wait for agent container to be running
echo "Waiting for agent container..."
for i in {1..30}; do
    if docker ps -q --filter "name=$AGENT_CONTAINER" | grep -q .; then
        break
    fi
    sleep 1
done

if ! docker ps -q --filter "name=$AGENT_CONTAINER" | grep -q .; then
    echo "ERROR: Agent container failed to start"
    $COMPOSE_CMD logs
    exit 1
fi

echo ""
echo "Containers running. Attaching to agent..."
echo "  Detach: Ctrl+P, Ctrl+Q (containers keep running)"
echo "  Re-attach: make attach W=$TASK_FULL_NAME   (or w= / WORKER=)"
echo "  Stop: make stop W=$TASK_FULL_NAME   (or w= / WORKER=)"
echo ""

# Attach to agent container (interactive)
docker attach "$AGENT_CONTAINER"
EXIT_CODE=$?

# Check if containers are still running (user detached vs exited)
if docker ps -q --filter "name=$AGENT_CONTAINER" | grep -q .; then
    echo ""
    echo "Detached. Containers still running."
    echo "  Re-attach: make attach W=$TASK_FULL_NAME   (or w= / WORKER=)"
    echo "  Stop: make stop W=$TASK_FULL_NAME   (or w= / WORKER=)"
    # Don't update metadata - task is still running
    exit 0
fi

# Agent exited - clean up supervisor too
echo "Agent exited. Stopping supervisor..."
docker stop "$SUPERVISOR_CONTAINER" 2>/dev/null || true

# Update metadata on exit
jq --arg stop_time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --argjson exit_code "$EXIT_CODE" \
   '.status.state = "stopped" | .status.stop_time = $stop_time | .status.exit_code = $exit_code' \
   "$METADATA_FILE" > "$METADATA_FILE.tmp" && mv "$METADATA_FILE.tmp" "$METADATA_FILE"

echo ""
echo "Task completed. Exit code: $EXIT_CODE"
echo "Metadata: $METADATA_FILE"
