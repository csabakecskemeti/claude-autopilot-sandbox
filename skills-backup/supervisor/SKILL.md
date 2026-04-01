---
name: supervisor
description: MANDATORY final step. Validates all workflow requirements before allowing completion.
allowed-tools: Bash, Read, Task
---

# Supervisor - Completion Validator

**You called /supervisor. Now I will check if you can stop.**

---

## Checklist Verification

### 1. Task Status
!`~/.claude/skills/tasks/tasks.sh list 2>&1`

!`~/.claude/skills/tasks/tasks.sh status 2>&1`

### 2. Workflow State
!`~/.claude/skills/workflow/workflow.sh status 2>&1`

### 3. Vision Verification (if UI project)
!`ls -la ~/.vision_logs/*.md 2>/dev/null | tail -5 || echo "No vision logs found"`

!`cat $(ls -t ~/workspace/.vision_logs/*_verify.md 2>/dev/null | head -1) 2>/dev/null || echo "No vision verify results"`

---

## Completion Requirements

**ALL of these must be true before you can stop:**

| # | Requirement | How to Check |
|---|-------------|--------------|
| 1 | All tasks marked `[x]` | No `[ ]` or `[>]` in task list |
| 2 | Vision verify PASS | Latest .vision_logs/*_verify.md shows "PASS" (if UI project) |
| 3 | No failing tests | Test output shows all passing |
| 4 | Original request fulfilled | All requested features implemented |

---

## Decision Logic

```
IF any task is [ ] or [>]:
    → CONTINUE: "Complete task N first"

IF UI project AND (no vision log OR vision shows FAIL):
    → CONTINUE: "Run /vision verify and fix until PASS"

IF tests were run AND any failed:
    → CONTINUE: "Fix failing tests"

IF all checks pass:
    → Call qa-agent to verify test coverage
    → IF qa-agent returns GAPS: Add tasks and CONTINUE
    → IF qa-agent returns VERIFIED: Proceed to completion
```

---

## Your Action Now

Based on the checklist above, determine:

### If NOT ready (any check fails):

Output exactly:
```
CONTINUE

Reason: [what failed]
Action: [what to do next]
```

Then continue working - do NOT stop.

### If ALL checks pass:

1. First call qa-agent subagent to verify test coverage
2. If qa-agent finds gaps, add tasks and continue
3. Only if qa-agent says VERIFIED, then output:

```
ALL COMPLETE

Summary: [what was built]
Tasks: [N] completed
Vision: PASS
QA: VERIFIED
```

And write the completion marker:
```bash
echo "COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" > ~/workspace/.supervisor_complete
```

---

## CRITICAL RULES

- **NEVER output "ALL COMPLETE" if any task is incomplete**
- **NEVER output "ALL COMPLETE" if vision shows FAIL**
- **NEVER output "ALL COMPLETE" without calling qa-agent first**
- **If in doubt, output CONTINUE and keep working**
