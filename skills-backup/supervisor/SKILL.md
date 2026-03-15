---
name: supervisor
description: Simple progress supervisor. Checks todo status and decides whether to continue or stop. Call at the end of every turn to maintain autonomous operation.
allowed-tools: Bash, Read
---

# Supervisor

Simple progress check and continuation decision. Call `/supervisor` at the end of every turn.

## When Invoked

### Step 1: Check Todo Status

Review current todos:
- How many complete vs pending?
- Is there active work in progress?

### Step 2: Verify Current Work

Run a quick verification:

```bash
# Check for syntax errors in Python files
find ~/workspace -name "*.py" -exec python3 -m py_compile {} \; 2>&1 | head -10

# Run tests if they exist
python3 -m pytest -v 2>&1 | tail -20 || echo "No pytest tests found"

# Or run a main file
timeout 5 python3 ~/workspace/main.py 2>&1 | head -20 || echo "No main.py or timeout"
```

### Step 3: Decide Action

Based on verification results:

**If tests FAIL or errors exist:**
```
===========================================================
[!] SUPERVISOR: ERRORS FOUND - CONTINUE FIXING
===========================================================

Errors found:
- [list errors]

INSTRUCTION: Fix these errors now:
1. [specific fix]
2. [specific fix]

Continue working. Do NOT stop.
===========================================================
```

**If tests PASS and todos remain:**
```
===========================================================
[OK] SUPERVISOR: PROGRESS OK - CONTINUE
===========================================================

Completed: X of Y todos
Tests: PASSING

INSTRUCTION: Continue with next todo:
- [next pending todo]

Keep working. Do NOT stop.
===========================================================
```

**If ALL todos complete and tests pass:**
```
===========================================================
[DONE] SUPERVISOR: ALL COMPLETE
===========================================================

All todos completed. Tests passing.

Summary:
- [what was built]

Waiting for user review or new task.
===========================================================
```

## Critical Rules

1. **Be honest** - If tests fail, say so
2. **Keep it simple** - Just check todos and tests
3. **Always give clear instruction** - Tell agent exactly what to do next
4. **Only stop when truly done** - All todos complete AND tests pass
