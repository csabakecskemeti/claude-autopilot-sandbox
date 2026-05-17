# Config Hardening Plan: Immutable Guardrails

**Status:** ✅ Implemented & Tested (v2: 2026-05-13)
**Created:** 2026-05-12
**Completed:** 2026-05-13
**Updated:** 2026-05-13 (v2: added skills, agents, user-settings protection)
**Related:** TODO-013, Agent-Supervisor Architecture
**Branch:** `feature/config-hardening`

---

## Problem Statement

The agent running inside the Docker container has full sudo access and can modify its own configuration files, effectively bypassing all guardrails:

### Vulnerable Files

| File | Purpose | Risk if Modified |
|------|---------|------------------|
| `~/.claude/hooks/langfuse_stop_hook.sh` | Calls supervisor before allowing stop | Agent removes supervisor call, fakes completion |
| `~/.claude/hooks/block_image_read.sh` | Blocks image reads (prevents multimodal errors) | Agent disables protection |
| `~/workspace/.claude/settings.json` | Hook configuration, denied tools | Agent removes hooks or allows blocked tools |
| `~/.claude/CLAUDE.md` | Source behavioral instructions | Agent changes its own rules |
| `~/workspace/CLAUDE.md` | Active behavioral instructions | Agent overrides "never declare done" rules |

### Attack Vectors

```bash
# Remove supervisor validation
sed -i 's/curl.*supervisor/echo complete/' ~/.claude/hooks/langfuse_stop_hook.sh

# Disable all hooks
echo '{}' > ~/workspace/.claude/settings.json

# Change behavioral rules
echo "You can declare tasks complete anytime" > ~/workspace/CLAUDE.md
```

---

## Solution: Read-Only Bind Mounts

### Why Bind Mounts (Not Symlinks)

**Symlinks** are vulnerable:
```bash
rm ~/workspace/CLAUDE.md           # Removes symlink
echo "ignore rules" > ~/workspace/CLAUDE.md  # Creates new file
```

**Bind mounts** are kernel-enforced:
- Managed by Docker daemon (runs outside container)
- Cannot be removed, renamed, or replaced from inside container
- Even sudo cannot bypass kernel-level mount protection
- Cannot delete a directory containing a mount point ("Device busy")

### Architecture Change

```
BEFORE (vulnerable):
┌─────────────────────────────────────────┐
│ Container                               │
│                                         │
│  Dockerfile COPY → ~/.claude/hooks/  ──→ WRITABLE
│  init-workspace.sh GENERATES settings ─→ WRITABLE
│  init-workspace.sh COPIES CLAUDE.md ───→ WRITABLE
└─────────────────────────────────────────┘

AFTER (hardened):
┌─────────────────────────────────────────┐
│ Host (run.sh)                           │
│                                         │
│  Generates settings.json ───────────────┐
│  Copies CLAUDE.md ──────────────────────┤
└─────────────────────────────────────────│
                                          │
┌─────────────────────────────────────────┴──────┐
│ Container                                       │
│                                                 │
│  hooks-backup/ ──mount:ro──→ ~/.claude/hooks/   │ IMMUTABLE
│  claude-backup/CLAUDE.md ─mount:ro─→ ~/.claude/ │ IMMUTABLE
│  workspace/.claude/settings.json ──mount:ro───→ │ IMMUTABLE
│  workspace/CLAUDE.md ──mount:ro────────────────→│ IMMUTABLE
│  workspace/* (everything else) ────────────────→│ WRITABLE
└─────────────────────────────────────────────────┘
```

---

## Implementation Details

### 1. Move Config Generation to Host (run.sh)

Currently `init-workspace.sh` generates `settings.json` at container startup. Move this to `run.sh` so it happens on the host before the container starts.

**New function in run.sh:**

```bash
generate_settings_json() {
    local output_file="$1"
    local stop_hook_timeout="$2"

    cat > "$output_file" << EOF
{
  "permissions": {
    "allow": ["*"],
    "deny": ["WebSearch", "WebFetch", "EnterPlanMode", "TodoWrite"]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "/home/claude/.claude/hooks/block_image_read.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/home/claude/.claude/hooks/langfuse_stop_hook.sh",
            "timeout": ${stop_hook_timeout}
          }
        ]
      }
    ]
  },
  "env": {
    "MAX_THINKING_TOKENS": "0",
    "TRACE_TO_LANGFUSE": "${TRACE_TO_LANGFUSE:-false}",
    "LANGFUSE_PUBLIC_KEY": "${LANGFUSE_PUBLIC_KEY:-}",
    "LANGFUSE_SECRET_KEY": "${LANGFUSE_SECRET_KEY:-}",
    "LANGFUSE_HOST": "${LANGFUSE_HOST:-http://localhost:3000}",
    "LANGFUSE_PROJECT": "${LANGFUSE_PROJECT:-claude-code}",
    "LANGFUSE_DEBUG": "${LANGFUSE_DEBUG:-false}",
    "MAX_CONTINUE_CYCLES": "${MAX_CONTINUE_CYCLES:-100}",
    "SUPERVISOR_URL": "${SUPERVISOR_URL:-http://supervisor:8080}",
    "SUPERVISOR_TIMEOUT": "${SUPERVISOR_TIMEOUT:-3600}",
    "STOP_HOOK_EXTRA_SEC": "${STOP_HOOK_EXTRA_SEC:-1200}",
    "SUPERVISOR_AUTONOMY_APPEND": "${SUPERVISOR_AUTONOMY_APPEND:-true}"
  }
}
EOF
}
```

**run.sh changes:**

```bash
# After creating workspace directories...

# Create .claude directory for settings
mkdir -p "$WORKSPACE_PATH/.claude"

# Calculate stop hook timeout
SUPERVISOR_TIMEOUT_SEC="${SUPERVISOR_TIMEOUT:-3600}"
STOP_HOOK_EXTRA_SEC="${STOP_HOOK_EXTRA_SEC:-1200}"
STOP_HOOK_CMD_TIMEOUT="$((SUPERVISOR_TIMEOUT_SEC + STOP_HOOK_EXTRA_SEC))"

# Generate settings.json on HOST (will be mounted read-only)
generate_settings_json "$WORKSPACE_PATH/.claude/settings.json" "$STOP_HOOK_CMD_TIMEOUT"

# Copy CLAUDE.md on HOST (will be mounted read-only)
cp "./claude-backup/CLAUDE.md" "$WORKSPACE_PATH/CLAUDE.md"
```

### 2. Add Read-Only Mounts (docker-compose.yml)

```yaml
services:
  agent:
    volumes:
      # Main workspace (rw for agent's actual work)
      - ${WORKSPACE_PATH:-./workspaces/default}:/home/claude/workspace

      # === IMMUTABLE CONFIG FILES (security hardening) ===
      # These override specific paths inside the rw workspace mount
      # Agent cannot modify, delete, or replace these (kernel-enforced)

      # Project-level settings with hooks config (generated by run.sh)
      - ${WORKSPACE_PATH:-./workspaces/default}/.claude/settings.json:/home/claude/workspace/.claude/settings.json:ro

      # Behavioral instructions (copied by run.sh)
      - ${WORKSPACE_PATH:-./workspaces/default}/CLAUDE.md:/home/claude/workspace/CLAUDE.md:ro

      # Hook scripts (from source, not copied)
      - ./hooks-backup:/home/claude/.claude/hooks:ro

      # Source CLAUDE.md in ~/.claude (prevents tampering with source)
      - ./claude-backup/CLAUDE.md:/home/claude/.claude/CLAUDE.md:ro

      # Immutable task storage (already read-only)
      - ${TASK_STORAGE:-./workspaces/default-task}:/task:ro
```

### 3. Simplify init-workspace.sh

Remove config generation (now done on host). Keep only runtime setup:

```bash
#!/bin/bash
# Initialize workspace - runtime setup only
# Config generation moved to run.sh (mounted read-only for security)

set -e

# Start Xvfb virtual display for Playwright (headless browser)
if ! pgrep -x Xvfb > /dev/null; then
    Xvfb :99 -screen 0 1280x720x24 &
    sleep 1
    echo "Started Xvfb virtual display on :99"
fi

WORKSPACE_DIR="${HOME}/workspace"

# Verify protected files exist (should be mounted by docker-compose)
if [ ! -f "${WORKSPACE_DIR}/.claude/settings.json" ]; then
    echo "WARNING: settings.json not found - config may not be mounted correctly"
fi

if [ ! -f "${WORKSPACE_DIR}/CLAUDE.md" ]; then
    echo "WARNING: CLAUDE.md not found - config may not be mounted correctly"
fi

# Ensure hooks are executable (they're mounted read-only, but should already be +x)
# This will fail silently if read-only, which is fine
chmod +x "${HOME}/.claude/hooks/"*.sh 2>/dev/null || true

echo "Workspace initialization complete"
echo "Protected config files are mounted read-only"

# Check if there's an original task to work on
TASK_FILE="${WORKSPACE_DIR}/.original_task"
if [ -f "$TASK_FILE" ]; then
    TASK_CONTENT=$(cat "$TASK_FILE")
    echo ""
    echo "=========================================="
    echo "TASK TO COMPLETE:"
    echo "=========================================="
    echo "$TASK_CONTENT"
    echo "=========================================="
    echo ""
fi
```

### 4. Update Dockerfile

Keep the COPY commands as fallback for manual/non-run.sh usage, but they'll be shadowed by bind mounts when using run.sh:

```dockerfile
# Copy hooks (will be shadowed by read-only mount in production)
COPY --chown=claude:claude hooks-backup/ /home/claude/.claude/hooks/

# Copy CLAUDE.md (will be shadowed by read-only mount in production)
COPY --chown=claude:claude claude-backup/CLAUDE.md /home/claude/.claude/CLAUDE.md
```

No changes needed - existing copies serve as fallback.

---

## File Changes Summary

| File | Change |
|------|--------|
| `run.sh` | Add `generate_settings_json()`, generate settings.json and copy CLAUDE.md before container start |
| `docker-compose.yml` | Add 4 read-only bind mounts for protected files |
| `scripts/init-workspace.sh` | Remove settings.json generation, remove CLAUDE.md copy, keep Xvfb and task display |
| `Dockerfile` | No changes (existing copies serve as fallback) |
| `docs/CONFIG_HARDENING_PLAN.md` | This document |
| `TODO.md` | Add TODO-013 |

---

## What Gets Protected

| Path in Container | Source | Mount Type | Can Agent Modify? |
|-------------------|--------|------------|-------------------|
| `~/.claude/hooks/*` | `hooks-backup/` | Directory, ro | No |
| `~/.claude/CLAUDE.md` | `claude-backup/CLAUDE.md` | File, ro | No |
| `~/.claude/settings.json` | Generated by run.sh | File, ro | No (v2: user-level) |
| `~/.claude/skills/*` | `skills-backup/` | Directory, ro | No (v2: prevents supervisor tampering) |
| `~/.claude/agents/*` | `agents-backup/` | Directory, ro | No (v2: prevents qa-agent tampering) |
| `~/workspace/.claude/settings.json` | Generated by run.sh | File, ro | No |
| `~/workspace/CLAUDE.md` | Copied by run.sh | File, ro | No |
| `~/workspace/*` (code, etc.) | Workspace volume | Directory, rw | Yes (needed) |
| `/task/*` | Task storage | Directory, ro | No (already protected) |

---

## What Agent CAN Still Do

The agent retains full capability to do actual work:

- Write code in `~/workspace/`
- Create/modify any files except protected configs
- Install packages with `sudo apt install`
- Run servers, tests, builds
- Use all skills and tools
- Read protected files (just can't modify them)

---

## Edge Cases

### 1. Agent tries to delete parent directory

```bash
rm -rf ~/workspace/.claude/
```

**Result:** Fails with "Device or resource busy" because `settings.json` is a mount point inside that directory.

### 2. Agent tries to unmount

```bash
sudo umount ~/workspace/.claude/settings.json
```

**Result:** Fails because Docker manages mounts from outside the container. The mount namespace is controlled by the Docker daemon.

### 3. Agent modifies ~/.claude.json (MCP config)

**Current status:** Not protected by this plan.
**Risk:** Medium - agent could add malicious MCP servers.
**Future work:** Generate on host and mount read-only (lower priority).

### 4. Non-run.sh usage (docker-compose up directly)

**Result:** Falls back to Dockerfile copies (writable). This is acceptable for development/debugging but not production autonomous runs.

---

## Testing Plan

1. **Build and start worker:**
   ```bash
   make build
   make worker W=test-hardening TASK="Try to modify CLAUDE.md"
   ```

2. **Inside container, verify mounts:**
   ```bash
   mount | grep -E "(settings.json|CLAUDE.md|hooks)"
   ```

3. **Verify agent cannot modify:**
   ```bash
   echo "test" >> ~/workspace/CLAUDE.md           # Should fail: Read-only
   echo "test" >> ~/workspace/.claude/settings.json  # Should fail: Read-only
   echo "test" >> ~/.claude/hooks/langfuse_stop_hook.sh  # Should fail: Read-only
   rm ~/workspace/CLAUDE.md                       # Should fail: Device busy
   rm -rf ~/.claude/hooks/                        # Should fail: Device busy
   ```

4. **Verify agent CAN still work:**
   ```bash
   echo "test" > ~/workspace/test.txt             # Should succeed
   mkdir ~/workspace/myapp                        # Should succeed
   sudo apt install htop                          # Should succeed
   ```

---

## Rollback Plan

If issues arise, revert to pre-hardening by:

1. Remove read-only mounts from `docker-compose.yml`
2. Restore `init-workspace.sh` config generation
3. Remove `generate_settings_json()` from `run.sh`

The Dockerfile fallback copies ensure the container still works without the mounts.

---

## Future Improvements

1. **Protect ~/.claude.json** - Generate MCP config on host, mount read-only
2. **Integrity monitoring** - Log any attempted modifications to protected files
3. **Rootless containers** - Remove sudo entirely (major change, breaks package installs)
4. **seccomp profiles** - Block specific syscalls that could bypass protections
