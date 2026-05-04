# Task Isolation & Folder Structure Refactor Plan

**Created:** 2026-05-02
**Status:** Implemented ✅
**Completed:** 2026-05-03

## Goals

1. **Supervisor per agent** - Each worker gets dedicated supervisor (no cross-contamination)
2. **Unified task folder** - All task artifacts in one parent directory
3. **Dynamic port management** - Automatic, collision-free port allocation
4. **Task metadata** - Full visibility into task configuration and status
5. **Supervisor output visibility** - Mount supervisor workspace to host

## Current State (Before)

```
$WORKSPACE_BASE/
├── kaggle_a5/              # Worker workspace
├── kaggle_a5-task/         # Task storage (separate folder)
├── kaggle_a5-supervisor/   # Supervisor workspace (separate folder)
├── todo_app/               # Another worker
├── todo_app-task/
└── todo_app-supervisor/
```

**Problems:**
- Folders scattered at same level
- No metadata about task configuration
- Shared supervisor can see all workspaces
- Manual port management
- Hard to know which folders belong together

## Target State (After)

```
$WORKSPACE_BASE/
├── kaggle_a5_20260502_223000/          # Task parent folder (with timestamp)
│   ├── worker/                          # Agent workspace
│   ├── task/                            # Immutable task storage
│   ├── supervisor/                      # Supervisor workspace (host-visible)
│   └── metadata.json                    # Task descriptor
│
└── todo_app_20260502_230000/
    ├── worker/
    ├── task/
    ├── supervisor/
    └── metadata.json
```

## Implementation Phases

### Phase 1: Port Management

**Approach:** Pool-based allocation with collision detection

```bash
# Port allocation logic (pseudo-code)
BASE_PORTS=(3000 5000 8000 8080)  # Container internal ports
MIN_EXTERNAL=30000
MAX_EXTERNAL=60000

allocate_ports() {
    # For each base port, find available external port
    for base in BASE_PORTS; do
        for candidate in $(seq $MIN_EXTERNAL $MAX_EXTERNAL); do
            if port_available $candidate; then
                assign $base -> $candidate
                break
            fi
        done
    done
}

port_available() {
    # Check 1: Not in use by system
    ! lsof -i :$port
    # Check 2: Not claimed by other task metadata
    ! grep -r "\"$port\"" $WORKSPACE_BASE/*/metadata.json
}
```

**Files to modify:**
- `run.sh` - Add port allocation logic
- New: `scripts/allocate-ports.sh` - Reusable port allocation

### Phase 2: Folder Structure Refactor

**Changes to `run.sh`:**

```bash
# Old
WORKSPACE_PATH="$WORKSPACE_BASE/$WORKSPACE_NAME"
SUPERVISOR_WORKSPACES="$WORKSPACE_BASE/${WORKSPACE_NAME}-supervisor"
TASK_STORAGE="$WORKSPACE_BASE/${WORKSPACE_NAME}-task"

# New
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TASK_DIR="$WORKSPACE_BASE/${WORKSPACE_NAME}_${TIMESTAMP}"
WORKSPACE_PATH="$TASK_DIR/worker"
SUPERVISOR_WORKSPACES="$TASK_DIR/supervisor"
TASK_STORAGE="$TASK_DIR/task"
METADATA_FILE="$TASK_DIR/metadata.json"
```

**Files to modify:**
- `run.sh` - New folder structure
- `docker-compose.yml` - Update volume mounts

### Phase 3: Embedded Supervisor (Per-Agent)

**Changes to `docker-compose.yml`:**

Remove shared supervisor, use embedded profile:

```yaml
services:
  agent:
    # ... existing config ...

  supervisor:
    profiles: ["supervisor"]  # Always included with agent
    build:
      context: ./supervisor
    volumes:
      - ${WORKSPACE_PATH}:/workspace:ro      # Agent's workspace
      - ${TASK_STORAGE}:/task:ro             # Task storage
      - ${SUPERVISOR_WORKSPACES}:/supervisor # Supervisor's workspace (rw)
    environment:
      - WORKSPACE=/workspace
      - TASK_STORAGE=/task
      - SUPERVISOR_WORKSPACES=/supervisor
```

**Files to modify:**
- `docker-compose.yml` - Embedded supervisor
- `run.sh` - Always start supervisor with agent
- Remove: `supervisor/docker-compose.yml` (or keep for standalone testing)

### Phase 4: Metadata File

**Structure:**

```json
{
  "version": "1.0",
  "task": {
    "name": "kaggle_a5",
    "full_name": "kaggle_a5_20260502_223000",
    "created_at": "2026-05-02T22:30:00Z",
    "original_task": "Solve Kaggle competition..."
  },
  "env": {
    "file": ".env-dgx2",
    "llm_host": "spark-7ceb.local",
    "llm_port": 11234,
    "llm_model": "qwen/qwen3.6-35b-a3b",
    "vision_model": "qwen/qwen3-vl-4b"
  },
  "containers": {
    "agent": {
      "name": "claude-agent-kaggle_a5-20260502",
      "image": "claude-agent:latest",
      "image_sha": "sha256:abc123..."
    },
    "supervisor": {
      "name": "claude-supervisor-kaggle_a5-20260502",
      "image": "claude-supervisor:latest"
    }
  },
  "ports": {
    "agent": {
      "3000": 31234,
      "5000": 31235,
      "8000": 31236
    },
    "supervisor": {
      "8080": 31237
    }
  },
  "paths": {
    "worker": "/path/to/task_dir/worker",
    "task": "/path/to/task_dir/task",
    "supervisor": "/path/to/task_dir/supervisor"
  },
  "status": {
    "state": "running",
    "start_time": "2026-05-02T22:30:05Z",
    "stop_time": null,
    "exit_code": null
  },
  "supervisor_results": {
    "total_evaluations": 5,
    "last_status": "not_complete",
    "last_evaluation": "2026-05-02T23:15:00Z"
  }
}
```

**Files to create/modify:**
- `run.sh` - Generate metadata.json at start
- `scripts/update-metadata.sh` - Update metadata (status, stop time)
- Stop hook - Update metadata on completion

### Phase 5: Makefile Updates

**New/modified targets:**

```makefile
# List all tasks with status
tasks:
    @echo "=== Tasks ==="
    @for meta in $(WORKSPACE_BASE)/*/metadata.json; do \
        jq -r '"\(.task.full_name): \(.status.state) - \(.env.llm_model)"' $$meta; \
    done

# Show task details
worker-info:
    @cat $(WORKSPACE_BASE)/$(T)/metadata.json | jq .

# Clean specific task
worker-clean:
    @# Stop containers, update metadata, optionally remove folder

# Clean all stopped tasks
workers-clean:
    @# Find tasks with status=stopped, remove folders
```

### Phase 6: Cleanup & Migration

**Cleanup logic:**

```bash
task_cleanup() {
    TASK_DIR=$1

    # Stop containers
    docker stop $(jq -r '.containers.agent.name' $TASK_DIR/metadata.json)
    docker stop $(jq -r '.containers.supervisor.name' $TASK_DIR/metadata.json)

    # Update metadata
    jq '.status.state = "stopped" | .status.stop_time = now' $TASK_DIR/metadata.json

    # Optionally remove folder
    if [ "$REMOVE" = "true" ]; then
        rm -rf $TASK_DIR
    fi
}
```

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `run.sh` | Modify | New folder structure, port allocation, metadata generation |
| `docker-compose.yml` | Modify | Embedded supervisor, updated volume paths |
| `scripts/allocate-ports.sh` | Create | Port allocation with collision detection |
| `scripts/update-metadata.sh` | Create | Update task metadata |
| `Makefile` | Modify | Targets: workers, worker-info, worker-clean |
| `supervisor/docker-compose.yml` | Keep | For standalone testing only |
| `hooks-backup/langfuse_stop_hook.sh` | Modify | Update metadata on stop |

## Backwards Compatibility

- Old folder structure will still exist but won't be managed
- New `make worker` creates new structure
- Add migration script? (Optional - can just leave old folders)

## Questions Resolved

| Question | Decision |
|----------|----------|
| Naming convention | `{name}_{timestamp}` (e.g., `kaggle_a5_20260502_223000`) |
| Port range | 30000-60000, with availability checking |
| Cleanup | Yes, `make worker-clean W=id` and `make workers-clean` |
| Multiple runs | New folder each time (timestamp ensures uniqueness) |

## Testing Plan

1. Create new worker run with `make worker W=test_task TASK="Test task"`
2. Verify folder structure created correctly
3. Verify metadata.json populated
4. Verify supervisor is per-agent (not shared)
5. Verify ports allocated without collision
6. Run second task in parallel, verify no port collision
7. Test cleanup with `make worker-clean W=<id>`

## Rollout

1. Implement on `feature/task-isolation` branch
2. Test with multiple parallel agents
3. Merge to `feature/standalone-services`
4. Eventually merge to `main`
