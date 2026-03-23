#!/bin/bash
# Vision skill - analyze images using vision AI model
# All requests are logged to ~/workspace/.vision_logs/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Configuration from environment
VISION_API_URL="${VISION_API_URL:-http://192.168.7.103:11234}"
VISION_API_TOKEN="${VISION_API_TOKEN:-lmstudio}"
VISION_MODEL="${VISION_MODEL:-qwen/qwen3-vl-4b}"

# Debug: Print config on startup
echo "Vision config: API=$VISION_API_URL MODEL=$VISION_MODEL" >&2

# Directories
SCREENSHOT_DIR="/tmp/vision_screenshots"
LOG_DIR="${HOME}/workspace/.vision_logs"
mkdir -p "$SCREENSHOT_DIR" "$LOG_DIR"

usage() {
    cat << EOF
Usage: $0 <command> <image_or_url> [prompt]

Commands:
  analyze <image_or_url> <prompt>   Analyze image file OR screenshot URL
  ocr <image_or_url>                Extract text from image/screenshot
  verify <image_or_url> <expected>  Verify image/UI matches expected description
  logs                              Show recent vision logs

The <image_or_url> can be:
  - Local file path: ./image.png, /path/to/image.jpg
  - Web URL: http://localhost:5000, https://example.com
  - Image URL: https://example.com/image.png

All requests are logged to: ~/workspace/.vision_logs/

Examples:
  $0 analyze ./screenshot.png "What is in this image?"
  $0 analyze http://localhost:5000 "Describe this web page"
  $0 ocr ./document.png
  $0 verify http://localhost:5000 "Should show a todo list"
  $0 logs
EOF
    exit 1
}

# Log a vision request
log_request() {
    local command="$1"
    local input="$2"
    local prompt="$3"
    local image_path="$4"
    local response="$5"

    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local log_entry="${LOG_DIR}/${timestamp}_${command}"

    # Copy image to log directory
    if [ -f "$image_path" ]; then
        cp "$image_path" "${log_entry}.png"
    fi

    # Write log file
    cat > "${log_entry}.md" << EOF
# Vision Request: ${command}
**Time:** $(date)
**Input:** ${input}
**Prompt:** ${prompt}
**Image:** ${log_entry}.png

## Response
${response}
EOF

    echo "Logged to: ${log_entry}.md" >&2
}

# Check if vision model is configured
check_config() {
    if [ -z "$VISION_MODEL" ]; then
        echo "Error: VISION_MODEL not configured"
        exit 1
    fi
}

# Encode image to base64
encode_image() {
    local image_path="$1"
    if [ ! -f "$image_path" ]; then
        echo "Error: Image not found: $image_path" >&2
        exit 1
    fi
    base64 -w 0 "$image_path" 2>/dev/null || base64 -i "$image_path" | tr -d '\n'
}

# Check if input is a URL
is_url() {
    local input="$1"
    [[ "$input" =~ ^https?:// ]]
}

# Check if URL points to an image file
is_image_url() {
    local url="$1"
    [[ "$url" =~ \.(png|jpg|jpeg|gif|webp|bmp|PNG|JPG|JPEG|GIF|WEBP|BMP)(\?.*)?$ ]]
}

# Download image from URL
download_image() {
    local url="$1"
    local output_path="$2"
    curl -s -L -o "$output_path" "$url"
}

# Take screenshot using playwright
take_screenshot() {
    local url="$1"
    local output_path="$2"

    # Check if playwright is available
    if ! python3 -c "from playwright.sync_api import sync_playwright" 2>/dev/null; then
        echo "Installing playwright..." >&2
        pip install playwright -q
        playwright install chromium -q 2>/dev/null || true
    fi

    # Take screenshot using playwright
    python3 << PYTHON
import sys
try:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={'width': 1280, 'height': 720})
        page.goto('${url}', wait_until='networkidle', timeout=15000)
        page.screenshot(path='${output_path}')
        browser.close()
        print('Screenshot saved', file=sys.stderr)
except Exception as e:
    print(f'Screenshot failed: {e}', file=sys.stderr)
    sys.exit(1)
PYTHON
}

# Get image (either from file, image URL, or webpage screenshot)
get_image() {
    local input="$1"
    local temp_path="${SCREENSHOT_DIR}/image_$(date +%s).png"

    if is_url "$input"; then
        if is_image_url "$input"; then
            echo "Downloading image from: $input" >&2
            download_image "$input" "$temp_path"
        else
            echo "Taking screenshot of: $input" >&2
            take_screenshot "$input" "$temp_path"
        fi
        echo "$temp_path"
    else
        # It's a local file
        if [ ! -f "$input" ]; then
            echo "Error: File not found: $input" >&2
            exit 1
        fi
        echo "$input"
    fi
}

# Call vision API
call_vision_api() {
    local image_base64="$1"
    local prompt="$2"

    # Debug: show what model we're using
    echo "DEBUG: VISION_MODEL='$VISION_MODEL'" >&2
    echo "DEBUG: VISION_API_URL='$VISION_API_URL'" >&2

    # Escape prompt for JSON (handle newlines, quotes, backslashes)
    local escaped_prompt=$(printf '%s' "$prompt" | jq -Rs .)

    # Build JSON payload using jq for proper escaping
    local payload=$(jq -n \
        --arg model "$VISION_MODEL" \
        --argjson prompt "$escaped_prompt" \
        --arg image_data "data:image/png;base64,${image_base64}" \
        '{
            model: $model,
            messages: [{
                role: "user",
                content: [
                    { type: "text", text: $prompt },
                    { type: "image_url", image_url: { url: $image_data } }
                ]
            }],
            temperature: 0.1,
            max_tokens: 2048
        }')

    # Debug: show payload structure (without the huge base64 image)
    echo "DEBUG: Payload model field: $(echo "$payload" | jq -r '.model')" >&2

    local response=$(curl -s -X POST "${VISION_API_URL}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${VISION_API_TOKEN}" \
        -d "$payload")

    # Extract content from response
    echo "$response" | jq -r '.choices[0].message.content // .error.message // "Error: Could not parse response"'
}

# Commands
cmd_analyze() {
    local input="$1"
    local prompt="${2:-Describe this image in detail.}"

    check_config

    local image_path=$(get_image "$input")
    echo "Analyzing..." >&2
    local image_base64=$(encode_image "$image_path")
    local response=$(call_vision_api "$image_base64" "$prompt")

    # Log the request
    log_request "analyze" "$input" "$prompt" "$image_path" "$response"

    echo "$response"
}

cmd_ocr() {
    local input="$1"
    local prompt="Extract and return ALL text visible in this image. Return only the text content, preserving layout where possible."

    check_config

    local image_path=$(get_image "$input")
    echo "Extracting text..." >&2
    local image_base64=$(encode_image "$image_path")
    local response=$(call_vision_api "$image_base64" "$prompt")

    # Log the request
    log_request "ocr" "$input" "$prompt" "$image_path" "$response"

    echo "$response"
}

cmd_verify() {
    local input="$1"
    local expected="$2"

    check_config

    if [ -z "$expected" ]; then
        echo "Error: Must provide expected description"
        exit 1
    fi

    local image_path=$(get_image "$input")
    echo "Verifying..." >&2
    local image_base64=$(encode_image "$image_path")

    local prompt="You are verifying a UI/image. Check if it matches the expected description.

EXPECTED: ${expected}

Analyze the image and respond with:
1. PASS or FAIL
2. What you actually see
3. If FAIL, what is missing or different

Be specific and helpful."

    local response=$(call_vision_api "$image_base64" "$prompt")

    # Log the request
    log_request "verify" "$input" "$expected" "$image_path" "$response"

    echo "$response"
}

cmd_logs() {
    echo "=== Recent Vision Logs ==="
    echo "Location: $LOG_DIR"
    echo ""
    ls -lt "$LOG_DIR"/*.md 2>/dev/null | head -10 || echo "No logs yet"
    echo ""
    echo "To view a log: cat $LOG_DIR/<filename>.md"
    echo "To view image: open $LOG_DIR/<filename>.png"
}

# Main
case "${1:-}" in
    analyze)
        [ -z "$2" ] && usage
        cmd_analyze "$2" "$3"
        ;;
    ocr)
        [ -z "$2" ] && usage
        cmd_ocr "$2"
        ;;
    verify)
        [ -z "$2" ] && usage
        cmd_verify "$2" "$3"
        ;;
    logs)
        cmd_logs
        ;;
    *)
        usage
        ;;
esac
