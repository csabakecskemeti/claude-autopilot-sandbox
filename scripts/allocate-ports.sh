#!/bin/bash
# Port allocation script with collision detection
# Usage: ./allocate-ports.sh <num_ports> [workspace_base]
# Output: Space-separated list of available ports

set -e

NUM_PORTS="${1:-4}"
WORKSPACE_BASE="${2:-./workspaces}"
MIN_PORT=30000
MAX_PORT=60000

# Check if a port is available
port_available() {
    local port=$1

    # Check 1: Not in use by system (lsof)
    if lsof -i ":$port" >/dev/null 2>&1; then
        return 1
    fi

    # Check 2: Not in use by Docker
    if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":$port->"; then
        return 1
    fi

    # Check 3: Not claimed in any task metadata
    if [ -d "$WORKSPACE_BASE" ]; then
        if grep -r "\"$port\"" "$WORKSPACE_BASE"/*/metadata.json 2>/dev/null | grep -q "ports"; then
            return 1
        fi
    fi

    return 0
}

# Find N available ports
find_ports() {
    local count=$1
    local found=0
    local ports=()
    local candidate=$MIN_PORT

    while [ $found -lt $count ] && [ $candidate -le $MAX_PORT ]; do
        if port_available $candidate; then
            ports+=($candidate)
            found=$((found + 1))
        fi
        candidate=$((candidate + 1))
    done

    if [ $found -lt $count ]; then
        echo "ERROR: Could not find $count available ports in range $MIN_PORT-$MAX_PORT" >&2
        exit 1
    fi

    echo "${ports[@]}"
}

# Main
find_ports $NUM_PORTS
