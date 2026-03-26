#!/bin/bash
###
# Claude Code Stop Hook - Langfuse Tracing Integration
# Sends Claude Code traces to Langfuse after each response.
# Adapted from LangSmith hook for self-hosted Langfuse.
###

# CRITICAL: Disable bash history expansion to handle ! characters in JSON
set +H

# Don't use set -e (exit on error) - handle errors gracefully instead
# set -e  # DISABLED - causes crashes without cleanup

# Config (needed early for logging)
LOG_FILE="$HOME/.claude/state/hook.log"
DEBUG="$(echo "$LANGFUSE_DEBUG" | tr '[:upper:]' '[:lower:]')"

# Ensure log directory exists FIRST
mkdir -p "$(dirname "$LOG_FILE")"

# Cleanup function for graceful exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "ERROR" "Hook exited with code $exit_code"
    fi
    # Kill any background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
}
trap cleanup EXIT

# Logging functions
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" >> "$LOG_FILE"
}

debug() {
    if [ "$DEBUG" = "true" ]; then
        log "DEBUG" "$@"
    fi
}

# ALWAYS log hook invocation (even if debug is off) - this helps diagnose trigger issues
log "INFO" "=== Stop hook invoked ==="
log "INFO" "TRACE_TO_LANGFUSE=$TRACE_TO_LANGFUSE"
log "INFO" "LANGFUSE_DEBUG=$LANGFUSE_DEBUG"
log "INFO" "PWD=$(pwd)"
log "INFO" "HOME=$HOME"

# Save stdin to variable AND log it
STDIN_CONTENT=$(cat)
log "INFO" "Received stdin (${#STDIN_CONTENT} bytes): $(echo "$STDIN_CONTENT" | head -c 500)"

# Exit early if tracing disabled
if [ "$(echo "$TRACE_TO_LANGFUSE" | tr '[:upper:]' '[:lower:]')" != "true" ]; then
    debug "Tracing disabled, exiting early"
    exit 0
fi

# Required commands
for cmd in jq curl uuidgen; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is required but not installed" >&2
        exit 0
    fi
done

# Config (continued)
PUBLIC_KEY="${LANGFUSE_PUBLIC_KEY:-}"
SECRET_KEY="${LANGFUSE_SECRET_KEY:-}"
PROJECT="${LANGFUSE_PROJECT:-claude-code}"
API_BASE="${LANGFUSE_HOST:-http://localhost:3000}"
STATE_FILE="${STATE_FILE:-$HOME/.claude/state/langfuse_state.json}"

# Global variables
CURRENT_TRACE_ID=""  # Track current trace for cleanup on exit

# Ensure state directory exists
mkdir -p "$(dirname "$STATE_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"

# Validate API keys
if [ -z "$PUBLIC_KEY" ] || [ -z "$SECRET_KEY" ]; then
    log "ERROR" "LANGFUSE_PUBLIC_KEY or LANGFUSE_SECRET_KEY not set"
    exit 0
fi

# Create Basic auth header
AUTH_HEADER=$(echo -n "$PUBLIC_KEY:$SECRET_KEY" | base64 | tr -d '\n')

# Langfuse API call helper - uses file-based approach to handle complex JSON
langfuse_ingest_file() {
    local data_file="$1"

    local response
    local http_code
    response=$(curl -s --max-time 60 -w "\n%{http_code}" -X POST \
        -H "Authorization: Basic $AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d @"$data_file" \
        "$API_BASE/api/public/ingestion" 2>&1)

    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
        log "ERROR" "Langfuse API call failed"
        log "ERROR" "HTTP $http_code: $response"
        log "ERROR" "Request file size: $(wc -c < "$data_file") bytes"
        if [ "$DEBUG" = "true" ]; then
            log "DEBUG" "Request data: $(head -c 500 "$data_file")"
        fi
        return 1
    fi

    debug "Langfuse ingestion succeeded: $http_code"
    echo "$response"
}

# Load state
load_state() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "{}"
        return
    fi
    cat "$STATE_FILE"
}

# Save state
save_state() {
    local state="$1"
    printf '%s\n' "$state" > "$STATE_FILE" 2>/dev/null || log "ERROR" "Failed to save state"
}

# Get message content (using printf for safety with special chars)
get_content() {
    local msg="$1"
    printf '%s' "$msg" | jq -c 'if type == "object" and has("message") then .message.content elif type == "object" then .content else null end' 2>/dev/null || echo "null"
}

# Check if message is tool result
is_tool_result() {
    local msg="$1"
    local content
    content=$(get_content "$msg")

    if printf '%s' "$content" | jq -e 'if type == "array" then any(.[]; type == "object" and .type == "tool_result") else false end' > /dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

# Extract text from content
extract_text() {
    local msg="$1"
    local content
    content=$(get_content "$msg")

    # Handle string content
    if printf '%s' "$content" | jq -e 'type == "string"' > /dev/null 2>&1; then
        local text
        text=$(printf '%s' "$content" | jq -r '.' 2>/dev/null) || text=""
        # Skip if whitespace-only
        if [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
            printf '%s' "$text"
        fi
        return
    fi

    # Handle array content - extract text blocks, filtering out whitespace-only
    if printf '%s' "$content" | jq -e 'type == "array"' > /dev/null 2>&1; then
        printf '%s' "$content" | jq -r '
            [.[] | select(type == "object" and .type == "text") | .text] |
            map(select(. | gsub("\\s"; "") | length > 0)) |
            join("\n")
        ' 2>/dev/null || echo ""
        return
    fi

    echo ""
}

# Get tool uses from message
get_tool_uses() {
    local msg="$1"
    local content
    content=$(get_content "$msg")

    if ! printf '%s' "$content" | jq -e 'type == "array"' > /dev/null 2>&1; then
        echo "[]"
        return
    fi

    printf '%s' "$content" | jq -c '[.[] | select(type == "object" and .type == "tool_use")]' 2>/dev/null || echo "[]"
}

# Get usage from assistant message
get_usage() {
    local msg="$1"
    printf '%s' "$msg" | jq -c 'if type == "object" and has("message") then .message.usage // null else null end' 2>/dev/null || echo "null"
}

# Truncate large content to prevent timeout on huge MCP responses
truncate_content() {
    local content="$1"
    local max_len="${2:-10000}"  # Default 10KB max

    local len=${#content}
    if [ "$len" -gt "$max_len" ]; then
        echo "${content:0:$max_len}... [TRUNCATED: ${len} chars total]"
    else
        echo "$content"
    fi
}

# Find tool result
find_tool_result() {
    local tool_id="$1"
    local tool_results="$2"

    local result
    result=$(printf '%s' "$tool_results" | jq -r --arg id "$tool_id" '
        first(
            .[] |
            (if type == "object" and has("message") then .message.content elif type == "object" then .content else null end) as $content |
            if $content | type == "array" then
                $content[] |
                select(type == "object" and .type == "tool_result" and .tool_use_id == $id) |
                if .content | type == "array" then
                    [.content[] | select(type == "object" and .type == "text") | .text] | join(" ")
                elif .content | type == "string" then
                    .content
                else
                    .content | tostring
                end
            else
                empty
            end
        ) // "No result"
    ')

    # Truncate large tool results (MCP responses can be huge)
    truncate_content "$result" 10000
}

# Merge assistant message parts (for SSE streaming)
merge_assistant_parts() {
    local parts="$1"

    printf '%s' "$parts" | jq -s '
        .[0][0] as $base |
        (.[0] | map(if type == "object" and has("message") then .message.content elif type == "object" then .content else null end) | map(select(. != null))) as $contents |
        ($contents | map(
            if type == "string" then [{"type":"text","text":.}]
            elif type == "array" then .
            else [.]
            end
        ) | add // []) as $merged_content |
        $base |
        if type == "object" and has("message") then
            .message.content = $merged_content
        elif type == "object" then
            .content = $merged_content
        else
            .
        end
    '
}

# Create Langfuse trace
create_trace() {
    local session_id="$1"
    local turn_num="$2"
    local user_msg="$3"
    local assistant_messages="$4"
    local tool_results="$5"

    debug "=== create_trace START ==="
    debug "session_id: $session_id"
    debug "turn_num: $turn_num"
    debug "user_msg length: ${#user_msg}"
    debug "assistant_messages length: ${#assistant_messages}"

    local trace_id
    trace_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    CURRENT_TRACE_ID="$trace_id"
    debug "trace_id: $trace_id"

    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    local user_text
    user_text=$(extract_text "$user_msg")
    debug "user_text: $user_text"

    # Build batch of events to send
    local batch="[]"

    # 1. Create trace
    local event_id
    event_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    debug "Creating trace event with event_id: $event_id"

    local trace_event
    trace_event=$(jq -n \
        --arg event_id "$event_id" \
        --arg id "$trace_id" \
        --arg name "Claude Code Turn $turn_num" \
        --arg session "$session_id" \
        --arg input "$user_text" \
        --arg time "$now" \
        --argjson turn "$turn_num" \
        '{
            id: $event_id,
            type: "trace-create",
            timestamp: $time,
            body: {
                id: $id,
                name: $name,
                sessionId: $session,
                input: $input,
                metadata: {
                    source: "claude-code",
                    turn: $turn
                }
            }
        }')
    debug "trace_event valid: $(echo "$trace_event" | jq -e '.' >/dev/null 2>&1 && echo 'yes' || echo 'no')"
    batch=$(echo "$batch" | jq --argjson evt "$trace_event" '. += [$evt]')
    debug "batch after trace_event - length: $(echo "$batch" | jq 'length' 2>/dev/null || echo 'INVALID')"

    # Aggregate all assistant messages into ONE generation per turn
    local all_output=""
    local total_input_tokens=0
    local total_output_tokens=0
    local model_name="unknown"
    local first_timestamp="$now"
    local last_timestamp="$now"
    local msg_count=0

    debug "Processing assistant_messages - count: $(echo "$assistant_messages" | jq 'length' 2>/dev/null || echo 'unknown')"

    # First pass: collect all text and aggregate tokens
    while IFS= read -r assistant_msg; do
        msg_count=$((msg_count + 1))

        # Get timestamp (use first message's timestamp as start)
        local msg_timestamp
        msg_timestamp=$(echo "$assistant_msg" | jq -r '.timestamp // ""' 2>/dev/null)
        if [ -n "$msg_timestamp" ]; then
            if [ "$msg_count" -eq 1 ]; then
                first_timestamp="$msg_timestamp"
            fi
            last_timestamp="$msg_timestamp"
        fi

        # Extract text (filtering whitespace-only)
        local assistant_text
        assistant_text=$(extract_text "$assistant_msg")
        if [ -n "$assistant_text" ]; then
            all_output="${all_output}${assistant_text}\n"
        fi

        # Get model name (use first non-unknown)
        local msg_model
        msg_model=$(echo "$assistant_msg" | jq -r 'if type == "object" and has("message") then .message.model // "unknown" else "unknown" end' 2>/dev/null)
        if [ "$msg_model" != "unknown" ] && [ "$model_name" = "unknown" ]; then
            model_name="$msg_model"
        fi

        # Aggregate token usage
        local usage
        usage=$(get_usage "$assistant_msg")
        if [ "$usage" != "null" ] && [ -n "$usage" ]; then
            local in_tok out_tok
            in_tok=$(echo "$usage" | jq -r '.input_tokens // 0')
            out_tok=$(echo "$usage" | jq -r '.output_tokens // 0')
            total_input_tokens=$((total_input_tokens + in_tok))
            total_output_tokens=$((total_output_tokens + out_tok))
        fi
    done < <(echo "$assistant_messages" | jq -c '.[]')

    debug "Aggregated: output_len=${#all_output}, input_tokens=$total_input_tokens, output_tokens=$total_output_tokens, model=$model_name"

    # Create ONE generation event for the entire turn
    local gen_id
    gen_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local gen_event_id
    gen_event_id=$(uuidgen | tr '[:upper:]' '[:lower:]')

    # Clean up output (remove trailing \n) and truncate if too large
    all_output=$(echo -e "$all_output" | sed 's/\\n$//')
    all_output=$(truncate_content "$all_output" 20000)

    local gen_event
    gen_event=$(jq -n \
        --arg event_id "$gen_event_id" \
        --arg id "$gen_id" \
        --arg trace_id "$trace_id" \
        --arg name "LLM Response" \
        --arg model "$model_name" \
        --arg input "$user_text" \
        --arg output "$all_output" \
        --arg start_time "$first_timestamp" \
        --arg end_time "$last_timestamp" \
        --argjson input_tokens "$total_input_tokens" \
        --argjson output_tokens "$total_output_tokens" \
        '{
            id: $event_id,
            type: "generation-create",
            timestamp: $end_time,
            body: {
                id: $id,
                traceId: $trace_id,
                name: $name,
                model: $model,
                input: $input,
                output: $output,
                startTime: $start_time,
                endTime: $end_time,
                usage: {
                    input: $input_tokens,
                    output: $output_tokens
                },
                metadata: {
                    source: "claude-code",
                    message_count: $msg_count
                }
            }
        }' --argjson msg_count "$msg_count")
    batch=$(echo "$batch" | jq --argjson evt "$gen_event" '. += [$evt]')
    debug "batch after gen_event - valid: $(echo "$batch" | jq -e '.' >/dev/null 2>&1 && echo 'yes' || echo 'no')"

    # Second pass: collect tool uses as spans
    local gen_num=0
    while IFS= read -r assistant_msg; do
        gen_num=$((gen_num + 1))

        local msg_timestamp
        msg_timestamp=$(echo "$assistant_msg" | jq -r '.timestamp // ""' 2>/dev/null)
        if [ -z "$msg_timestamp" ]; then
            msg_timestamp="$now"
        fi

        # Process tool uses
        local tool_uses
        tool_uses=$(get_tool_uses "$assistant_msg")

        if [ "$(echo "$tool_uses" | jq 'length')" -gt 0 ]; then
            while IFS= read -r tool; do
                local span_id
                span_id=$(uuidgen | tr '[:upper:]' '[:lower:]')

                local tool_name
                tool_name=$(echo "$tool" | jq -r '.name // "tool"')

                local tool_input
                tool_input=$(echo "$tool" | jq -c '.input // {}')

                local tool_use_id
                tool_use_id=$(echo "$tool" | jq -r '.id // ""')

                local tool_output
                tool_output=$(find_tool_result "$tool_use_id" "$tool_results")

                # Create span event for tool
                local span_event_id
                span_event_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
                local span_event
                span_event=$(jq -n \
                    --arg event_id "$span_event_id" \
                    --arg id "$span_id" \
                    --arg trace_id "$trace_id" \
                    --arg parent_id "$gen_id" \
                    --arg name "$tool_name" \
                    --argjson input "$tool_input" \
                    --arg output "$tool_output" \
                    --arg time "$msg_timestamp" \
                    '{
                        id: $event_id,
                        type: "span-create",
                        timestamp: $time,
                        body: {
                            id: $id,
                            traceId: $trace_id,
                            parentObservationId: $parent_id,
                            name: $name,
                            input: $input,
                            output: $output,
                            startTime: $time,
                            endTime: $time,
                            metadata: {
                                type: "tool",
                                source: "claude-code"
                            }
                        }
                    }')
                batch=$(echo "$batch" | jq --argjson evt "$span_event" '. += [$evt]')

            done < <(echo "$tool_uses" | jq -c '.[]')
        fi

    done < <(echo "$assistant_messages" | jq -c '.[]')

    # Update trace with output
    local update_event_id
    update_event_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
    local trace_update
    trace_update=$(jq -n \
        --arg event_id "$update_event_id" \
        --arg id "$trace_id" \
        --arg output "$all_output" \
        --arg time "$now" \
        '{
            id: $event_id,
            type: "trace-create",
            timestamp: $time,
            body: {
                id: $id,
                output: $output
            }
        }')
    batch=$(echo "$batch" | jq --argjson evt "$trace_update" '. += [$evt]')
    debug "batch after trace_update - valid: $(echo "$batch" | jq -e '.' >/dev/null 2>&1 && echo 'yes' || echo 'no')"
    debug "batch final length: $(echo "$batch" | jq 'length' 2>/dev/null || echo 'INVALID')"

    # Send batch to Langfuse using temp file to handle complex JSON
    local temp_dir
    temp_dir=$(mktemp -d)
    local batch_file="$temp_dir/batch.json"
    local payload_file="$temp_dir/payload.json"

    debug "Writing batch to $batch_file"

    # Write batch to file
    echo "$batch" > "$batch_file"
    debug "batch_file size: $(wc -c < "$batch_file") bytes"

    # Validate batch is valid JSON array
    if ! jq -e 'type == "array"' "$batch_file" >/dev/null 2>&1; then
        log "ERROR" "Invalid batch - not a valid JSON array"
        log "ERROR" "batch_file first 200 chars: $(head -c 200 "$batch_file")"
        rm -rf "$temp_dir"
        return 1
    fi
    debug "batch_file validated as array"

    # Create payload file
    debug "Creating payload file with slurpfile"
    jq -n --slurpfile batch "$batch_file" '{batch: $batch[0]}' > "$payload_file" 2>&1
    local jq_exit=$?
    debug "jq slurpfile exit code: $jq_exit"

    # Debug logging
    debug "Batch length: $(jq 'length' "$batch_file" 2>/dev/null || echo 'INVALID')"
    debug "Payload file size: $(wc -c < "$payload_file") bytes"
    debug "Payload first 200 chars: $(head -c 200 "$payload_file")"

    # Validate payload
    if ! jq -e '.batch | type == "array"' "$payload_file" >/dev/null 2>&1; then
        log "ERROR" "Invalid payload - batch field is not an array"
        rm -rf "$temp_dir"
        return 1
    fi

    langfuse_ingest_file "$payload_file" || true

    # Cleanup
    rm -rf "$temp_dir"

    CURRENT_TRACE_ID=""
    log "INFO" "Created trace $trace_id for turn $turn_num with $gen_num generation(s)"
}

# Main function
main() {
    local script_start
    script_start=$(date +%s)

    # Use already-captured stdin (from top of script)
    local hook_input="$STDIN_CONTENT"

    # Check stop_hook_active flag
    if echo "$hook_input" | jq -e '.stop_hook_active == true' > /dev/null 2>&1; then
        debug "stop_hook_active=true, skipping"
        exit 0
    fi

    # Extract session info
    local session_id
    session_id=$(echo "$hook_input" | jq -r '.session_id // ""')

    local transcript_path
    transcript_path=$(echo "$hook_input" | jq -r '.transcript_path // ""' | sed "s|^~|$HOME|")

    if [ -z "$session_id" ] || [ ! -f "$transcript_path" ]; then
        log "WARN" "Invalid input: session=$session_id, transcript=$transcript_path"
        exit 0
    fi

    log "INFO" "Processing session $session_id"

    # Load state
    local state
    state=$(load_state)

    local last_line
    last_line=$(echo "$state" | jq -r --arg sid "$session_id" '.[$sid].last_line // -1')

    local turn_count
    turn_count=$(echo "$state" | jq -r --arg sid "$session_id" '.[$sid].turn_count // 0')

    # Parse new messages
    local new_messages
    new_messages=$(awk -v start="$last_line" 'NR > start + 1 && NF' "$transcript_path")

    if [ -z "$new_messages" ]; then
        debug "No new messages"
        exit 0
    fi

    local msg_count
    msg_count=$(echo "$new_messages" | wc -l)
    log "INFO" "Found $msg_count new messages"

    # Estimate processing time for large transcripts
    if [ "$msg_count" -gt 50 ]; then
        log "WARN" "Large transcript ($msg_count messages) - processing may take a while"
    fi

    # Group into turns
    local current_user=""
    local current_assistants="[]"
    local current_msg_id=""
    local current_assistant_parts="[]"
    local current_tool_results="[]"
    local turns=0
    local new_last_line=$last_line

    while IFS= read -r line; do
        new_last_line=$((new_last_line + 1))

        if [ -z "$line" ]; then
            continue
        fi

        # Safely extract role - handle jq failures gracefully
        local role
        role=$(printf '%s' "$line" | jq -r 'if type == "object" and has("message") then .message.role elif type == "object" then .role else "unknown" end' 2>/dev/null) || role="unknown"

        if [ "$role" = "user" ]; then
            if [ "$(is_tool_result "$line")" = "true" ]; then
                current_tool_results=$(printf '%s' "$current_tool_results" | jq --argjson msg "$line" '. += [$msg]' 2>/dev/null) || current_tool_results="[]"
            else
                # Finalize pending assistant message
                if [ -n "$current_msg_id" ] && [ "$(printf '%s' "$current_assistant_parts" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
                    local merged
                    merged=$(merge_assistant_parts "$current_assistant_parts")
                    current_assistants=$(printf '%s' "$current_assistants" | jq --argjson msg "$merged" '. += [$msg]' 2>/dev/null) || current_assistants="[]"
                    current_assistant_parts="[]"
                    current_msg_id=""
                fi

                # Create trace for previous turn
                if [ -n "$current_user" ] && [ "$(printf '%s' "$current_assistants" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
                    turns=$((turns + 1))
                    local turn_num=$((turn_count + turns))
                    log "INFO" "Processing turn $turn_num..."
                    create_trace "$session_id" "$turn_num" "$current_user" "$current_assistants" "$current_tool_results" || true
                fi

                # Start new turn
                current_user="$line"
                current_assistants="[]"
                current_assistant_parts="[]"
                current_msg_id=""
                current_tool_results="[]"
            fi
        elif [ "$role" = "assistant" ]; then
            local msg_id
            msg_id=$(printf '%s' "$line" | jq -r 'if type == "object" and has("message") then .message.id else "" end' 2>/dev/null) || msg_id=""

            if [ -z "$msg_id" ]; then
                current_assistant_parts=$(printf '%s' "$current_assistant_parts" | jq --argjson msg "$line" '. += [$msg]' 2>/dev/null) || true
            elif [ "$msg_id" = "$current_msg_id" ]; then
                current_assistant_parts=$(printf '%s' "$current_assistant_parts" | jq --argjson msg "$line" '. += [$msg]' 2>/dev/null) || true
            else
                if [ -n "$current_msg_id" ] && [ "$(printf '%s' "$current_assistant_parts" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
                    local merged
                    merged=$(merge_assistant_parts "$current_assistant_parts")
                    current_assistants=$(printf '%s' "$current_assistants" | jq --argjson msg "$merged" '. += [$msg]' 2>/dev/null) || true
                fi
                current_msg_id="$msg_id"
                current_assistant_parts=$(jq -n --argjson msg "$line" '[$msg]')
            fi
        fi
    done <<< "$new_messages"

    # Process final turn
    if [ -n "$current_msg_id" ] && [ "$(printf '%s' "$current_assistant_parts" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
        local merged
        merged=$(merge_assistant_parts "$current_assistant_parts")
        current_assistants=$(printf '%s' "$current_assistants" | jq --argjson msg "$merged" '. += [$msg]' 2>/dev/null) || true
    fi

    if [ -n "$current_user" ] && [ "$(printf '%s' "$current_assistants" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]; then
        turns=$((turns + 1))
        local turn_num=$((turn_count + turns))
        log "INFO" "Processing final turn $turn_num..."
        create_trace "$session_id" "$turn_num" "$current_user" "$current_assistants" "$current_tool_results" || true
    fi

    # Update state
    local updated
    updated=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    state=$(printf '%s' "$state" | jq \
        --arg sid "$session_id" \
        --arg line "$new_last_line" \
        --arg count "$((turn_count + turns))" \
        --arg time "$updated" \
        '.[$sid] = {last_line: ($line | tonumber), turn_count: ($count | tonumber), updated: $time}' 2>/dev/null) || state="{}"

    save_state "$state"

    # Log execution time
    local script_end
    script_end=$(date +%s)
    local duration=$((script_end - script_start))

    log "INFO" "Processed $turns turns in ${duration}s"
}

# Check if task is complete - uses marker file written by supervisor skill
check_auto_continue() {
    local transcript_path="$1"
    local workspace_dir="$2"

    # Check if supervisor wrote the completion marker file
    # This is more reliable than grepping transcript (avoids matching code content)
    local is_complete="false"
    local marker_file="$workspace_dir/.supervisor_complete"

    if [ -f "$marker_file" ]; then
        is_complete="true"
        log "INFO" "Found completion marker: $marker_file"
        # Clean up the marker file after reading
        rm -f "$marker_file" 2>/dev/null
    fi

    log "INFO" "Auto-continue check: is_complete=$is_complete (marker_file=$marker_file)"

    local flag_file="$workspace_dir/.claude_continue_flag"

    if [ "$is_complete" = "true" ]; then
        log "INFO" "Task completed - no auto-continue needed"
        rm -f "$flag_file" 2>/dev/null
        return 0
    else
        log "INFO" "Task not complete - triggering auto-continue"

        # Write flag for run.sh to detect (NO stdout - it interferes with Claude Code!)
        echo "CONTINUE_NEEDED" > "$flag_file"
        echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$flag_file"

        return 1
    fi
}

# Run main
main

# After tracing, check if auto-continue is needed
WORKSPACE_DIR=$(echo "$STDIN_CONTENT" | jq -r '.cwd // ""')
TRANSCRIPT=$(echo "$STDIN_CONTENT" | jq -r '.transcript_path // ""' | sed "s|^~|$HOME|")

if [ -n "$WORKSPACE_DIR" ] && [ -n "$TRANSCRIPT" ]; then
    check_auto_continue "$TRANSCRIPT" "$WORKSPACE_DIR"
fi

exit 0
