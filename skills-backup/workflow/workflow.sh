#!/bin/bash
# Workflow state management for autonomous task completion
# Tracks workflow state and checkpoints

set -e

WORKFLOW_FILE="${HOME}/workspace/.workflow_state"
TASKS_FILE="${HOME}/workspace/.tasks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << 'EOF'
Usage: workflow.sh <command> [args]

Commands:
  start <description>     Start workflow for a new task
  checkpoint <type>       Record a checkpoint (plan, tasks, test, vision, qa)
  status                  Show current workflow state
  validate                Check if required checkpoints exist
  reset                   Clear workflow state

Examples:
  workflow.sh start "Build a todo web app"
  workflow.sh checkpoint plan
  workflow.sh checkpoint tasks
  workflow.sh checkpoint test
  workflow.sh checkpoint vision
  workflow.sh status
  workflow.sh validate
  workflow.sh reset
EOF
    exit 1
}

# Initialize workflow state file
init_state() {
    local description="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$WORKFLOW_FILE" << EOF
{
  "state": "PLANNING",
  "description": "$description",
  "started_at": "$timestamp",
  "checkpoints": {
    "plan": false,
    "tasks": false,
    "test": false,
    "vision": false,
    "qa": false
  },
  "history": [
    {"state": "PLANNING", "at": "$timestamp"}
  ]
}
EOF
}

# Read current state
get_state() {
    if [ -f "$WORKFLOW_FILE" ]; then
        jq -r '.state' "$WORKFLOW_FILE" 2>/dev/null || echo "UNKNOWN"
    else
        echo "IDLE"
    fi
}

# Get checkpoint status
get_checkpoint() {
    local checkpoint="$1"
    if [ -f "$WORKFLOW_FILE" ]; then
        jq -r ".checkpoints.$checkpoint // false" "$WORKFLOW_FILE" 2>/dev/null
    else
        echo "false"
    fi
}

# Set checkpoint
set_checkpoint() {
    local checkpoint="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ ! -f "$WORKFLOW_FILE" ]; then
        echo -e "${RED}ERROR: No active workflow. Run 'workflow.sh start' first.${NC}"
        exit 1
    fi

    # Update checkpoint
    local tmp=$(mktemp)
    jq ".checkpoints.$checkpoint = true" "$WORKFLOW_FILE" > "$tmp" && mv "$tmp" "$WORKFLOW_FILE"

    echo -e "${GREEN}✓ Checkpoint recorded: $checkpoint${NC}"
}

# Update state
set_state() {
    local new_state="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ ! -f "$WORKFLOW_FILE" ]; then
        echo -e "${RED}ERROR: No active workflow.${NC}"
        exit 1
    fi

    local tmp=$(mktemp)
    jq ".state = \"$new_state\" | .history += [{\"state\": \"$new_state\", \"at\": \"$timestamp\"}]" "$WORKFLOW_FILE" > "$tmp" && mv "$tmp" "$WORKFLOW_FILE"
}

# Command: start
cmd_start() {
    local description="$*"

    if [ -z "$description" ]; then
        echo -e "${RED}ERROR: Task description required${NC}"
        echo "Usage: workflow.sh start \"task description\""
        exit 1
    fi

    # Check if workflow already exists
    if [ -f "$WORKFLOW_FILE" ]; then
        local current_state=$(get_state)
        if [ "$current_state" != "COMPLETE" ]; then
            echo -e "${YELLOW}WARNING: Workflow already in progress (state: $current_state)${NC}"
            echo "Run 'workflow.sh reset' to start over, or 'workflow.sh status' to see current state."
            return
        fi
    fi

    init_state "$description"

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  WORKFLOW STARTED${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  Task: ${BLUE}$description${NC}"
    echo ""
    echo "  Next steps:"
    echo "  1. PLAN - Think through what to build"
    echo "  2. TASKS - Add tasks with: /tasks add \"...\""
    echo "  3. WORK - Implement each task"
    echo "  4. TEST - Run tests, /vision verify for UI"
    echo "  5. QA - Call qa-agent to verify coverage"
    echo "  6. SUPERVISOR - Call /supervisor to evaluate"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
}

# Command: checkpoint
cmd_checkpoint() {
    local checkpoint_type="$1"

    case "$checkpoint_type" in
        plan|tasks|test|vision|qa)
            set_checkpoint "$checkpoint_type"

            # Auto-transition states based on checkpoints
            case "$checkpoint_type" in
                tasks)
                    set_state "TASKED"
                    ;;
                test)
                    set_state "TESTING"
                    ;;
                qa)
                    set_state "QA_CHECK"
                    ;;
            esac
            ;;
        *)
            echo -e "${RED}ERROR: Unknown checkpoint type: $checkpoint_type${NC}"
            echo "Valid types: plan, tasks, test, vision, qa"
            exit 1
            ;;
    esac
}

# Command: status
cmd_status() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  WORKFLOW STATUS"
    echo "═══════════════════════════════════════════════════════════"

    if [ ! -f "$WORKFLOW_FILE" ]; then
        echo ""
        echo -e "  State: ${YELLOW}IDLE${NC} (no active workflow)"
        echo ""
        echo "  To start a workflow:"
        echo "    workflow.sh start \"task description\""
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        return
    fi

    local state=$(get_state)
    local description=$(jq -r '.description' "$WORKFLOW_FILE")
    local started=$(jq -r '.started_at' "$WORKFLOW_FILE")

    echo ""
    echo -e "  Task: ${BLUE}$description${NC}"
    echo -e "  Started: $started"
    echo ""

    # State with color
    case "$state" in
        PLANNING)
            echo -e "  State: ${YELLOW}$state${NC}"
            ;;
        TASKED|WORKING)
            echo -e "  State: ${BLUE}$state${NC}"
            ;;
        TESTING|QA_CHECK)
            echo -e "  State: ${YELLOW}$state${NC}"
            ;;
        COMPLETE)
            echo -e "  State: ${GREEN}$state${NC}"
            ;;
        *)
            echo -e "  State: $state"
            ;;
    esac

    echo ""
    echo "  Checkpoints:"

    local plan=$(get_checkpoint "plan")
    local tasks=$(get_checkpoint "tasks")
    local test=$(get_checkpoint "test")
    local vision=$(get_checkpoint "vision")
    local qa=$(get_checkpoint "qa")

    [ "$plan" = "true" ] && echo -e "    ${GREEN}[✓]${NC} Plan created" || echo -e "    ${RED}[ ]${NC} Plan created"
    [ "$tasks" = "true" ] && echo -e "    ${GREEN}[✓]${NC} Tasks added" || echo -e "    ${RED}[ ]${NC} Tasks added"
    [ "$test" = "true" ] && echo -e "    ${GREEN}[✓]${NC} Tests run" || echo -e "    ${RED}[ ]${NC} Tests run"
    [ "$vision" = "true" ] && echo -e "    ${GREEN}[✓]${NC} Vision verified" || echo -e "    ${YELLOW}[ ]${NC} Vision verified (if UI)"
    [ "$qa" = "true" ] && echo -e "    ${GREEN}[✓]${NC} QA passed" || echo -e "    ${RED}[ ]${NC} QA passed"

    echo ""

    # Show task status if tasks file exists
    if [ -f "$TASKS_FILE" ] && [ -s "$TASKS_FILE" ]; then
        local total=$(wc -l < "$TASKS_FILE" | tr -d ' ')
        local done=$(grep -c "^\[x\]" "$TASKS_FILE" 2>/dev/null || echo "0")
        echo "  Tasks: $done of $total complete"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

# Command: validate
cmd_validate() {
    if [ ! -f "$WORKFLOW_FILE" ]; then
        echo -e "${RED}ERROR: No active workflow${NC}"
        exit 1
    fi

    local missing=()

    # Required checkpoints
    [ "$(get_checkpoint 'plan')" != "true" ] && missing+=("plan")
    [ "$(get_checkpoint 'tasks')" != "true" ] && missing+=("tasks")
    [ "$(get_checkpoint 'test')" != "true" ] && missing+=("test")
    [ "$(get_checkpoint 'qa')" != "true" ] && missing+=("qa")

    # Check if all tasks complete
    if [ -f "$TASKS_FILE" ] && [ -s "$TASKS_FILE" ]; then
        local total=$(wc -l < "$TASKS_FILE" | tr -d ' ')
        local done=$(grep -c "^\[x\]" "$TASKS_FILE" 2>/dev/null || echo "0")
        if [ "$done" -lt "$total" ]; then
            echo -e "${RED}ERROR: Not all tasks complete ($done of $total)${NC}"
            exit 1
        fi
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}ERROR: Missing checkpoints: ${missing[*]}${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ All required checkpoints present${NC}"
}

# Command: reset
cmd_reset() {
    if [ -f "$WORKFLOW_FILE" ]; then
        rm "$WORKFLOW_FILE"
        echo -e "${YELLOW}Workflow state cleared${NC}"
    else
        echo "No workflow to reset"
    fi
}

# Main
case "${1:-}" in
    start)
        shift
        cmd_start "$@"
        ;;
    checkpoint)
        cmd_checkpoint "$2"
        ;;
    status)
        cmd_status
        ;;
    validate)
        cmd_validate
        ;;
    reset)
        cmd_reset
        ;;
    *)
        usage
        ;;
esac
