---
name: supervisor
description: Check task progress and decide next action. Call after completing implementation work.
allowed-tools: Bash, Read
---

# Supervisor Check

## Current Task Status

!`~/.claude/skills/tasks/tasks.sh list 2>&1`

!`~/.claude/skills/tasks/tasks.sh status 2>&1`

---

## Your Job Now

Based on the task status above:

1. **If tasks remain incomplete** → Continue working on the next pending task
2. **If all tasks complete** → Verify the work meets the original request
3. **If UI project** → Run `/vision verify` to check visually before declaring done

## Decision Guide

| Status | Action |
|--------|--------|
| Tasks pending | Mark next as working, continue implementing |
| All complete, no UI | Declare done, summarize what was built |
| All complete, has UI | Run `/vision verify` first, then declare done |
| Tests failing | Add fix tasks, continue working |

## Quick Commands

```bash
# Mark task as working
~/.claude/skills/tasks/tasks.sh working <num>

# Mark task as done
~/.claude/skills/tasks/tasks.sh done <num>

# Add new task if issues found
~/.claude/skills/tasks/tasks.sh add "Fix: <issue>"

# Clear tasks when fully complete
~/.claude/skills/tasks/tasks.sh clear
```

## When Done

Output a summary:
```
ALL COMPLETE

Built: [what was created]
Verified: [tests/vision status]
```
