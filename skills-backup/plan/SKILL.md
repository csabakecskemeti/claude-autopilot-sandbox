---
name: plan
description: Create an implementation plan for a task. Use this skill when asked to build, create, or implement something. Analyzes workspace context and generates actionable steps without requiring user approval.
---

# Plan Skill

Use this skill to plan implementation tasks **without entering plan mode**. This skill provides autonomous planning that doesn't require user approval.

## When to Use

Use `/plan` when:
- Building a new feature or application
- Implementing something with multiple steps
- You need to analyze the workspace before starting

**Do NOT use Claude Code's built-in `EnterPlanMode`** - it requires approval and breaks autonomous operation.

## How to Plan

### Step 1: Analyze the Workspace

First, understand what you're working with:

```bash
# Check what files exist
ls -la ~/workspace/

# Check for project type indicators
ls ~/workspace/package.json ~/workspace/requirements.txt ~/workspace/Cargo.toml 2>/dev/null

# Check available tools
python3 --version
node --version
```

### Step 2: Break Down the Task

For any implementation task, identify these phases:

1. **Setup** - Dependencies, environment, project structure
2. **Core** - Main functionality implementation
3. **UI** (if applicable) - User interface components
4. **Integration** - Connect pieces together
5. **Testing** - Verify everything works
6. **Polish** - Clean up, error handling, edge cases

### Step 3: Add Steps to /tasks

Use the tasks skill to track your plan:

```bash
~/.claude/skills/tasks/tasks.sh add "Setup: Install dependencies"
~/.claude/skills/tasks/tasks.sh add "Core: Implement main logic"
~/.claude/skills/tasks/tasks.sh add "UI: Create user interface"
~/.claude/skills/tasks/tasks.sh add "Test: Verify implementation"
~/.claude/skills/tasks/tasks.sh add "Polish: Final cleanup"
```

### Step 4: Start Working Immediately

After adding tasks:
1. Mark first task as working: `~/.claude/skills/tasks/tasks.sh working 1`
2. Begin implementation
3. Mark complete and move to next
4. Call `/supervisor` when done

## Example: Planning a Todo Web App

```bash
# 1. Analyze workspace
ls -la ~/workspace/
python3 --version

# 2. Add specific tasks
~/.claude/skills/tasks/tasks.sh clear
~/.claude/skills/tasks/tasks.sh add "Install Flask if needed"
~/.claude/skills/tasks/tasks.sh add "Create app.py with routes"
~/.claude/skills/tasks/tasks.sh add "Create templates/index.html"
~/.claude/skills/tasks/tasks.sh add "Implement add/delete todo functionality"
~/.claude/skills/tasks/tasks.sh add "Test the application"
~/.claude/skills/tasks/tasks.sh add "Verify UI with /vision"

# 3. Start working
~/.claude/skills/tasks/tasks.sh working 1
# ... begin implementation ...
```

## Key Principles

1. **No approval needed** - Just plan and start working
2. **Use /tasks for tracking** - Makes progress visible to supervisor
3. **Be specific** - Break tasks into concrete, actionable steps
4. **Verify with /vision** - For UI work, always check visually
5. **Call /supervisor when done** - Get verification before declaring complete

## Quick Reference

| Action | Command |
|--------|---------|
| Add task | `~/.claude/skills/tasks/tasks.sh add "description"` |
| List tasks | `~/.claude/skills/tasks/tasks.sh list` |
| Start task | `~/.claude/skills/tasks/tasks.sh working <num>` |
| Complete task | `~/.claude/skills/tasks/tasks.sh done <num>` |
| Clear all | `~/.claude/skills/tasks/tasks.sh clear` |
