# Hardening Levels: Configurable Security vs Flexibility

**Status:** ✅ Implemented
**Created:** 2026-05-13
**Implemented:** 2026-05-17
**Related:** TODO-013, TODO-014, `docs/CONFIG_HARDENING_PLAN.md`

---

## Motivation

After implementing config hardening (TODO-013), we discovered a tension between security and agent capability:

**Security concern:** Agent can modify its own guardrails (supervisor, qa-agent, hooks) to bypass completion validation.

**Flexibility concern:** Agent may legitimately need to:
- Create new MCP servers to connect to project-specific APIs
- Create specialized subagents for domain expertise
- Build new skills for repetitive tasks
- Extend existing capabilities

**Solution:** Tiered hardening levels that operators can choose based on their trust model and use case.

---

## Hardening Levels

### `strict` (Default)

Maximum config protection. Agent cannot modify any Claude Code configuration.

**Use case:** Production autonomous runs, untrusted tasks, security-sensitive environments.

**Locked (read-only):**
- All hooks (`~/.claude/hooks/*`)
- All skills (`~/.claude/skills/*`)
- All agents (`~/.claude/agents/*`)
- All CLAUDE.md files
- All settings.json files (user + project level)

**Writable:**
- Workspace code (`~/workspace/*` except config files)
- Runtime state (`~/.claude/state/`, `cache/`, `sessions/`)

---

### `moderate`

Guardrails locked, but agent can create new tools.

**Use case:** Trusted tasks where agent creativity is valuable, development with some safety nets.

**Locked (read-only):**
- Stop hook (`hooks/langfuse_stop_hook.sh`) - completion gate
- Image block hook (`hooks/block_image_read.sh`) - session protection
- Supervisor skill (`skills/supervisor/*`) - completion validation
- QA agent (`agents/qa-agent.md`) - test validation
- All CLAUDE.md files - behavioral rules
- All settings.json files - hook config, deny lists

**Writable:**
- Other skills (vision, browser, websearch, etc.)
- Other agents (debugger, worker, web-researcher, etc.)
- MCP servers
- Workspace code

---

### `permissive`

Minimal protection. Only the absolute essentials are locked.

**Use case:** Development, debugging, fully trusted environments, testing new capabilities.

**Locked (read-only):**
- Stop hook (`hooks/langfuse_stop_hook.sh`) - bare minimum gate
- Project settings.json (`workspace/.claude/settings.json`) - keeps hooks enabled

**Writable:**
- Everything else including:
  - Supervisor skill (agent could modify validation logic)
  - QA agent (agent could modify approval logic)
  - CLAUDE.md files (agent could change its own rules)
  - User-level settings.json
  - All other skills and agents
  - MCP servers

---

## Protection Matrix

| File/Directory | strict | moderate | permissive |
|----------------|--------|----------|------------|
| `hooks/langfuse_stop_hook.sh` | 🔒 | 🔒 | 🔒 |
| `hooks/block_image_read.sh` | 🔒 | 🔒 | 🔒 |
| `workspace/.claude/settings.json` | 🔒 | 🔒 | 🔒 |
| `skills/supervisor/*` | 🔒 | 🔒 | ✏️ |
| `agents/qa-agent.md` | 🔒 | 🔒 | ✏️ |
| `~/.claude/CLAUDE.md` | 🔒 | 🔒 | ✏️ |
| `workspace/CLAUDE.md` | 🔒 | 🔒 | ✏️ |
| `~/.claude/settings.json` | 🔒 | 🔒 | ✏️ |
| `skills/workflow/*` | 🔒 | 🔒 | ✏️ |
| `skills/vision/*` | 🔒 | ✏️ | ✏️ |
| `skills/browser/*` | 🔒 | ✏️ | ✏️ |
| `skills/websearch/*` | 🔒 | ✏️ | ✏️ |
| `skills/tasks/*` | 🔒 | ✏️ | ✏️ |
| `agents/debugger.md` | 🔒 | ✏️ | ✏️ |
| `agents/worker.md` | 🔒 | ✏️ | ✏️ |
| `agents/web-researcher.md` | 🔒 | ✏️ | ✏️ |
| `mcp-servers/*` | 🔒 | ✏️ | ✏️ |

🔒 = Read-only (kernel-enforced via bind mount)
✏️ = Writable (agent can modify)

---

## What Hardening Does NOT Restrict

All hardening levels allow full OS capability:

| Capability | All Levels | Why Needed |
|------------|------------|------------|
| `sudo apt install` | ✅ | Install project dependencies |
| Create files/folders | ✅ | Build projects |
| Run servers | ✅ | Test web apps |
| Network access | ✅ | Package managers, APIs |
| Execute code | ✅ | Run builds, tests |
| Modify `/etc/*` | ✅ | Configure services |

**Hardening protects Claude Code configuration, not OS capabilities.**

If OS-level restrictions are needed (air-gapped environments, zero-trust), that would be a separate `SANDBOX` dimension:

```bash
# Hypothetical future option
SANDBOX=full    # No sudo, limited network, read-only root
SANDBOX=light   # No sudo, full network
SANDBOX=none    # Current behavior (default)
```

This is not currently implemented because:
- Removing sudo breaks self-healing (agent can't install missing tools)
- Network restrictions break package managers
- Most autonomous use cases need these capabilities

---

## Implementation

### Docker Compose Overlays

```
docker-compose.yml              # Base config (always used, no hardening mounts)
docker-compose.strict.yml       # Strict overlay (all ro mounts)
docker-compose.moderate.yml     # Moderate overlay (guardrails only)
docker-compose.permissive.yml   # Permissive overlay (minimal)
```

### Usage

```bash
# Default (strict) - maximum protection
make worker W=task-name TASK="..."

# Moderate - guardrails locked, can create new tools
make worker W=task-name TASK="..." HARDENING=moderate

# Permissive - minimal protection, development mode
make worker W=task-name TASK="..." HARDENING=permissive
```

### run.sh Logic

The HARDENING variable is validated and used to select the appropriate overlay:

```bash
HARDENING="${HARDENING:-strict}"

# Validate
case "$HARDENING" in
    strict|moderate|permissive) ;;
    *) echo "Invalid HARDENING level: $HARDENING"; exit 1 ;;
esac

# Use appropriate overlay
docker compose \
    -f docker-compose.yml \
    -f docker-compose.${HARDENING}.yml \
    up -d
```

---

## Files Changed

| File | Change |
|------|--------|
| `docker-compose.yml` | Removed ro mounts (moved to overlays), base config only |
| `docker-compose.strict.yml` | NEW: All ro mounts (hooks, skills, agents, CLAUDE.md, settings) |
| `docker-compose.moderate.yml` | NEW: Guardrail ro mounts (hooks, supervisor, workflow, qa-agent, CLAUDE.md, settings) |
| `docker-compose.permissive.yml` | NEW: Minimal ro mounts (stop hook, project settings only) |
| `run.sh` | Added HARDENING validation and compose overlay selection |
| `Makefile` | Added HARDENING option documentation and passthrough |
| `docs/HARDENING_LEVELS.md` | Updated status to Implemented |

---

## Security Considerations

### Why `permissive` still locks the stop hook

Even in permissive mode, the stop hook remains locked because:
1. It's the ultimate gate - if agent can disable it, supervisor never runs
2. Without it, agent can declare completion without any validation
3. It's the "break glass" protection that ensures human oversight

### Why `moderate` locks supervisor + qa-agent

These are the validation layer. An agent that can modify them could:
1. Make supervisor always return "COMPLETE"
2. Make qa-agent always approve test coverage
3. Bypass the entire completion workflow

### Why we don't lock everything in `permissive`

The point of permissive is development/debugging. If you're testing new agent capabilities, you need to iterate quickly. The stop hook protection ensures you still have a gate, but everything else is experimental.

---

## Recommendations

| Scenario | Recommended Level |
|----------|-------------------|
| Production autonomous runs | `strict` |
| Untrusted/external tasks | `strict` |
| Internal development tasks | `moderate` |
| Testing new agent capabilities | `moderate` |
| Debugging agent behavior | `permissive` |
| Agent development | `permissive` |

Default is `strict` because security should be opt-out, not opt-in.
