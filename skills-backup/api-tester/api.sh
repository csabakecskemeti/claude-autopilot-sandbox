#!/usr/bin/env bash
# API Tester - REST API testing with curl

set -e

REQUESTS_DIR="$HOME/.claude/api-requests"
mkdir -p "$REQUESTS_DIR"

# Handle special commands
case "$1" in
    --list)
        echo "Saved requests:"
        ls -1 "$REQUESTS_DIR" 2>/dev/null | sed 's/\.json$//' || echo "  (none)"
        exit 0
        ;;
    --replay)
        REQUEST_FILE="$REQUESTS_DIR/$2.json"
        if [[ ! -f "$REQUEST_FILE" ]]; then
            echo "Request not found: $2"
            exit 1
        fi
        # Read and execute saved request
        METHOD=$(jq -r '.method' "$REQUEST_FILE")
        URL=$(jq -r '.url' "$REQUEST_FILE")
        BODY=$(jq -r '.body // empty' "$REQUEST_FILE")
        HEADERS=$(jq -r '.headers[]? // empty' "$REQUEST_FILE")

        CURL_ARGS=(-s -w "\n---\nStatus: %{http_code}\nTime: %{time_total}s\n" -X "$METHOD")
        [[ -n "$BODY" ]] && CURL_ARGS+=(-d "$BODY" -H "Content-Type: application/json")
        while IFS= read -r header; do
            [[ -n "$header" ]] && CURL_ARGS+=(-H "$header")
        done <<< "$HEADERS"

        echo "Replaying: $METHOD $URL"
        echo "---"
        curl "${CURL_ARGS[@]}" "$URL" | python3 -m json.tool 2>/dev/null || cat
        exit 0
        ;;
esac

METHOD="$1"
URL="$2"
BODY="$3"
shift 3 2>/dev/null || true

HEADERS=()
SAVE_NAME=""

# Parse additional arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -H)
            HEADERS+=("$2")
            shift 2
            ;;
        --save)
            SAVE_NAME="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$METHOD" ]] || [[ -z "$URL" ]]; then
    echo "Usage: $0 <METHOD> <URL> [body] [-H 'Header: Value'] [--save name]"
    echo "       $0 --replay <name>"
    echo "       $0 --list"
    exit 1
fi

# Build curl command
CURL_ARGS=(-s -i -w "\n---\nTime: %{time_total}s\n" -X "$METHOD")

if [[ -n "$BODY" ]]; then
    CURL_ARGS+=(-d "$BODY" -H "Content-Type: application/json")
fi

for header in "${HEADERS[@]}"; do
    CURL_ARGS+=(-H "$header")
done

# Execute request
echo "$METHOD $URL"
echo "---"
curl "${CURL_ARGS[@]}" "$URL" 2>&1 | while IFS= read -r line; do
    # Try to format JSON in body
    if echo "$line" | python3 -m json.tool 2>/dev/null; then
        :
    else
        echo "$line"
    fi
done

# Save request if requested
if [[ -n "$SAVE_NAME" ]]; then
    HEADER_JSON=$(printf '%s\n' "${HEADERS[@]}" | jq -R . | jq -s .)
    jq -n \
        --arg method "$METHOD" \
        --arg url "$URL" \
        --arg body "$BODY" \
        --argjson headers "$HEADER_JSON" \
        '{method: $method, url: $url, body: $body, headers: $headers}' \
        > "$REQUESTS_DIR/$SAVE_NAME.json"
    echo "---"
    echo "Saved as: $SAVE_NAME"
fi
