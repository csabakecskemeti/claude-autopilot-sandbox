#!/bin/bash
# PreToolUse hook: Block direct image reads, redirect to /vision skill
#
# Local LLMs don't support multimodal tool_result content. When Claude reads an
# image file directly, it corrupts the session with multimodal data that the LLM
# cannot process, causing persistent "Only text tool_result blocks are supported"
# errors until the session is restarted.
#
# This hook intercepts Read tool calls on image files and blocks them with a
# message directing the agent to use the /vision skill instead.

set -e

# Read hook input from stdin
INPUT=$(cat)

# Extract tool name and file path
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

# Only check Read tool
if [ "$TOOL_NAME" != "Read" ]; then
    exit 0
fi

# Check if file path matches image extensions (case insensitive)
if echo "$FILE_PATH" | grep -qiE '\.(png|jpg|jpeg|gif|webp|bmp|heic|heif|tiff|tif|ico|svg)$'; then
    # Block the read and provide guidance
    jq -n '{
        decision: "block",
        reason: "BLOCKED: Cannot read image files directly - local LLMs do not support multimodal content.\n\nUse the /vision skill instead:\n  /vision ocr '"$FILE_PATH"'\n  /vision analyze '"$FILE_PATH"' \"your prompt\"\n\nThis extracts text or analyzes images via a separate vision API that returns text-only results."
    }'
    exit 0
fi

# Allow all other reads
exit 0
