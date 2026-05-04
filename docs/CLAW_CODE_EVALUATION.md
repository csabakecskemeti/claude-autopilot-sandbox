# Claw Code Evaluation for Local LLM Agent Harness

**Repository**: https://github.com/ultraworkers/claw-code
**Evaluation Date**: 2026-04-07
**Purpose**: Assess viability as Claude Code alternative for local LLM autonomous agents

---

## Executive Summary

**Verdict: NOT READY for our use case**

Claw Code is a Rust clean-room implementation of Claude Code. While it has impressive features and local LLM support, **hooks are NOT fully implemented** - config is parsed but runtime execution is missing. This is a blocker for our supervisor pattern.

---

## Feature Parity Analysis

### What's Implemented ✅

| Feature | Status | Notes |
|---------|--------|-------|
| Provider flows (Anthropic/OpenAI) | ✅ | Streaming support |
| Local LLM support | ✅ | Ollama, OpenAI-compatible endpoints |
| OAuth authentication | ✅ | `claw login` command |
| Interactive REPL | ✅ | rustyline-based |
| Tool system | ✅ | bash, file ops, search, web |
| Sub-agent surfaces | ✅ | `copilot_swe_agent_use_subagents` flag |
| Project memory (CLAUDE.md) | ✅ | Supported |
| Permission system | ✅ | Multiple modes |
| MCP server lifecycle | ✅ | Bridge to external servers |
| Session persistence | ✅ | Resume capability |
| Git integration | ✅ | Built-in |
| Plugin management | ✅ | Install/enable/disable |
| Skills inventory | ✅ | Supported |
| Slash commands | ✅ | `/hooks`, `/config`, etc. |

### What's Missing/Limited ⚠️

| Feature | Status | Impact |
|---------|--------|--------|
| **Hook EXECUTION** | ❌ CONFIG ONLY | **BLOCKER** - our supervisor relies on Stop hook |
| Interactive prompts (AskUserQuestion) | ⚠️ Pending | Returns pending, no real UI |
| Background execution | ⚠️ No worker fleet | No real background scheduler |
| Bash validation depth | ⚠️ 1/18 modules | Limited vs upstream |
| Session compaction | ⚠️ Incomplete | Token counting gaps |
| Output truncation | ⚠️ Unimplemented | Large responses may fail |

---

## Critical Issue: Hooks Not Functional

From [PARITY.md](https://github.com/ultraworkers/claw-code/blob/main/PARITY.md) and code analysis:

> "Hook config is parsed and merged in `rust/crates/runtime/src/config.rs`.
> **However, there is no actual hook execution pipeline** in `rust/crates/runtime/src/conversation.rs`.
> No PreToolUse/PostToolUse mutation/deny/rewrite/result-hook behavior.
> **Status: config-only; runtime behavior missing.**"

### What This Means

```
Claude Code (current):
  Agent stops → Stop hook executes → Supervisor validates → Feedback injected

Claw Code (current):
  Agent stops → Hook config exists but IGNORED → No supervisor call → Agent exits
```

**Our entire supervisor pattern depends on the Stop hook actually running.**

### Hook Events in Claude Code (for reference)

Claude Code supports 12 hook events:
1. `PreToolUse` - Before tool execution
2. `PostToolUse` - After tool execution
3. `Stop` - When agent tries to stop ← **WE NEED THIS**
4. `SubagentStart` - When subagent begins
5. `SubagentStop` - When subagent ends
6. `PreCompact` - Before context compaction
7. `SessionStart` - Session begins
8. `SessionEnd` - Session ends
9. `PermissionRequest` - Permission prompt
10. `PostToolUseFailure` - Tool execution failed
11. `Notification` - General notifications
12. (more...)

Claw Code: **Config parsed, runtime execution NOT implemented**

---

## Local LLM Support

**This part is good!**

Claw Code supports local LLMs via:

```bash
# Ollama
export OPENAI_BASE_URL="http://127.0.0.1:11434/v1"
export OPENAI_API_KEY="ollama"

# Any OpenAI-compatible endpoint
export OPENAI_BASE_URL="http://localhost:8080/v1"
export OPENAI_API_KEY="local"

# LM Studio (Anthropic-compatible)
export ANTHROPIC_BASE_URL="http://localhost:1234"
export ANTHROPIC_AUTH_TOKEN="lmstudio"
```

Model names passed verbatim, enabling any local model.

---

## Architecture

Nine-crate Rust workspace (~20,000 lines):

```
rust/crates/
├── api/          # Provider clients, SSE streaming
├── commands/     # Slash-command registry
├── runtime/      # ConversationRuntime, config, permissions
├── tools/        # Built-in tool execution
├── plugins/      # Plugin lifecycle
├── telemetry/    # Session tracing
└── mock-anthropic-service/  # Local testing
```

**Pros:**
- Clean Rust implementation
- Modular crate structure
- Good test infrastructure

**Cons:**
- Hooks not wired up
- Some features are "registry-backed approximations"

---

## Python Hooks Subsystem

The `src/hooks/` directory contains only:

```python
# __init__.py
# "Python package placeholder for the archived `hooks` subsystem."
```

The Python hooks have been **archived** - not functional.

---

## Comparison Table

| Capability | Claude Code | Claw Code | Impact |
|------------|-------------|-----------|--------|
| Stop hook execution | ✅ Full | ❌ Config only | **BLOCKER** |
| PreToolUse/PostToolUse | ✅ Full | ❌ Config only | Can't add guardrails |
| Local LLM support | ⚠️ Via env vars | ✅ Native | Claw better here |
| Subagent support | ✅ Full | ✅ Supported | Parity |
| MCP integration | ✅ Full | ✅ Bridge | Parity |
| Session persistence | ✅ Full | ✅ Full | Parity |
| Open source | ❌ Closed | ✅ MIT | Claw wins |
| Customizability | ⚠️ Limited | ✅ Full source | Claw wins |

---

## Recommendation

### Short Term: Stay with Claude Code

Our supervisor pattern requires Stop hooks. Until Claw Code implements hook execution, it's not viable for our use case.

### Medium Term: Watch Claw Code Development

The project is active (176k stars, frequent commits). Hook execution may be added soon. Monitor:
- https://github.com/ultraworkers/claw-code/issues (for hook-related issues)
- `rust/crates/runtime/src/conversation.rs` (for hook execution PRs)

### Long Term: Consider Contributing

If we want to accelerate hook support in Claw Code, we could:
1. Fork and implement hook execution ourselves
2. Submit PR upstream
3. Gain full control over the agent harness

**Estimated effort**: Medium-High (need to understand Rust codebase, implement hook dispatch in conversation runtime)

---

## If We Wanted to Fork & Fix

The hook execution would need to be added to:

```
rust/crates/runtime/src/conversation.rs
```

Specifically:
1. Load hook config (already done)
2. At Stop points, execute registered Stop hooks
3. Parse hook output JSON (`{decision: "block", reason: "..."}`)
4. If blocked, inject reason into context and continue
5. Same pattern for PreToolUse, PostToolUse, etc.

**Reference**: Our current `langfuse_stop_hook.sh` shows exactly what output format is expected.

---

## Alternative Approaches

If we don't want to wait for Claw Code hooks:

1. **Wrapper approach**: Run Claw Code, wrap with external process that intercepts exit
   - Hacky, unreliable

2. **MCP-based supervisor**: Instead of Stop hook, supervisor polls via MCP
   - Requires MCP implementation
   - More complex

3. **Stay with Claude Code**: Current approach works
   - Closed source, but functional
   - Hooks work today

---

## Sources

- [Claw Code Repository](https://github.com/ultraworkers/claw-code)
- [PARITY.md - Feature Status](https://github.com/ultraworkers/claw-code/blob/main/PARITY.md)
- [Rust README](https://github.com/ultraworkers/claw-code/blob/main/rust/README.md)
- [USAGE.md - Configuration](https://github.com/ultraworkers/claw-code/blob/main/USAGE.md)
- [src/hooks/__init__.py](https://github.com/ultraworkers/claw-code/blob/main/src/hooks/__init__.py)
