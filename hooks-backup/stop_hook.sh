#!/bin/bash
###
# Claude Code Stop Hook - Langfuse Tracing Integration
# Sends Claude Code traces to Langfuse after each response.
# Adapted from LangSmith hook for self-hosted Langfuse.
###

set -e

# Config (needed early for logging)
LOG_FILE="$HOME/.claude/state/hook.log"
DEBUG="$(echo "$LANGFUSE_DEBUG" | tr '[:upper:]' '[:lower:]')"

# Ensure log directory exists FIRST
mkdir -p "$(dirname "$LOG_FILE")"

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
    echo "$state" > "$STATE_FILE"
}

# Get message content
get_content() {
    local msg="$1"
    echo "$msg" | jq -c 'if type == "object" and has("message") then .message.content elif type == "object" then .content else null end'
}

# Check if message is tool result
is_tool_result() {
    local msg="$1"
    local content
    content=$(get_content "$msg")

    if echo "$content" | jq -e 'if type == "array" then any(.[]; type == "object" and .type == "tool_result") else false end' > /dev/null 2>&1; then
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
    if echo "$content" | jq -e 'type == "string"' > /dev/null 2>&1; then
        echo "$content" | jq -r '.'
        return
    fi

    # Handle array content - extract text blocks
    if echo "$content" | jq -e 'type == "array"' > /dev/null 2>&1; then
        echo "$content" | jq -r '[.[] | select(type == "object" and .type == "text") | .text] | join("\n")'
        return
    fi

    echo ""
}

# Get tool uses from message
get_tool_uses() {
    local msg="$1"
    local content
    content=$(get_content "$msg")

    if ! echo "$content" | jq -e 'type == "array"' > /dev/null 2>&1; then
        echo "[]"
        return
    fi

    echo "$content" | jq -c '[.[] | select(type == "object" and .type == "tool_use")]'
}

# Get usage from assistant message
get_usage() {
    local msg="$1"
    echo "$msg" | jq -c 'if type == "object" and has("message") then .message.usage // null else null end'
}

# Find tool result
find_tool_result() {
    local tool_id="$1"
    local tool_results="$2"

    echo "$tool_results" | jq -r --arg id "$tool_id" '
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
    '
}

# Merge assistant message parts (for SSE streaming)
merge_assistant_parts() {
    local parts="$1"

    echo "$parts" | jq -s '
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

    # Process each assistant message (each represents one LLM generation)
    local gen_num=0
    local all_output=""
    debug "Processing assistant_messages - count: $(echo "$assistant_messages" | jq 'length' 2>/dev/null || echo 'unknown')"

    while IFS= read -r assistant_msg; do
        gen_num=$((gen_num + 1))
        debug "Processing generation $gen_num - msg length: ${#assistant_msg}"

        local gen_id
        gen_id=$(uuidgen | tr '[:upper:]' '[:lower:]')

        local msg_timestamp
        msg_timestamp=$(echo "$assistant_msg" | jq -r '.timestamp // ""' 2>/dev/null)
        if [ -z "$msg_timestamp" ]; then
            msg_timestamp="$now"
        fi
        debug "gen $gen_num timestamp: $msg_timestamp"

        local assistant_text
        assistant_text=$(extract_text "$assistant_msg")
        debug "gen $gen_num text length: ${#assistant_text}"
        all_output="${all_output}${assistant_text}\n"

        # Get model name
        local model_name
        model_name=$(echo "$assistant_msg" | jq -r 'if type == "object" and has("message") then .message.model // "unknown" else "unknown" end' 2>/dev/null)
        debug "gen $gen_num model: $model_name"

        # Get usage
        local usage
        usage=$(get_usage "$assistant_msg")
        local input_tokens=0
        local output_tokens=0
        if [ "$usage" != "null" ] && [ -n "$usage" ]; then
            input_tokens=$(echo "$usage" | jq -r '.input_tokens // 0')
            output_tokens=$(echo "$usage" | jq -r '.output_tokens // 0')
        fi

        # Create generation event
        local gen_event_id
        gen_event_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
        local gen_event
        gen_event=$(jq -n \
            --arg event_id "$gen_event_id" \
            --arg id "$gen_id" \
            --arg trace_id "$trace_id" \
            --arg name "LLM Call $gen_num" \
            --arg model "$model_name" \
            --arg input "$user_text" \
            --arg output "$assistant_text" \
            --arg time "$msg_timestamp" \
            --argjson input_tokens "$input_tokens" \
            --argjson output_tokens "$output_tokens" \
            '{
                id: $event_id,
                type: "generation-create",
                timestamp: $time,
                body: {
                    id: $id,
                    traceId: $trace_id,
                    name: $name,
                    model: $model,
                    input: $input,
                    output: $output,
                    startTime: $time,
                    endTime: $time,
                    usage: {
                        input: $input_tokens,
                        output: $output_tokens
                    },
                    metadata: {
                        source: "claude-code"
                    }
                }
            }')
        batch=$(echo "$batch" | jq --argjson evt "$gen_event" '. += [$evt]')
        debug "batch after gen_event $gen_num - valid: $(echo "$batch" | jq -e '.' >/dev/null 2>&1 && echo 'yes' || echo 'no')"

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

        local role
        role=$(echo "$line" | jq -r 'if type == "object" and has("message") then .message.role elif type == "object" then .role else "unknown" end')

        if [ "$role" = "user" ]; then
            if [ "$(is_tool_result "$line")" = "true" ]; then
                current_tool_results=$(echo "$current_tool_results" | jq --argjson msg "$line" '. += [$msg]')
            else
                # Finalize pending assistant message
                if [ -n "$current_msg_id" ] && [ "$(echo "$current_assistant_parts" | jq 'length')" -gt 0 ]; then
                    local merged
                    merged=$(merge_assistant_parts "$current_assistant_parts")
                    current_assistants=$(echo "$current_assistants" | jq --argjson msg "$merged" '. += [$msg]')
                    current_assistant_parts="[]"
                    current_msg_id=""
                fi

                # Create trace for previous turn
                if [ -n "$current_user" ] && [ "$(echo "$current_assistants" | jq 'length')" -gt 0 ]; then
                    turns=$((turns + 1))
                    local turn_num=$((turn_count + turns))
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
            msg_id=$(echo "$line" | jq -r 'if type == "object" and has("message") then .message.id else "" end')

            if [ -z "$msg_id" ]; then
                current_assistant_parts=$(echo "$current_assistant_parts" | jq --argjson msg "$line" '. += [$msg]')
            elif [ "$msg_id" = "$current_msg_id" ]; then
                current_assistant_parts=$(echo "$current_assistant_parts" | jq --argjson msg "$line" '. += [$msg]')
            else
                if [ -n "$current_msg_id" ] && [ "$(echo "$current_assistant_parts" | jq 'length')" -gt 0 ]; then
                    local merged
                    merged=$(merge_assistant_parts "$current_assistant_parts")
                    current_assistants=$(echo "$current_assistants" | jq --argjson msg "$merged" '. += [$msg]')
                fi
                current_msg_id="$msg_id"
                current_assistant_parts=$(jq -n --argjson msg "$line" '[$msg]')
            fi
        fi
    done <<< "$new_messages"

    # Process final turn
    if [ -n "$current_msg_id" ] && [ "$(echo "$current_assistant_parts" | jq 'length')" -gt 0 ]; then
        local merged
        merged=$(merge_assistant_parts "$current_assistant_parts")
        current_assistants=$(echo "$current_assistants" | jq --argjson msg "$merged" '. += [$msg]')
    fi

    if [ -n "$current_user" ] && [ "$(echo "$current_assistants" | jq 'length')" -gt 0 ]; then
        turns=$((turns + 1))
        local turn_num=$((turn_count + turns))
        create_trace "$session_id" "$turn_num" "$current_user" "$current_assistants" "$current_tool_results" || true
    fi

    # Update state
    local updated
    updated=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    state=$(echo "$state" | jq \
        --arg sid "$session_id" \
        --arg line "$new_last_line" \
        --arg count "$((turn_count + turns))" \
        --arg time "$updated" \
        '.[$sid] = {last_line: ($line | tonumber), turn_count: ($count | tonumber), updated: $time}')

    save_state "$state"

    # Log execution time
    local script_end
    script_end=$(date +%s)
    local duration=$((script_end - script_start))

    log "INFO" "Processed $turns turns in ${duration}s"
}

# Run main
main

exit 0
