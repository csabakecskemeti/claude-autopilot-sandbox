#!/bin/bash
# Watchdog script for Claude Code autonomous operation
# Monitors session activity and nudges if stuck

INTERVAL_MINUTES=${1:-30}  # Check every N minutes (default: 30)
CONTAINER_NAME="claude-local-llm"

echo "🐕 Watchdog started - checking every ${INTERVAL_MINUTES} minutes"
echo "   Press Ctrl+C to stop"

while true; do
    sleep $((INTERVAL_MINUTES * 60))

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
        echo "$(date): Container not running, watchdog exiting"
        exit 0
    fi

    echo ""
    echo "$(date): 🔍 Watchdog check - sending nudge to container..."

    # Send a nudge message to the container's stdin
    # This assumes the container is running interactively
    docker exec -i "$CONTAINER_NAME" bash -c '
        echo ""
        echo "---"
        echo "[WATCHDOG] Periodic check - Are all todos complete?"
        echo "[WATCHDOG] If not, please continue working on remaining tasks."
        echo "[WATCHDOG] Run /supervisor to verify progress."
        echo "---"
    ' 2>/dev/null || echo "$(date): Could not send nudge (container may not be interactive)"

done
