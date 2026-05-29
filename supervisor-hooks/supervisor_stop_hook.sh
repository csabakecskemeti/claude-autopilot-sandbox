#!/bin/bash
###
# Supervisor Stop Hook - Langfuse Tracing
# Sends supervisor's evaluation traces to a separate Langfuse project.
# This hook NEVER blocks - supervisor always exits after evaluation.
###

set -e

# Config
LOG_FILE="$HOME/.claude/state/supervisor_hook.log"
DEBUG="${LANGFUSE_DEBUG:-false}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}

log "INFO" "=== Supervisor stop hook invoked ==="

# Read stdin
STDIN_CONTENT=$(cat)
log "INFO" "Received stdin (${#STDIN_CONTENT} bytes)"

# Check if tracing is enabled for supervisor
TRACE_ENABLED="${SUPERVISOR_TRACE_TO_LANGFUSE:-false}"
if [ "$TRACE_ENABLED" != "true" ]; then
    log "INFO" "Supervisor tracing disabled, exiting"
    exit 0
fi

# Extract session info
SESSION_ID=$(echo "$STDIN_CONTENT" | jq -r '.session_id // ""')
TRANSCRIPT_PATH=$(echo "$STDIN_CONTENT" | jq -r '.transcript_path // ""' | sed "s|^~|$HOME|")

log "INFO" "Session: $SESSION_ID"
log "INFO" "Transcript: $TRANSCRIPT_PATH"

# Langfuse config for supervisor (separate project)
PUBLIC_KEY="${SUPERVISOR_LANGFUSE_PUBLIC_KEY:-}"
SECRET_KEY="${SUPERVISOR_LANGFUSE_SECRET_KEY:-}"
PROJECT="${SUPERVISOR_LANGFUSE_PROJECT:-claude-supervisor}"
API_BASE="${LANGFUSE_HOST:-http://localhost:3000}"

if [ -z "$PUBLIC_KEY" ] || [ -z "$SECRET_KEY" ]; then
    log "WARN" "Supervisor Langfuse keys not set, skipping tracing"
    exit 0
fi

# Create Basic auth header
AUTH_HEADER=$(echo -n "$PUBLIC_KEY:$SECRET_KEY" | base64 | tr -d '\n')

# Generate trace ID
TRACE_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Read transcript to get evaluation details
if [ -f "$TRANSCRIPT_PATH" ]; then
    # Extract last assistant message (the evaluation result)
    EVALUATION=$(tac "$TRANSCRIPT_PATH" 2>/dev/null | \
        jq -s 'map(select(.role == "assistant" or (.message.role == "assistant"))) | .[0]' 2>/dev/null | \
        jq -r 'if .message then .message.content else .content end' 2>/dev/null | \
        head -c 5000)
else
    EVALUATION="No transcript found"
fi

# Create trace event
EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')

# Build payload
PAYLOAD=$(jq -n \
    --arg event_id "$EVENT_ID" \
    --arg trace_id "$TRACE_ID" \
    --arg session_id "$SESSION_ID" \
    --arg project "$PROJECT" \
    --arg output "$EVALUATION" \
    --arg time "$NOW" \
    '{
        batch: [
            {
                id: $event_id,
                type: "trace-create",
                timestamp: $time,
                body: {
                    id: $trace_id,
                    name: "Supervisor Evaluation",
                    sessionId: $session_id,
                    output: $output,
                    metadata: {
                        source: "claude-supervisor",
                        project: $project
                    }
                }
            }
        ]
    }')

# Send to Langfuse
log "INFO" "Sending trace to Langfuse project: $PROJECT"

RESPONSE=$(curl -s --max-time 30 -w "\n%{http_code}" -X POST \
    -H "Authorization: Basic $AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$API_BASE/api/public/ingestion" 2>&1)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    log "INFO" "Trace sent successfully (HTTP $HTTP_CODE)"
else
    log "ERROR" "Failed to send trace: HTTP $HTTP_CODE"
    log "ERROR" "Response: $BODY"
fi

# Always allow supervisor to exit
log "INFO" "Supervisor stop hook complete"
exit 0
