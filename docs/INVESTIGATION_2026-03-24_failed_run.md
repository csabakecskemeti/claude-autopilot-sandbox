# Investigation Report: Failed Agent Run

**Date:** 2026-03-24
**Session ID:** 3d5917c0-89e9-4f69-a039-9ffc75a0d5ee
**Trace ID:** 01c6688c-d3e5-4f65-864a-e2d9a517e28a
**Model:** qwen/qwen3.5-35b-a3b
**Duration:** ~18-21 minutes
**Workspace:** test_20260324-752pm
**Comparison:** Successful run from test_20260323-101pm (1hr 18min)

---

## Executive Summary

The agent produced code for 18 minutes but stopped without:
- Testing the code
- Using `/vision verify` for UI validation
- Calling `/supervisor` for completion

**Root causes identified:**
1. **Auto-continue false positive** - Hook detected "MISSION COMPLETE" in game code, not actual completion
2. **LLM garbled output** - After large Edit operation, LLM output malformed text
3. **CLAUDE.md differences** - Failed run has extra instructions that may confuse local LLM

---

## Timeline

| Time | Event |
|------|-------|
| 15:03 | Session started, read docs/example_tasks/GAME_TASK.md |
| 15:03 | Created directory structure |
| 15:04 | Wrote index.html (63 lines) |
| 15:05 | Wrote style.css (170 lines) |
| 15:06 | Attempted heredoc for game.js - **FAILED** |
| 15:06 | Wrote game.js with Write tool (237 lines) |
| 15:10 | Multiple Edit operations to expand game.js |
| 15:24 | Large Edit operation (259 lines added) |
| 15:24 | **LLM output garbled text: `"\n}\n\n}\n</tool_call>`** |
| 15:24 | Stop hook invoked |
| 15:25 | **Auto-continue detected "MISSION COMPLETE" - FALSE POSITIVE** |
| 15:25 | Session ended |

---

## Root Cause Analysis

### Issue 1: Auto-Continue False Positive

**The bug:**
```bash
# In check_auto_continue():
if grep -qi "ALL COMPLETE\|ALL TASKS COMPLETE\|TASK COMPLETE\|MISSION COMPLETE" "$transcript_path"
```

This grep matches **ANY occurrence** of these strings in the transcript - including code content!

**What was matched:**
```javascript
// In the game code written to game.js:
title.textContent = 'MISSION COMPLETE!';
```

**Hook log:**
```
Auto-continue check: is_complete=true
Task completed - no auto-continue needed
```

**Impact:** Auto-continue didn't trigger even though task was incomplete.

---

### Issue 2: LLM Garbled Output

**Last 3 assistant messages:**
```json
[{"type":"thinking","thinking":"\n\n"}]      // Empty thinking
[{"type":"text","text":"\n\n"}]              // Empty text
[{"type":"text","text":"\"\n}\n\n}\n</tool_call>"}]  // GARBLED
```

The LLM output `"\n}\n\n}\n</tool_call>` as plain text instead of a proper tool call or response. This appears to be:
- Trailing content from a malformed tool call attempt
- The LLM "lost track" of its output format

**Triggered by:** Large Edit operation with ~15KB of JavaScript code in `new_string`

---

### Issue 3: Earlier Heredoc Failure

```bash
Bash(cat > /home/claude/workspace/platformer-game/js/game.js << 'GAMEJS')
⎿  /bin/bash: line 1: warning: here-document at line 1 delimited by end-of-file (wanted `GAMEJS')
```

The heredoc was truncated. The LLM then tried to use Write tool, but the `GAMEJS` delimiter appeared in subsequent Edit operations:

```javascript
// End of old_string and new_string in Edit calls:
        this.updateUI();\n    }\nGAMEJS\n}\n"
```

**Impact:** Corrupted file content may have confused subsequent operations.

---

### Issue 4: CLAUDE.md Differences

**Successful run (test_20260323-101pm):**
- Simpler CLAUDE.md
- NO "Native Tools vs Skills" section
- NO "IMPORTANT: Vision is a BASH SKILL" section

**Failed run (test_20260324-752pm):**
- Has "Native Tools vs Skills" section (5 lines added)
- Has "IMPORTANT: Vision is a BASH SKILL" section (4 lines added)

**Diff:**
```diff
+ **Native Tools vs Skills:**
+ - **Native tools** (Read, Write, Edit, Bash, Glob, Grep) → Call directly
+ - **Skills** (/tasks, /vision, /fetch, etc.) → Call via Bash: `~/.claude/skills/<name>/<script>`
+ - **MCP tools** (mcp__playwright__*) → Call directly with mcp__ prefix
+
+ **IMPORTANT:** Vision is a BASH SKILL, not a native tool. Call it via Bash:
+ Do NOT try to call `Vision` as a tool directly - it will fail with "No such tool".
```

**Hypothesis:** The extra instructions may be confusing the local LLM or diluting focus on the core workflow.

---

## Behavior Comparison

| Aspect | Successful Run (Mar 23) | Failed Run (Mar 24) |
|--------|------------------------|---------------------|
| Duration | 1hr 18min | 18min |
| Vision verify | ✅ Used (logs exist) | ❌ Never called |
| Supervisor | ✅ Called | ❌ Never called |
| Testing | ✅ Yes | ❌ No |
| CLAUDE.md version | Simple | Has extra sections |
| Final output | Working game | Incomplete code |
| Garbled LLM output | Unknown | Yes |

---

## Evidence

### Hook Log (Failed Run)
```
2026-03-24 15:24:47 [INFO] Received stdin (340 bytes): {...,"last_assistant_message":"\"\n}\n\n}\n</tool_call>"}
2026-03-24 15:25:15 [INFO] Auto-continue check: is_complete=true
2026-03-24 15:25:15 [INFO] Task completed - no auto-continue needed
```

### Vision Logs
- **Successful run:** 11 files in `.vision_logs/` with screenshots and analysis
- **Failed run:** Empty directory (no vision calls)

### Files Produced
**Failed run produced:**
- `platformer-game/index.html` - ✅ Created
- `platformer-game/css/style.css` - ✅ Created
- `platformer-game/js/game.js` - ⚠️ Incomplete (745 lines but truncated)
- No testing, no verification

---

## Recommendations

### Immediate Fix: Auto-Continue Detection

The grep must only match completion signals from supervisor, not code content:

```bash
# BAD: Matches anywhere in transcript
grep -qi "MISSION COMPLETE" "$transcript_path"

# BETTER: Only match supervisor output
grep -q '\.claude/skills/supervisor.*ALL COMPLETE' "$transcript_path"

# OR: Use specific marker
grep -q '\[SUPERVISOR\] ALL COMPLETE' "$transcript_path"
```

### Consider: Revert CLAUDE.md

The successful run used a simpler CLAUDE.md without:
- "Native Tools vs Skills" section
- "IMPORTANT: Vision is a BASH SKILL" section

These additions may be:
1. Overloading the local LLM with instructions
2. Causing it to overthink tool selection
3. Diluting focus on the core workflow

### Investigate: LLM Context/Token Limits

The garbled output occurred after:
- ~76 messages in transcript
- Large Edit operation with ~15KB content
- Total context may have exceeded LLM's effective window

---

## Files for Reference

- Transcript: Container `/home/claude/.claude/projects/-home-claude-workspace/3d5917c0-89e9-4f69-a039-9ffc75a0d5ee.jsonl`
- Hook log: Container `~/.claude/state/hook.log`
- Successful workspace: `/Users/csabakecskemeti/claude-workspaces/test_20260323-101pm/`
- Failed workspace: `/Users/csabakecskemeti/claude-workspaces/test_20260324-752pm/`

---

## Key Takeaway

The auto-continue mechanism has a critical bug: **it matches completion strings in code content, not actual supervisor signals**. This caused it to falsely believe the task was complete when the game code contained `"MISSION COMPLETE!"` as a victory message.

Additionally, the CLAUDE.md changes between the successful and failed runs are suspect and should be investigated as a contributing factor to the LLM's degraded performance.
