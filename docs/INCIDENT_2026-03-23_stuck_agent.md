# Incident Report: Stuck Agent Run

**Date:** 2026-03-23
**Session ID:** 75ce4930-6615-4518-b4bc-e59187b97e39
**Model:** nvidia.nvidia-nemotron-3-super-120b-a12b
**Task:** Build a web-based platformer game (TASK.md)
**Workspace:** `/Users/csabakecskemeti/claude-workspaces/test_20260322-803pm`

---

## Summary

The agent got stuck after **1 hour 14 minutes** while attempting to write `main.js`. The root cause was the **local LLM passing an invalid parameter** to Claude Code's Write tool, causing a validation error. After the error, the LLM entered a prolonged "thinking" state and never recovered.

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 03:14 | Container started, agent began reading TASK.md |
| 03:35 | Agent started planning phase |
| 03:43 | Agent decided on HTML5 Canvas + JavaScript stack |
| 03:56-03:58 | Agent attempted to download assets from GitHub (404 errors) |
| 04:12-04:13 | Agent created `index.html` and `styles.css` |
| 04:17-04:18 | Agent added task 5 and marked it "working" |
| **04:24:42** | **Agent called Write tool with invalid `description` parameter** |
| **04:24:42** | **Claude Code returned InputValidationError** |
| 04:25:59 | LLM started thinking about how to fix the error |
| 04:30:01 | Stop hook invoked, found 246 messages |
| 04:30:01 | Hook crashed during processing (zombie processes) |
| 04:31:01 | Last transcript entry |
| +12 hours | Container still running, agent stuck at prompt |

---

## Root Cause Analysis

### Primary Cause: Local LLM Tool Schema Confusion

The LLM attempted to call the Write tool with this input:

```json
{
  "name": "Write",
  "input": {
    "file_path": "/home/claude/workspace/main.js",
    "content": "// Game Constants\nconst CANVAS_WIDTH = 800;...",
    "description": "Create main.js with core game engine..."  // ← INVALID
  }
}
```

**The `description` parameter does not exist on the Write tool.** It exists on the Bash tool, but not Write.

Claude Code returned:
```
InputValidationError: Write failed due to the following issue:
An unexpected parameter `description` was provided
```

This is the "Error writing file" message shown in the UI.

### Why This Happened

The local LLM (Nemotron) confused tool schemas:

| Tool | Has `description` param? |
|------|-------------------------|
| Bash | ✅ Yes |
| Write | ❌ No |
| Edit | ❌ No |
| Read | ❌ No |

The LLM likely learned from seeing `description` on Bash tool calls and incorrectly generalized it to Write.

### Secondary Issue: Prolonged "Crunching" State

After the error, the LLM started a thinking block:
```
"We are in a bash session. We need to create main.js without using description field.
Let's just use cat or echo to write the file..."
```

But then the agent entered a **1 hour 14 minute "Crunching"** state, during which:
- The LLM may have been generating extremely long output
- Or the LLM backend (LM Studio) was processing slowly
- Or there was a network/connection issue

The session never recovered.

### Tertiary Issue: Hook Processing Crashed

When the Stop hook fired, it attempted to process 246 messages but crashed:

```
[INFO] Found 246 new messages
```

No further log entries. Process table shows zombie processes:
```
claude    1550  Z+   [langfuse_stop_h] <defunct>
claude    5502  Z+   [langfuse_stop_h] <defunct>
claude    5504  Z+   [jq] <defunct>
```

#### Root Cause of Hook Crash: Bash History Expansion

**Investigation revealed the actual cause:**

1. **Transcript contains `!` characters** - Found in JSON content like:
   - `"ALL TASKS COMPLETE!"`
   - `"CYBER RUNNER: NEON REBELLION!"`
   - Other exclamation marks in thinking/output text

2. **Bash history expansion** - The hook script does:
   ```bash
   echo "$line" | jq ...
   ```
   When `$line` contains `!` followed by certain characters, bash interprets it as history expansion:
   ```
   bash: !: command not found
   ```

3. **`set -e` kills the script** - With `set -e` at line 8, any non-zero exit code terminates the script immediately

4. **Zombie processes** - Child `jq` processes become orphaned when parent dies abruptly

5. **No state saved** - Crash happens before `save_state()` is called

**Evidence:**
```bash
# 12 exclamation marks across 6 lines in transcript
$ grep -c '!' transcript.jsonl
6

# When processed through bash variables:
$ while read line; do echo "$line" | jq ...; done
bash: !: command not found  # Repeated 248 times
```

**Result:** No trace was sent to Langfuse, no state file created.

---

## Evidence

### Files Created (incomplete)
```
/workspace/
├── index.html      ✅ Created (references main.js)
├── styles.css      ✅ Created
├── main.js         ❌ NOT CREATED (Write failed)
├── TASK.md         ✅ Exists
├── CLAUDE.md       ✅ Exists
└── src/
    └── assets/
        ├── sprites/    (empty)
        ├── sounds/     (empty)
        └── tilemaps/   (empty)
```

### Task State
```
[x] Planning phase: Break down project into components
[x] Choose technology stack: HTML5 Canvas + JavaScript
[x] Gather open-source game assets (marked done but assets not actually gathered)
[x] Create project structure: index.html, main.js, styles.css
[>] Implement core game engine  ← STUCK HERE
```

### Container State
```
PID 1: claude process still running at 3.2% CPU
Multiple zombie hook processes
Container uptime: 12+ hours
```

---

## Recommendations

### Immediate Actions

1. **Kill the stuck container**
   ```bash
   docker kill 59ce308aeb92
   ```

2. **Clean up workspace** for retry
   ```bash
   rm -rf /Users/csabakecskemeti/claude-workspaces/test_20260322-803pm
   ```

### Short-term Fixes

3. **Add tool schema guidance to CLAUDE.md**

   Add this to the inner Claude's instructions:
   ```markdown
   ## Tool Parameter Reference

   When using tools, use ONLY these parameters:

   | Tool | Parameters |
   |------|-----------|
   | Write | file_path, content |
   | Edit | file_path, old_string, new_string, replace_all |
   | Read | file_path, offset, limit |
   | Bash | command, timeout, description |

   ⚠️ Do NOT add extra parameters. The `description` field is ONLY for Bash.
   ```

4. **Add error recovery guidance**
   ```markdown
   ## Error Recovery

   If you see "InputValidationError" or "Error writing file":
   1. Check your tool parameters - you may have used an invalid parameter
   2. Retry the operation with correct parameters
   3. If Write fails, try using Bash with heredoc as fallback:
      ```bash
      cat > /path/to/file << 'EOF'
      content here
      EOF
      ```
   ```

5. **Langfuse hook completely rewritten** (v2.0.0) ✅ DONE

   Key improvements:
   - `set +H` - Disables bash history expansion (fixes `!` character issue)
   - Handles ALL message types: `assistant`, `user`, `progress`, `system`
   - Extracts tool calls from subagent progress messages
   - Uses `jq --slurp` for bulk processing instead of bash loops
   - Proper cleanup trap with temp file management
   - `printf` everywhere instead of `echo`
   - Comprehensive error handling and logging

### Long-term Improvements

6. **Test local LLMs with tool validation**
   - Create a test suite that verifies LLM tool calls
   - Flag models that frequently hallucinate extra parameters

7. **Add watchdog for stuck sessions**
   - Detect sessions that haven't made progress in N minutes
   - Auto-terminate or alert

8. **Improve hook resilience**
   - Process messages in smaller batches
   - Add retry logic for Langfuse API calls
   - Clean up zombie processes

---

## Lessons Learned

1. **Local LLMs may not perfectly follow tool schemas** - They can hallucinate parameters based on patterns from other tools.

2. **Error recovery is critical** - A single validation error shouldn't cause hour-long hangs.

3. **Bash scripts processing JSON need special care:**
   - Disable history expansion with `set +H`
   - Don't use `echo "$var" | jq` for untrusted content
   - Process files directly instead of loading into variables
   - Handle special characters (`!`, `$`, backticks) properly

4. **`set -e` is dangerous in complex scripts** - One unexpected failure kills everything with no cleanup.

5. **Zombie processes indicate missing cleanup** - Always use `trap` for cleanup handlers.

6. **Filesystem was NOT the issue** - Initial hypothesis about exFAT was incorrect. The workspace was on APFS.

---

## Appendix: The Failed Write Tool Call

Full tool call that caused the error:

```json
{
  "type": "tool_use",
  "id": "966647554",
  "name": "Write",
  "input": {
    "file_path": "/home/claude/workspace/main.js",
    "content": "// Game Constants\nconst CANVAS_WIDTH = 800;\nconst CANVAS_HEIGHT = 600;\n... [~350 lines of valid JavaScript]",
    "description": "Create main.js with core game engine, player movement, platforms, levels, and state management"
  }
}
```

The content was valid. Only the `description` parameter was wrong.
