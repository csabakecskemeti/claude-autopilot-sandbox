# macOS Docker LAN Connectivity Guide

## Problem

Docker Desktop on macOS cannot reach LAN devices (192.168.x.x) from inside containers. This is a **macOS limitation**, not a Docker configuration issue.

## Solution: socat Tunnel

Use socat to create a tunnel from Mac localhost to the remote LLM server.

### 1. Install socat

```bash
brew install socat
```

### 2. Start the Tunnel

```bash
# For litellm/vllm on port 4000
socat TCP-LISTEN:4000,fork,reuseaddr TCP:spark-db71.local:4000 &

# For LM Studio on port 11234
socat TCP-LISTEN:11234,fork,reuseaddr TCP:spark-db71.local:11234 &
```

### 3. Configure .env

```bash
# Use host.docker.internal to reach the tunnel on Mac host
LLM_HOST=host.docker.internal
LLM_PORT=4000  # or 11234 for LM Studio

# For litellm/vllm, use AUTH_TOKEN
LLM_AUTH_TOKEN=vllm
LLM_MODEL=Qwen/Qwen3.6-35B-A3B-FP8
```

### 4. Test the Tunnel

```bash
# From Mac host
curl http://localhost:4000/v1/models

# From inside container
docker run --rm alpine wget -O- http://host.docker.internal:4000/v1/models
```

## Persistent Tunnel (Optional)

Create a LaunchAgent to auto-start the tunnel on login:

```xml
<!-- ~/Library/LaunchAgents/com.user.socat-llm-tunnel.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.socat-llm-tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/socat</string>
        <string>TCP-LISTEN:4000,fork,reuseaddr</string>
        <string>TCP:spark-db71.local:4000</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.user.socat-llm-tunnel.plist
```

## Important Notes

### Authentication: AUTH_TOKEN vs API_KEY

- **`ANTHROPIC_AUTH_TOKEN`** = Bearer token for gateways/proxies (litellm, vllm)
- **`ANTHROPIC_API_KEY`** = x-api-key for direct Anthropic API (triggers confirmation prompts)

Always use `ANTHROPIC_AUTH_TOKEN` when connecting to litellm or other proxies.

### Why This Is Required

- Docker Desktop on macOS runs in a VM
- The VM cannot route to LAN devices on 192.168.x.x networks
- `host.docker.internal` resolves to Mac host, not LAN devices
- socat bridges Mac localhost → LAN device

### Services That Don't Need Tunnel

Services running on the same Mac (Langfuse, SearXNG) can use `host.docker.internal` directly without a tunnel.
