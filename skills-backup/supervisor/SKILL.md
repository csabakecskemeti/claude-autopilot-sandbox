---
name: supervisor
description: Simple progress supervisor. Checks task status using /tasks skill and decides whether to continue or stop. Call at the end of every turn to maintain autonomous operation.
allowed-tools: Bash, Read
---

# Supervisor

Simple progress check and continuation decision. Call `/supervisor` at the end of every turn.

## When Invoked

### Step 1: Check Task Status

Check current tasks using the tasks skill:

```bash
~/.claude/skills/tasks/tasks.sh status
~/.claude/skills/tasks/tasks.sh list
```

Review the output:
- How many complete vs pending?
- Is there active work in progress?
- Are any tasks stuck?

### Step 2: Test the Solution

1. Recall the **original user request** - what did they ask for?
2. Verify the completed work **actually meets that intent**
3. Run/test/check the output to confirm it works

Ask yourself: "If I were the user, would I be satisfied with this result?"

### Step 3: Add Tasks if Issues Found

If verification reveals problems, add new tasks:

```bash
~/.claude/skills/tasks/tasks.sh add "Fix: [specific issue found]"
~/.claude/skills/tasks/tasks.sh add "Fix: [another issue]"
```

Then instruct agent to continue working on the new tasks.

### Step 4: Decide Action

Based on verification results:

**If tests FAIL or errors exist:**
```bash
# Add tasks for each issue found
~/.claude/skills/tasks/tasks.sh add "Fix: [specific error]"
```

Then output:
```
===========================================================
[!] SUPERVISOR: ERRORS FOUND - CONTINUE FIXING
===========================================================

Errors found:
- [list errors]

Added new tasks for fixes. Current status:
[output of tasks.sh status]

INSTRUCTION: Fix these errors now. Start with task 1.

Continue working. Do NOT stop.
===========================================================
```

**If tests PASS and tasks remain:**
```
===========================================================
[OK] SUPERVISOR: PROGRESS OK - CONTINUE
===========================================================

Completed: X of Y tasks
Tests: PASSING

INSTRUCTION: Continue with next task:
- [next pending task]

Mark current task as working:
~/.claude/skills/tasks/tasks.sh working <number>

Keep working. Do NOT stop.
===========================================================
```

**If ALL tasks complete and tests pass:**
```
===========================================================
[DONE] SUPERVISOR: ALL COMPLETE
===========================================================

All tasks completed. Tests passing.

Summary:
- [what was built]

Clear tasks for next session:
~/.claude/skills/tasks/tasks.sh clear

Waiting for user review or new task.
===========================================================
```

## Critical Rules

1. **Be honest** - If tests fail, say so
2. **Keep it simple** - Just check tasks and tests
3. **Always give clear instruction** - Tell agent exactly what to do next
4. **Only stop when truly done** - All tasks complete AND tests pass
5. **Track with /tasks** - Always use the tasks skill, not built-in todos
