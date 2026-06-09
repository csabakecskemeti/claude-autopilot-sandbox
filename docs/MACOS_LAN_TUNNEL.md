# macOS Docker LAN Connectivity Guide

## Problem

Docker Desktop on macOS cannot reach LAN devices (192.168.x.x) from inside containers. This is a **macOS limitation**, not a Docker configuration issue.

## Solution: Automatic socat Tunnels

The project automatically detects LAN hosts and creates socat tunnels when starting workers on macOS.

### Quick Start

1. **Install socat** (one-time setup):
```bash
make install-socat
```

2. **Configure .env with actual LAN hostnames**:
```bash
# Use the ACTUAL hostname/IP of your LLM server
LLM_HOST=spark-db71.local  # or 192.168.7.103
LLM_PORT=4000

# Vision model (can be same host, different port)
VISION_HOST=spark-db71.local
VISION_PORT=11234

# For litellm/vllm, use AUTH_TOKEN
LLM_AUTH_TOKEN=vllm
LLM_MODEL=Qwen/Qwen3.6-35B-A3B-FP8
```

3. **Start worker** (tunnels created automatically):
```bash
make worker
```

That's it! The `run.sh` script will:
- Detect that `spark-db71.local` is a LAN host
- Create socat tunnels for ports 4000 and 11234
- Override environment variables to use `host.docker.internal`
- Container connects to tunnel automatically

### Manual Tunnel Management

```bash
# Start tunnels based on .env
make tunnel

# Show tunnel status
make tunnel-status

# Test tunnel connectivity
make tunnel-test PORT=4000

# Stop all tunnels
make tunnel-stop
```

### How It Works

1. **Auto-detection**: `run.sh` scans .env for LAN hosts:
   - IP patterns: `192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`
   - mDNS hostnames: `*.local`
   - Excludes: `localhost`, `127.0.0.1`, `host.docker.internal`

2. **Tunnel creation**: For each LAN host:port, creates:
```bash
socat TCP-LISTEN:4000,fork,reuseaddr TCP:spark-db71.local:4000
```

3. **Environment override**: In container:
```bash
LLM_HOST=host.docker.internal  # Overridden from spark-db71.local
LLM_PORT=4000                  # Unchanged
```

4. **Connection path**:
```
Container → host.docker.internal:4000 → Mac localhost:4000 → socat → spark-db71.local:4000
```

## Advanced Usage

### Multiple Workers with Different .env Files

```bash
# Start worker with specific env file
ENV_FILE=.env-dgx2 make worker

# Tunnels are created based on the specified .env file
```

### Testing

```bash
# Run full test suite (includes tunnel check on macOS)
make test

# Test specific tunnel port
make tunnel-test PORT=4000
make tunnel-test PORT=11234
```

### Persistent Tunnel (Optional)

For tunnels that persist across reboots, create a LaunchAgent:

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

Note: `run.sh` will detect existing tunnels and reuse them instead of creating duplicates.

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

### Multiple Ports on Same Host

The automatic tunnel system handles same-host, different-port scenarios:

```bash
# This works correctly - creates TWO tunnels
LLM_HOST=spark-db71.local
LLM_PORT=4000

VISION_HOST=spark-db71.local
VISION_PORT=11234
```

Creates:
- `localhost:4000 → spark-db71.local:4000`
- `localhost:11234 → spark-db71.local:11234`

### Tunnel Management

Tunnels are tracked by PID in `.tunnel-pids`. The script ensures:
- No duplicate tunnels for same port
- Clean shutdown with `make tunnel-stop`
- Status checking with `make tunnel-status`
- Automatic cleanup on worker start/stop

### Troubleshooting

If containers can't reach LLM server:

1. **Check tunnel status**:
```bash
make tunnel-status
```

2. **Verify socat is installed**:
```bash
which socat
```

3. **Test tunnel connectivity**:
```bash
make tunnel-test PORT=4000
```

4. **Check .env configuration**:
```bash
# Should use actual LAN hostname
grep LLM_HOST .env
# Not: LLM_HOST=host.docker.internal (old approach)
# But: LLM_HOST=spark-db71.local (correct)
```

5. **Restart tunnel**:
```bash
make tunnel-stop
make tunnel
```
