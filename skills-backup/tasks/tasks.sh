#!/bin/bash
# Tasks skill - simple task tracking for work sessions
# Storage: ~/workspace/.tasks

set -e

TASKS_FILE="${HOME}/workspace/.tasks"

# Ensure tasks file exists
touch "$TASKS_FILE" 2>/dev/null || true

usage() {
    cat << 'EOF'
Usage: tasks.sh <command> [args]

Commands:
  add <task>       Add a new task
  list             Show all tasks
  done <number>    Mark task as completed
  working <number> Mark task as in-progress
  remove <number>  Remove a task
  clear            Clear all tasks
  status           Show summary

Examples:
  tasks.sh add "Create user model"
  tasks.sh list
  tasks.sh working 1
  tasks.sh done 1
  tasks.sh status
EOF
    exit 1
}

# Count tasks by status
count_tasks() {
    local total=$(grep -c "^" "$TASKS_FILE" 2>/dev/null || echo 0)
    local done=$(grep -c "^\[x\]" "$TASKS_FILE" 2>/dev/null || echo 0)
    local working=$(grep -c "^\[>\]" "$TASKS_FILE" 2>/dev/null || echo 0)
    local pending=$((total - done - working))
    echo "$done $total $working $pending"
}

cmd_add() {
    local task="$*"
    if [ -z "$task" ]; then
        echo "Error: Task description required"
        exit 1
    fi
    echo "[ ] $task" >> "$TASKS_FILE"
    echo "Added: $task"
    cmd_status
}

cmd_list() {
    if [ ! -s "$TASKS_FILE" ]; then
        echo "No tasks. Add some with: tasks.sh add \"task description\""
        return
    fi

    read -r done total working pending <<< "$(count_tasks)"
    echo "Tasks ($done of $total complete):"
    echo ""

    local num=1
    while IFS= read -r line; do
        echo "  $num. $line"
        ((num++))
    done < "$TASKS_FILE"
}

cmd_done() {
    local num="$1"
    if [ -z "$num" ]; then
        echo "Error: Task number required"
        exit 1
    fi

    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid task number"
        exit 1
    fi

    local total=$(wc -l < "$TASKS_FILE" | tr -d ' ')
    if [ "$num" -lt 1 ] || [ "$num" -gt "$total" ]; then
        echo "Error: Task $num not found (have $total tasks)"
        exit 1
    fi

    # Mark as done [x]
    sed -i.bak "${num}s/^\[.\]/[x]/" "$TASKS_FILE" && rm -f "${TASKS_FILE}.bak"

    local task=$(sed -n "${num}p" "$TASKS_FILE" | sed 's/^\[.\] //')
    echo "Completed: $task"
    cmd_status
}

cmd_working() {
    local num="$1"
    if [ -z "$num" ]; then
        echo "Error: Task number required"
        exit 1
    fi

    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid task number"
        exit 1
    fi

    local total=$(wc -l < "$TASKS_FILE" | tr -d ' ')
    if [ "$num" -lt 1 ] || [ "$num" -gt "$total" ]; then
        echo "Error: Task $num not found (have $total tasks)"
        exit 1
    fi

    # Mark as working [>]
    sed -i.bak "${num}s/^\[.\]/[>]/" "$TASKS_FILE" && rm -f "${TASKS_FILE}.bak"

    local task=$(sed -n "${num}p" "$TASKS_FILE" | sed 's/^\[.\] //')
    echo "Working on: $task"
}

cmd_remove() {
    local num="$1"
    if [ -z "$num" ]; then
        echo "Error: Task number required"
        exit 1
    fi

    local total=$(wc -l < "$TASKS_FILE" | tr -d ' ')
    if [ "$num" -lt 1 ] || [ "$num" -gt "$total" ]; then
        echo "Error: Task $num not found"
        exit 1
    fi

    local task=$(sed -n "${num}p" "$TASKS_FILE")
    sed -i.bak "${num}d" "$TASKS_FILE" && rm -f "${TASKS_FILE}.bak"
    echo "Removed: $task"
}

cmd_clear() {
    > "$TASKS_FILE"
    echo "All tasks cleared"
}

cmd_status() {
    read -r done total working pending <<< "$(count_tasks)"

    if [ "$total" -eq 0 ]; then
        echo "Status: No tasks"
        return
    fi

    local pct=0
    if [ "$total" -gt 0 ]; then
        pct=$((done * 100 / total))
    fi

    echo ""
    echo "========================================="
    echo "  TASK STATUS: $done of $total complete ($pct%)"
    if [ "$working" -gt 0 ]; then
        echo "  In progress: $working"
    fi
    if [ "$pending" -gt 0 ]; then
        echo "  Pending: $pending"
    fi
    echo "========================================="

    if [ "$done" -eq "$total" ] && [ "$total" -gt 0 ]; then
        echo "  ALL TASKS COMPLETE!"
    fi
}

# Main
case "${1:-}" in
    add)
        shift
        cmd_add "$@"
        ;;
    list)
        cmd_list
        ;;
    done)
        cmd_done "$2"
        ;;
    working)
        cmd_working "$2"
        ;;
    remove)
        cmd_remove "$2"
        ;;
    clear)
        cmd_clear
        ;;
    status)
        cmd_status
        ;;
    *)
        usage
        ;;
esac
