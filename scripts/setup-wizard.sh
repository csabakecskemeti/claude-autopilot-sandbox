#!/bin/bash
# Interactive setup wizard to create/edit .env file

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

echo "========================================"
echo "  Claude Autopilot Sandbox Setup"
echo "========================================"
echo ""

# Load existing .env if present
if [ -f "$ENV_FILE" ]; then
    echo "Loading existing .env file..."
    set -a
    source "$ENV_FILE"
    set +a
    echo "Current values will be shown as defaults."
    echo ""
fi

echo "Press Enter to accept defaults shown in [brackets]."
echo "Leave empty and press Enter to keep current value or use default."
echo ""

# Helper function to prompt with default
prompt() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local current_value="${!var_name}"

    # Use current value if set, otherwise use default
    local show_default="${current_value:-$default_value}"

    if [ -n "$show_default" ]; then
        read -p "$prompt_text [$show_default]: " input
        eval "$var_name=\"${input:-$show_default}\""
    else
        read -p "$prompt_text: " input
        eval "$var_name=\"$input\""
    fi
}

# Helper for yes/no prompts
prompt_yn() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local current_value="${!var_name}"

    local show_default="${current_value:-$default_value}"
    local yn_hint="y/N"
    if [ "$show_default" = "true" ]; then
        yn_hint="Y/n"
    fi

    read -p "$prompt_text [$yn_hint]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        eval "$var_name=true"
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
        eval "$var_name=false"
    else
        eval "$var_name=\"$show_default\""
    fi
}

# ============================================================================
# LLM Backend (Required)
# ============================================================================

echo "=== LLM Backend Configuration ==="
echo ""

prompt LLM_HOST "LLM Host (IP or hostname)" ""
if [ -z "$LLM_HOST" ]; then
    echo "Error: LLM_HOST is required"
    exit 1
fi

prompt LLM_PORT "LLM Port" "11234"
prompt LLM_AUTH_TOKEN "LLM Auth Token" "lmstudio"

prompt LLM_MODEL "LLM Model name" ""
if [ -z "$LLM_MODEL" ]; then
    echo "Error: LLM_MODEL is required"
    exit 1
fi

echo ""

# ============================================================================
# Vision Model
# ============================================================================

echo "=== Vision Model ==="
echo ""

prompt VISION_MODEL "Vision Model" "qwen/qwen3-vl-4b"

prompt_yn USE_DIFFERENT_VISION_HOST "Use different host for vision model?" "false"
if [ "$USE_DIFFERENT_VISION_HOST" = "true" ]; then
    prompt VISION_HOST "Vision Host" "$LLM_HOST"
    prompt VISION_PORT "Vision Port" "$LLM_PORT"
else
    VISION_HOST=""
    VISION_PORT=""
fi

echo ""

# ============================================================================
# Resource Limits
# ============================================================================

echo "=== Resource Limits ==="
echo ""

prompt MEMORY_LIMIT "Memory Limit" "16G"
prompt MEMORY_RESERVATION "Memory Reservation" "2G"

echo ""

# ============================================================================
# Workspace
# ============================================================================

echo "=== Workspace Configuration ==="
echo ""

prompt WORKSPACE_NAME "Default workspace name" "default"
prompt WORKSPACE_BASE "Workspace base path (empty for ./workspaces)" ""

echo ""

# ============================================================================
# Agent Langfuse Tracing
# ============================================================================

echo "=== Agent Langfuse Tracing ==="
echo ""

prompt_yn TRACE_TO_LANGFUSE "Enable Langfuse tracing for agent?" "false"

if [ "$TRACE_TO_LANGFUSE" = "true" ]; then
    prompt LANGFUSE_PUBLIC_KEY "Langfuse Public Key" ""
    prompt LANGFUSE_SECRET_KEY "Langfuse Secret Key" ""
    prompt LANGFUSE_HOST "Langfuse Host" "http://host.docker.internal:3000"
    prompt LANGFUSE_PROJECT "Langfuse Project (agent)" "claude-code"
    prompt_yn LANGFUSE_DEBUG "Enable Langfuse debug logging?" "false"
fi

echo ""

# ============================================================================
# Supervisor Configuration
# ============================================================================

echo "=== Supervisor Configuration ==="
echo ""

prompt SUPERVISOR_MAX_LOOPS "Max evaluation loops" "20"
prompt SUPERVISOR_TIMEOUT "Supervisor timeout (seconds)" "3600"
prompt STOP_HOOK_EXTRA_SEC "Stop hook extra time for Langfuse (seconds)" "1200"
prompt_yn SUPERVISOR_AUTONOMY_APPEND "Append autonomy nudge to feedback?" "true"

echo ""

# ============================================================================
# Supervisor LLM Override
# ============================================================================

echo "=== Supervisor LLM Override ==="
echo ""

prompt_yn USE_DIFFERENT_SUPERVISOR_LLM "Use different LLM host for supervisor?" "false"
if [ "$USE_DIFFERENT_SUPERVISOR_LLM" = "true" ]; then
    prompt SUPERVISOR_LLM_HOST "Supervisor LLM Host" "$LLM_HOST"
    prompt SUPERVISOR_LLM_PORT "Supervisor LLM Port" "$LLM_PORT"
else
    SUPERVISOR_LLM_HOST=""
    SUPERVISOR_LLM_PORT=""
fi

echo ""

# ============================================================================
# Supervisor Langfuse Tracing
# ============================================================================

echo "=== Supervisor Langfuse Tracing ==="
echo ""

prompt_yn SUPERVISOR_TRACE_TO_LANGFUSE "Enable Langfuse tracing for supervisor?" "false"

if [ "$SUPERVISOR_TRACE_TO_LANGFUSE" = "true" ]; then
    prompt SUPERVISOR_LANGFUSE_PUBLIC_KEY "Supervisor Langfuse Public Key" "$LANGFUSE_PUBLIC_KEY"
    prompt SUPERVISOR_LANGFUSE_SECRET_KEY "Supervisor Langfuse Secret Key" "$LANGFUSE_SECRET_KEY"
    prompt SUPERVISOR_LANGFUSE_PROJECT "Supervisor Langfuse Project" "claude-supervisor"
fi

echo ""

# ============================================================================
# Write .env file
# ============================================================================

echo "Writing .env file..."

cat > "$ENV_FILE" << EOF
# Generated by setup wizard on $(date)

# LLM Backend
LLM_HOST=$LLM_HOST
LLM_PORT=$LLM_PORT
LLM_AUTH_TOKEN=$LLM_AUTH_TOKEN
LLM_MODEL=$LLM_MODEL

# Vision Model
VISION_MODEL=$VISION_MODEL
EOF

if [ -n "$VISION_HOST" ]; then
cat >> "$ENV_FILE" << EOF
VISION_HOST=$VISION_HOST
VISION_PORT=$VISION_PORT
EOF
fi

cat >> "$ENV_FILE" << EOF

# Resource Limits
MEMORY_LIMIT=$MEMORY_LIMIT
MEMORY_RESERVATION=$MEMORY_RESERVATION

# Workspace
WORKSPACE_NAME=$WORKSPACE_NAME
EOF

if [ -n "$WORKSPACE_BASE" ]; then
cat >> "$ENV_FILE" << EOF
WORKSPACE_BASE=$WORKSPACE_BASE
EOF
fi

cat >> "$ENV_FILE" << EOF

# Supervisor Configuration
SUPERVISOR_MAX_LOOPS=$SUPERVISOR_MAX_LOOPS
SUPERVISOR_TIMEOUT=$SUPERVISOR_TIMEOUT
STOP_HOOK_EXTRA_SEC=$STOP_HOOK_EXTRA_SEC
SUPERVISOR_AUTONOMY_APPEND=$SUPERVISOR_AUTONOMY_APPEND
EOF

if [ -n "$SUPERVISOR_LLM_HOST" ]; then
cat >> "$ENV_FILE" << EOF

# Supervisor LLM Override
SUPERVISOR_LLM_HOST=$SUPERVISOR_LLM_HOST
SUPERVISOR_LLM_PORT=$SUPERVISOR_LLM_PORT
EOF
fi

if [ "$TRACE_TO_LANGFUSE" = "true" ]; then
cat >> "$ENV_FILE" << EOF

# Agent Langfuse Tracing
TRACE_TO_LANGFUSE=$TRACE_TO_LANGFUSE
LANGFUSE_PUBLIC_KEY=$LANGFUSE_PUBLIC_KEY
LANGFUSE_SECRET_KEY=$LANGFUSE_SECRET_KEY
LANGFUSE_HOST=$LANGFUSE_HOST
LANGFUSE_PROJECT=$LANGFUSE_PROJECT
LANGFUSE_DEBUG=$LANGFUSE_DEBUG
EOF
fi

if [ "$SUPERVISOR_TRACE_TO_LANGFUSE" = "true" ]; then
cat >> "$ENV_FILE" << EOF

# Supervisor Langfuse Tracing
SUPERVISOR_TRACE_TO_LANGFUSE=$SUPERVISOR_TRACE_TO_LANGFUSE
SUPERVISOR_LANGFUSE_PUBLIC_KEY=$SUPERVISOR_LANGFUSE_PUBLIC_KEY
SUPERVISOR_LANGFUSE_SECRET_KEY=$SUPERVISOR_LANGFUSE_SECRET_KEY
SUPERVISOR_LANGFUSE_PROJECT=$SUPERVISOR_LANGFUSE_PROJECT
EOF
fi

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Configuration saved to .env"
echo ""
echo "Next steps:"
echo "  1. Review config:     make env"
echo "  2. Test connection:   make test"
echo "  3. Build images:      make build"
echo "  4. Start an agent:    make run W=myproject T=\"your task\""
echo ""
