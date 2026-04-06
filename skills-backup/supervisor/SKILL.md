---
name: supervisor
description: MANDATORY final step. Validates task completion through testing and QA before allowing stop.
allowed-tools: Bash, Read, Task
---

# Supervisor - Completion Validator

**You called /supervisor. Now I will verify your work is complete.**

---

## Step 1: Self-Assessment

Answer these questions honestly:

1. **What was the original task?** (summarize in one sentence)
2. **What did you build/fix?** (list main changes)
3. **Did you test it?** (how did you verify it works?)
4. **Are there any known issues?** (be honest)

---

## Step 2: Run Verification

### If this is a coding project, run tests:

```bash
# Try common test commands (use whichever applies)
npm test 2>&1 || python -m pytest 2>&1 || go test ./... 2>&1 || echo "No test runner found"
```

### If this is a web app, check it runs:

```bash
# Check if server is running on common ports
curl -s http://localhost:3000 > /dev/null && echo "Server OK on 3000" || \
curl -s http://localhost:8000 > /dev/null && echo "Server OK on 8000" || \
curl -s http://localhost:5000 > /dev/null && echo "Server OK on 5000" || \
echo "No server detected"
```

### Check for obvious errors:

```bash
# Look for error patterns in recent output
echo "=== Checking for errors ==="
```

---

## Step 3: QA Agent Review (Required)

Call the qa-agent to review your work:

```
Use Task tool with subagent_type "qa-agent" to verify:
1. Does the implementation match the original request?
2. Are there any obvious bugs or missing pieces?
3. Is there adequate test coverage?
```

---

## Step 4: Decision

### If QA agent finds issues:

```
CONTINUE

Reason: [what QA found]
Action: [fix the issues]
```

Then go fix the issues - do NOT stop.

### If tests fail:

```
CONTINUE

Reason: Tests failing
Action: Fix the failing tests
```

Then go fix them - do NOT stop.

### If ALL verification passes:

Output this:
```
ALL COMPLETE

Task: [what was requested]
Built: [what you made]
Tested: [how you verified]
QA: VERIFIED
```

Then write the completion marker:
```bash
echo "COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" > ~/workspace/.supervisor_complete
```

---

## Supplementary Info (Optional)

If task/workflow files exist, you can check them too:

```bash
# Task list (if exists)
cat ~/workspace/.tasks 2>/dev/null || echo "No .tasks file"

# Workflow state (if exists)
cat ~/workspace/.workflow_state 2>/dev/null || echo "No .workflow_state file"
```

But these are NOT required for completion - tests and QA are what matter.

---

## CRITICAL RULES

- **NEVER say "ALL COMPLETE" without running tests or QA**
- **NEVER say "ALL COMPLETE" if tests are failing**
- **NEVER say "ALL COMPLETE" if QA agent finds issues**
- **If unsure, say CONTINUE and verify more**
- **Always write `.supervisor_complete` marker when truly done**
