#!/bin/bash
# Tunnel Management Script for macOS Docker LAN Access
# Automatically creates socat tunnels to bridge containers to LAN devices

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load .env file if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if a host is a LAN device (not localhost or host.docker.internal)
is_lan_host() {
    local host="$1"

    # Skip if empty
    [ -z "$host" ] && return 1

    # Skip localhost variants
    [[ "$host" =~ ^(localhost|127\.|::1|host\.docker\.internal)$ ]] && return 1

    # Skip if it's already host.docker.internal
    [ "$host" = "host.docker.internal" ] && return 1

    # If it starts with 192.168., 10., 172.16-31., or ends with .local, it's LAN
    [[ "$host" =~ ^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.) ]] && return 0
    [[ "$host" =~ \.local$ ]] && return 0

    return 1
}

# Check if tunnel is already running for a given port
is_tunnel_running() {
    local port="$1"
    pgrep -f "socat.*TCP-LISTEN:${port}" > /dev/null 2>&1
}

# Get PID of tunnel on given port
get_tunnel_pid() {
    local port="$1"
    pgrep -f "socat.*TCP-LISTEN:${port}" 2>/dev/null | head -1
}

# Start a tunnel
start_tunnel() {
    local remote_host="$1"
    local remote_port="$2"
    local local_port="${3:-$remote_port}"  # Default to same port

    if [ -z "$remote_host" ] || [ -z "$remote_port" ]; then
        log_error "Usage: start_tunnel <remote_host> <remote_port> [local_port]"
        return 1
    fi

    # Check if tunnel already running
    if is_tunnel_running "$local_port"; then
        local pid=$(get_tunnel_pid "$local_port")
        log_warning "Tunnel already running on port $local_port (PID: $pid)"
        return 0
    fi

    # Verify remote host is reachable from Mac
    log_info "Testing connectivity to ${remote_host}:${remote_port}..."
    if ! timeout 3 bash -c "cat < /dev/null > /dev/tcp/${remote_host}/${remote_port}" 2>/dev/null; then
        log_error "Cannot reach ${remote_host}:${remote_port} from Mac host"
        log_error "Please ensure the service is running and accessible"
        return 1
    fi

    # Start tunnel
    log_info "Starting tunnel: localhost:${local_port} → ${remote_host}:${remote_port}"
    socat TCP-LISTEN:${local_port},fork,reuseaddr TCP:${remote_host}:${remote_port} &
    local pid=$!

    # Wait a moment and verify it started
    sleep 1
    if kill -0 $pid 2>/dev/null; then
        log_success "Tunnel started (PID: $pid)"
        echo "$pid" >> "$PROJECT_ROOT/.tunnel-pids"
        return 0
    else
        log_error "Failed to start tunnel"
        return 1
    fi
}

# Stop tunnel on given port
stop_tunnel() {
    local port="$1"

    if [ -z "$port" ]; then
        log_error "Usage: stop_tunnel <port>"
        return 1
    fi

    if ! is_tunnel_running "$port"; then
        log_warning "No tunnel running on port $port"
        return 0
    fi

    local pid=$(get_tunnel_pid "$port")
    log_info "Stopping tunnel on port $port (PID: $pid)"
    kill $pid 2>/dev/null || true
    sleep 1

    if ! is_tunnel_running "$port"; then
        log_success "Tunnel stopped"
        # Clean up from tracking file
        [ -f "$PROJECT_ROOT/.tunnel-pids" ] && sed -i.bak "/^${pid}$/d" "$PROJECT_ROOT/.tunnel-pids"
        return 0
    else
        log_error "Failed to stop tunnel"
        return 1
    fi
}

# Stop all tunnels
stop_all_tunnels() {
    local pids=$(pgrep -f "socat.*TCP-LISTEN" 2>/dev/null || true)

    if [ -z "$pids" ]; then
        log_info "No tunnels running"
        return 0
    fi

    log_info "Stopping all tunnels..."
    echo "$pids" | while read pid; do
        if [ -n "$pid" ]; then
            kill $pid 2>/dev/null || true
        fi
    done

    sleep 1
    rm -f "$PROJECT_ROOT/.tunnel-pids"
    log_success "All tunnels stopped"
}

# Show tunnel status
show_status() {
    echo
    echo "=== Tunnel Status ==="
    echo

    local tunnels=$(ps aux | grep "[s]ocat.*TCP-LISTEN" || true)

    if [ -z "$tunnels" ]; then
        log_info "No tunnels running"
    else
        echo "$tunnels" | while read line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local port=$(echo "$line" | grep -o "TCP-LISTEN:[0-9]*" | cut -d: -f2)
            local target=$(echo "$line" | grep -o "TCP:[^ ]*" | cut -d: -f2-)
            log_success "Port $port → $target (PID: $pid)"
        done
    fi
    echo
}

# Auto-detect and start tunnels based on .env
auto_tunnels() {
    log_info "Auto-detecting tunnel requirements from .env..."

    local tunnels_started=0

    # Check LLM_HOST
    if is_lan_host "$LLM_HOST"; then
        log_info "LLM_HOST ($LLM_HOST) is on LAN, tunnel required"
        if start_tunnel "$LLM_HOST" "${LLM_PORT:-11234}"; then
            tunnels_started=$((tunnels_started + 1))
        fi
    else
        log_info "LLM_HOST ($LLM_HOST) is local, no tunnel needed"
    fi

    # Check VISION_HOST if different from LLM_HOST
    if [ -n "$VISION_HOST" ] && [ "$VISION_HOST" != "$LLM_HOST" ]; then
        if is_lan_host "$VISION_HOST"; then
            log_info "VISION_HOST ($VISION_HOST) is on LAN, tunnel required"
            if start_tunnel "$VISION_HOST" "${VISION_PORT:-11234}"; then
                tunnels_started=$((tunnels_started + 1))
            fi
        else
            log_info "VISION_HOST ($VISION_HOST) is local, no tunnel needed"
        fi
    fi

    # Check SUPERVISOR_LLM_HOST if different from LLM_HOST
    if [ -n "$SUPERVISOR_LLM_HOST" ] && [ "$SUPERVISOR_LLM_HOST" != "$LLM_HOST" ]; then
        if is_lan_host "$SUPERVISOR_LLM_HOST"; then
            log_info "SUPERVISOR_LLM_HOST ($SUPERVISOR_LLM_HOST) is on LAN, tunnel required"
            if start_tunnel "$SUPERVISOR_LLM_HOST" "${SUPERVISOR_LLM_PORT:-11234}"; then
                tunnels_started=$((tunnels_started + 1))
            fi
        else
            log_info "SUPERVISOR_LLM_HOST ($SUPERVISOR_LLM_HOST) is local, no tunnel needed"
        fi
    fi

    if [ $tunnels_started -eq 0 ]; then
        log_info "No tunnels needed"
    else
        log_success "Started $tunnels_started tunnel(s)"
    fi

    show_status
}

# Test tunnel connectivity
test_tunnel() {
    local port="$1"

    if [ -z "$port" ]; then
        log_error "Usage: test_tunnel <port>"
        return 1
    fi

    if ! is_tunnel_running "$port"; then
        log_error "No tunnel running on port $port"
        return 1
    fi

    log_info "Testing tunnel on port $port..."

    # Test from Mac host
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/localhost/${port}" 2>/dev/null; then
        log_success "Tunnel accessible from Mac host on port $port"
    else
        log_error "Tunnel NOT accessible from Mac host on port $port"
        return 1
    fi

    # Test from a Docker container if docker is available
    if command -v docker &> /dev/null; then
        log_info "Testing from Docker container..."
        if docker run --rm alpine timeout 3 sh -c "cat < /dev/null > /dev/tcp/host.docker.internal/${port}" 2>/dev/null; then
            log_success "Tunnel accessible from Docker containers"
        else
            log_warning "Tunnel NOT accessible from Docker containers (host.docker.internal may not be configured)"
        fi
    fi

    return 0
}

# Main command handler
case "${1:-}" in
    start)
        if [ -n "$2" ] && [ -n "$3" ]; then
            # Manual tunnel: start_tunnel <host> <port> [local_port]
            start_tunnel "$2" "$3" "${4:-$3}"
        else
            # Auto-detect from .env
            auto_tunnels
        fi
        ;;
    stop)
        if [ -n "$2" ]; then
            stop_tunnel "$2"
        else
            stop_all_tunnels
        fi
        ;;
    status)
        show_status
        ;;
    test)
        if [ -n "$2" ]; then
            test_tunnel "$2"
        else
            log_error "Usage: $0 test <port>"
            exit 1
        fi
        ;;
    restart)
        stop_all_tunnels
        sleep 1
        auto_tunnels
        ;;
    *)
        echo "Usage: $0 {start|stop|status|test|restart}"
        echo
        echo "Commands:"
        echo "  start              - Auto-detect and start tunnels from .env"
        echo "  start <host> <port> [local_port] - Start specific tunnel"
        echo "  stop [port]        - Stop tunnel on port (or all tunnels)"
        echo "  status             - Show running tunnels"
        echo "  test <port>        - Test tunnel connectivity"
        echo "  restart            - Restart all tunnels"
        echo
        exit 1
        ;;
esac
