---
name: workflow
description: Manage autonomous task completion workflow. Use this at the START of any task that requires building, creating, fixing, or implementing something.
---

# Workflow - Autonomous Task Completion

## When to Use This Skill

**ALWAYS use `/workflow start` when the user request is a TASK, not a chat.**

| Request Type | Example | Action |
|--------------|---------|--------|
| **Chat** | "What is React?" | Answer directly, NO workflow |
| **Chat** | "Explain this code" | Answer directly, NO workflow |
| **Task** | "Build a todo app" | `/workflow start` FIRST |
| **Task** | "Fix the login bug" | `/workflow start` FIRST |
| **Task** | "Add dark mode" | `/workflow start` FIRST |
| **Task** | "Create an API endpoint" | `/workflow start` FIRST |

**Rule:** If you will write/edit code or create files → USE WORKFLOW.

---

## The Complete Workflow Loop

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER REQUEST                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Chat or Task?   │
                    └─────────────────┘
                      │           │
              Chat ───┘           └─── Task
                │                       │
                ▼                       ▼
         ┌──────────┐         ┌─────────────────────┐
         │ Answer   │         │ /workflow start     │
         │ directly │         │ "task description"  │
         └──────────┘         └─────────────────────┘
                                        │
                    ┌───────────────────┘
                    ▼
         ┌─────────────────────┐
         │ PHASE 1: PLAN       │
         │                     │
         │ Think through:      │
         │ • What to build     │
         │ • Key components    │
         │ • Dependencies      │
         │ • Testing approach  │
         └─────────────────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │ PHASE 2: TASKS      │
         │                     │
         │ /tasks add "..."    │
         │ /tasks add "..."    │
         │ /tasks add "..."    │
         │                     │
         │ Break plan into     │
         │ trackable steps     │
         └─────────────────────┘
                    │
                    ▼
         ┌─────────────────────┐
         │ PHASE 3: WORK       │◄────────────────────┐
         │                     │                     │
         │ /tasks working N    │                     │
         │ • Implement         │                     │
         │ • Use subagents     │                     │
         │   if stuck          │                     │
         │ /tasks done N       │                     │
         └─────────────────────┘                     │
                    │                                │
                    ▼                                │
         ┌─────────────────────┐                     │
         │ PHASE 4: TEST       │                     │
         │                     │                     │
         │ • Run tests         │                     │
         │ • Fix failures      │                     │
         │ • If UI project:    │                     │
         │   /vision verify    │                     │
         └─────────────────────┘                     │
                    │                                │
                    ▼                                │
         ┌─────────────────────┐                     │
         │ More tasks?         │───── Yes ──────────┘
         └─────────────────────┘
                    │
                   No
                    │
                    ▼
         ┌─────────────────────┐
         │ PHASE 5: QA         │
         │                     │
         │ Call qa-agent:      │
         │ • Verify coverage   │
         │ • Check all tested  │
         │ • Identify gaps     │
         └─────────────────────┘
                    │
           ┌───────┴───────┐
           ▼               ▼
      QA VERIFIED     GAPS FOUND
           │               │
           │               ▼
           │         ┌───────────┐
           │         │ Add tasks │
           │         │ for gaps  │──────────────────┐
           │         └───────────┘                  │
           │                                        │
           ▼                                        │
         ┌─────────────────────┐                    │
         │ PHASE 6: SUPERVISOR │                    │
         │                     │                    │
         │ /supervisor         │                    │
         │ • Checks tasks      │                    │
         │ • Checks tests      │                    │
         │ • Checks QA         │                    │
         │ • Makes decision    │                    │
         └─────────────────────┘                    │
                    │                               │
         ┌──────────┼──────────┐                    │
         ▼          ▼          ▼                    │
    ALL COMPLETE  CONTINUE   RE-PLAN               │
         │          │          │                    │
         │          └──────────┼────────────────────┘
         │                     │
         ▼                     ▼
      ┌──────┐          ┌──────────┐
      │ STOP │          │ Back to  │
      │      │          │ PLAN     │
      └──────┘          └──────────┘
```

---

## Workflow Commands

```bash
# Start workflow for a new task
~/.claude/skills/workflow/workflow.sh start "task description"

# Record a checkpoint (auto-called by other skills)
~/.claude/skills/workflow/workflow.sh checkpoint plan
~/.claude/skills/workflow/workflow.sh checkpoint tasks
~/.claude/skills/workflow/workflow.sh checkpoint test
~/.claude/skills/workflow/workflow.sh checkpoint vision

# Check current workflow state
~/.claude/skills/workflow/workflow.sh status

# Reset workflow (start over)
~/.claude/skills/workflow/workflow.sh reset
```

---

## Phase Details

### Phase 1: PLAN

Before writing any code, think through:

1. **What exactly needs to be built?**
   - Core functionality
   - User-facing features
   - Edge cases

2. **What components are needed?**
   - Files to create
   - Functions/classes
   - Dependencies

3. **What's the testing approach?**
   - Unit tests?
   - Integration tests?
   - UI verification?

4. **Any research needed?**
   - Unknown APIs?
   - Best practices?
   - Use `web-researcher` subagent if needed

### Phase 2: TASKS

Break your plan into trackable tasks:

```bash
~/.claude/skills/tasks/tasks.sh add "Setup: Create project structure"
~/.claude/skills/tasks/tasks.sh add "Core: Implement main logic"
~/.claude/skills/tasks/tasks.sh add "UI: Create user interface"
~/.claude/skills/tasks/tasks.sh add "Test: Write and run tests"
~/.claude/skills/tasks/tasks.sh add "Verify: Visual verification"
```

**Good tasks are:**
- Specific and actionable
- Small enough to complete in one step
- Verifiable (you know when it's done)

### Phase 3: WORK

For each task:

```bash
# Mark as in progress
~/.claude/skills/tasks/tasks.sh working 1

# Do the work...
# - Write code
# - Create files
# - Install dependencies
# - Use subagents if stuck

# Mark as complete
~/.claude/skills/tasks/tasks.sh done 1
```

**Use subagents when:**
- `debugger` - Stuck on errors
- `web-researcher` - Need documentation/examples
- `code-reviewer` - Want quality check
- `worker` - Delegate independent subtask

### Phase 4: TEST

**For code changes:**
```bash
# Run tests
npm test
pytest
go test ./...

# Check output
# Fix any failures before proceeding
```

**For UI changes (MANDATORY):**
```bash
~/.claude/skills/vision/vision.sh verify http://localhost:8000 "expected elements"
```

### Phase 5: QA

Call the QA agent to verify test coverage:

```
Use the qa-agent subagent to verify:
- All requirements tested
- UI verified (if applicable)
- Edge cases covered
```

QA will return:
- `QA VERIFIED` → Proceed to supervisor
- `QA GAPS FOUND` → Add tasks for missing tests, loop back

### Phase 6: SUPERVISOR

```bash
# Call supervisor to evaluate completion
# Supervisor will check everything and decide
```

**Supervisor responses:**
- `ALL COMPLETE` → STOP, task is done
- `CONTINUE` → More tasks remain, keep working
- `RE-PLAN` → Requirements changed, start over

**CRITICAL:** Never announce "done" yourself. Only stop when supervisor says `ALL COMPLETE`.

---

## Quick Reference

| Phase | Command | Required? |
|-------|---------|-----------|
| Start | `/workflow start "desc"` | Yes, for all tasks |
| Plan | Think, research, design | Yes |
| Tasks | `/tasks add "..."` | Yes |
| Work | `/tasks working N` + implement | Yes |
| Test | Run tests, `/vision verify` | Yes for code/UI |
| QA | `qa-agent` subagent | Yes |
| Supervisor | `/supervisor` | Yes, always last |

---

## Example: Building a Todo App

```bash
# 1. START WORKFLOW
~/.claude/skills/workflow/workflow.sh start "Build a web-based todo app"

# 2. PLAN (thinking)
# - Need: HTML, CSS, JavaScript
# - Features: Add, complete, delete todos
# - Storage: localStorage
# - Testing: Manual + vision verify

# 3. CREATE TASKS
~/.claude/skills/tasks/tasks.sh add "Create HTML structure"
~/.claude/skills/tasks/tasks.sh add "Add CSS styling"
~/.claude/skills/tasks/tasks.sh add "Implement JavaScript logic"
~/.claude/skills/tasks/tasks.sh add "Add localStorage persistence"
~/.claude/skills/tasks/tasks.sh add "Test functionality"
~/.claude/skills/tasks/tasks.sh add "Visual verification"

# 4. WORK ON EACH TASK
~/.claude/skills/tasks/tasks.sh working 1
# ... create HTML ...
~/.claude/skills/tasks/tasks.sh done 1

~/.claude/skills/tasks/tasks.sh working 2
# ... add CSS ...
~/.claude/skills/tasks/tasks.sh done 2

# ... continue for all tasks ...

# 5. TEST
# Start server, test manually
python3 -m http.server 8000 &

# Visual verification (REQUIRED for UI)
~/.claude/skills/vision/vision.sh verify http://localhost:8000 "todo input, add button, task list"

# 6. QA
# Call qa-agent to verify coverage

# 7. SUPERVISOR
# /supervisor will check everything and declare complete
```

---

## Common Mistakes to Avoid

| Mistake | Why It's Wrong | Correct Approach |
|---------|----------------|------------------|
| Skipping `/workflow start` | No tracking | Always start workflow for tasks |
| Writing code before planning | Miss requirements | Think first, code second |
| Not using `/tasks` | Can't track progress | Break everything into tasks |
| Skipping `/vision verify` for UI | UI bugs missed | ALWAYS verify UI visually |
| Announcing "Done!" to user | Only supervisor decides | Call `/supervisor` instead |
| Skipping QA | Test gaps missed | Always run qa-agent |

---

## Remember

1. **Chat = Answer directly**
2. **Task = /workflow start FIRST**
3. **Plan before coding**
4. **Track with /tasks**
5. **Test everything**
6. **Vision for UI**
7. **QA before supervisor**
8. **Only supervisor says DONE**
