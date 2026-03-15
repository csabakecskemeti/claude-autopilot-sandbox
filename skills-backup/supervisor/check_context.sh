#!/bin/bash
# Check context/session size and recommend compaction if needed
# Uses both file size (proxy) and configurable token limits

CONFIG_FILE="$(dirname "$0")/config.json"
CLAUDE_DIR="$HOME/.claude"

# Load config
if [ -f "$CONFIG_FILE" ]; then
    MAX_TOKENS=$(jq -r '.context.max_context_tokens // 800000' "$CONFIG_FILE")
    WARN_PERCENT=$(jq -r '.context.warn_threshold_percent // 60' "$CONFIG_FILE")
    COMPACT_PERCENT=$(jq -r '.context.compact_threshold_percent // 75' "$CONFIG_FILE")
    WARN_KB=$(jq -r '.context.session_file_warn_kb // 500' "$CONFIG_FILE")
    COMPACT_KB=$(jq -r '.context.session_file_compact_kb // 800' "$CONFIG_FILE")
    AUTO_COMPACT=$(jq -r '.auto_compact // false' "$CONFIG_FILE")
else
    MAX_TOKENS=800000
    WARN_PERCENT=60
    COMPACT_PERCENT=75
    WARN_KB=500
    COMPACT_KB=800
    AUTO_COMPACT=false
fi

# Calculate token thresholds from percentages
WARN_TOKENS=$((MAX_TOKENS * WARN_PERCENT / 100))
COMPACT_TOKENS=$((MAX_TOKENS * COMPACT_PERCENT / 100))

# Find current session file (most recently modified)
SESSION_FILE=$(find "$CLAUDE_DIR/projects" -name "*.jsonl" -type f 2>/dev/null | xargs ls -t 2>/dev/null | head -1)

if [ -z "$SESSION_FILE" ]; then
    echo "STATUS: UNKNOWN"
    echo "Could not find session file"
    exit 0
fi

# Get file size in KB
SIZE_KB=$(du -k "$SESSION_FILE" 2>/dev/null | cut -f1)

if [ -z "$SIZE_KB" ]; then
    SIZE_KB=0
fi

# Estimate tokens (rough: ~4-6 chars per token, session file is JSON with overhead)
# Using conservative estimate: 1KB ≈ 150-200 tokens for JSONL format
SIZE_BYTES=$((SIZE_KB * 1024))
ESTIMATED_TOKENS=$((SIZE_KB * 170))  # ~170 tokens per KB of session file

# Calculate percentage of max context used
PERCENT_USED=$((ESTIMATED_TOKENS * 100 / MAX_TOKENS))

echo "═══════════════════════════════════════════════════════════"
echo "                   CONTEXT STATUS CHECK"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "SESSION_FILE: $SESSION_FILE"
echo "FILE_SIZE: ${SIZE_KB} KB"
echo ""
echo "MAX_CONTEXT: $MAX_TOKENS tokens"
echo "ESTIMATED_TOKENS: ~$ESTIMATED_TOKENS tokens"
echo "PERCENT_USED: ${PERCENT_USED}%"
echo ""
echo "THRESHOLDS:"
echo "  Warning:  ${WARN_PERCENT}% ($WARN_TOKENS tokens)"
echo "  Compact:  ${COMPACT_PERCENT}% ($COMPACT_TOKENS tokens)"
echo ""

# Determine status based on both file size and estimated tokens
if [ "$SIZE_KB" -ge "$COMPACT_KB" ] || [ "$ESTIMATED_TOKENS" -ge "$COMPACT_TOKENS" ]; then
    echo "STATUS: CRITICAL"
    echo ""
    echo "⚠️  CONTEXT IS VERY LARGE - COMPACTION REQUIRED"
    echo ""
    echo "RECOMMENDATION:"
    echo "1. Store critical context in memory:"
    echo "   ~/.claude/skills/memory/memory.sh store \"KEY: [current state]\" --category session"
    echo ""
    echo "2. Run compaction:"
    echo "   /compact"
    echo ""
    echo "3. Recall context after compact:"
    echo "   ~/.claude/skills/memory/memory.sh recall \"session\""
    echo ""

    if [ "$AUTO_COMPACT" = "true" ]; then
        echo "AUTO_COMPACT: ENABLED - Supervisor should trigger /compact"
    fi
    exit 2

elif [ "$SIZE_KB" -ge "$WARN_KB" ] || [ "$ESTIMATED_TOKENS" -ge "$WARN_TOKENS" ]; then
    echo "STATUS: WARNING"
    echo ""
    echo "⚡ Context is getting large. Consider compacting soon."
    echo ""
    echo "RECOMMENDATION: Store important findings in memory now"
    echo "   ~/.claude/skills/memory/memory.sh store \"KEY: [findings]\" --category session"
    echo ""
    exit 1

else
    echo "STATUS: OK"
    echo ""
    echo "✅ Context size is healthy."
    echo ""
    exit 0
fi
