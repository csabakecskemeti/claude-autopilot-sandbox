---
name: tasks
description: Track tasks for the current work session. Use this to break down work into steps and track progress. ALWAYS use this when starting a new task - add items first, then mark them done as you complete them.
allowed-tools: Bash
---

# Tasks

Simple task tracking for the current work session. **Use this for ALL task management.**

## Commands

| Command | Description |
|---------|-------------|
| `add <task>` | Add a new task |
| `list` | Show all tasks with status |
| `done <number>` | Mark task as completed |
| `working <number>` | Mark task as in-progress |
| `remove <number>` | Remove a task |
| `clear` | Clear all tasks |
| `status` | Show summary (X of Y complete) |

## Usage

```bash
# Add tasks
~/.claude/skills/tasks/tasks.sh add "Set up project structure"
~/.claude/skills/tasks/tasks.sh add "Create database models"
~/.claude/skills/tasks/tasks.sh add "Write tests"

# List tasks
~/.claude/skills/tasks/tasks.sh list

# Mark as in-progress
~/.claude/skills/tasks/tasks.sh working 1

# Mark as done
~/.claude/skills/tasks/tasks.sh done 1

# Check status
~/.claude/skills/tasks/tasks.sh status
```

## Workflow

1. **Start of task**: Break work into steps, add each as a task
2. **Working**: Mark current task as "working"
3. **Complete**: Mark task as "done" when finished
4. **Before /supervisor**: Run `status` to check progress

## Output Format

```
Tasks (2 of 5 complete):
  [x] 1. Set up project structure
  [>] 2. Create database models (in progress)
  [ ] 3. Write tests
  [ ] 4. Create templates
  [ ] 5. Run verification
```

## Storage

Tasks are stored in `~/workspace/.tasks` and persist across the session.
