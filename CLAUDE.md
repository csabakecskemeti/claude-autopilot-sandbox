# Project Instructions

## Chat vs Task: Know the Difference

**First, determine what type of request this is:**

| Type | Examples | What to do |
|------|----------|------------|
| **Chat** | "hello", "what is X?", "explain Y", "how does Z work?" | Just respond normally. No tasks, no supervisor. |
| **Task** | "build a game", "fix this bug", "add feature X", "create a script" | Use task tracking + supervisor workflow below. |

**Simple rule:** If the user is asking a question or having a conversation, just answer. Only use the task/supervisor workflow when there's actual implementation work to do.

## Autonomous Operation

You are running in a Docker sandbox with full permissions. When given an **implementation task**, complete it autonomously without waiting for user input.

**CRITICAL: Do NOT use plan mode.**

- **NEVER** use `EnterPlanMode` - it requires user approval and breaks autonomous operation
- **NEVER** ask "Should I proceed?" or wait for confirmation
- **Just do the work** - start implementing immediately

**If you need to plan, use the `/plan` skill instead:**

Just invoke `/plan` - it will guide you through analyzing the workspace and creating actionable steps using `/tasks`. No approval required.

This gives you planning WITHOUT requiring approval. Then start working immediately.

## You Have Vision Capabilities!

You can SEE images and screenshots using the `/vision` skill. Use this for:

- **UI Testing**: Take screenshot of your web app, verify it looks correct
- **Asset Verification**: Check downloaded images/sprites are what you expect
- **OCR**: Read text from images or screenshots
- **Visual Debugging**: See what's actually displayed when something looks wrong

### UI Testing Workflow

When building web UIs, ALWAYS verify with vision:

```bash
# 1. Start your app
python app.py &
sleep 2

# 2. Take screenshot and verify UI
~/.claude/skills/vision/vision.sh verify "http://localhost:5000" \
    "Should show: a title, input form, and todo list"

# 3. Check the response - fix issues if needed
```

## Task Tracking (For Implementation Work Only)

**Skip this section for simple chat/questions. Only use for actual implementation tasks.**

Use the `/tasks` skill for task tracking. Do NOT use the built-in TodoWrite tool.

The `/tasks` skill stores tasks in a file that persists and is checked by the supervisor.

### 1. Receive Implementation Task
When you receive a task that requires building/fixing/creating something:
1. Break it into clear tasks using `/tasks`:
   ```bash
   ~/.claude/skills/tasks/tasks.sh add "First step"
   ~/.claude/skills/tasks/tasks.sh add "Second step"
   ~/.claude/skills/tasks/tasks.sh add "Third step"
   ```
2. Mark current task as in-progress: `~/.claude/skills/tasks/tasks.sh working 1`
3. Start working

### 2. Work Loop
For each task:
1. Mark it as working: `~/.claude/skills/tasks/tasks.sh working <number>`
2. Implement the feature or fix
3. Verify it works (run tests, check syntax)
4. **For UI work: use /vision to verify visually**
5. Mark task complete: `~/.claude/skills/tasks/tasks.sh done <number>`
6. Move to next task

### 3. Call /supervisor After Implementation Work
**When working on tasks**, call `/supervisor` after completing work:

```
[your implementation work here]

Calling supervisor:
/supervisor
```

**DO NOT call /supervisor for:**
- Simple greetings or chat
- Answering questions
- Explanations or clarifications

**DO call /supervisor for:**
- After implementing features
- After fixing bugs
- After any code changes
- When you think a task is complete

### 4. Follow Supervisor Instructions
The supervisor will tell you to either:
- **Continue** - Keep working on remaining tasks
- **Fix errors** - Tests failed, fix them first
- **Done** - All complete, wait for user

**Only stop working when supervisor says "ALL COMPLETE".**

## Verification

Before marking a task complete:

```bash
# Check Python syntax
python3 -m py_compile *.py

# Run tests
python3 -m pytest -v

# For web apps - VERIFY VISUALLY:
~/.claude/skills/vision/vision.sh verify "http://localhost:5000" "Describe this page"
```

## Web Server Binding

**IMPORTANT:** When running web servers, always bind to `0.0.0.0` so the app is accessible from the host machine:

```bash
# Python http.server
python3 -m http.server 8000 --bind 0.0.0.0

# Flask
app.run(host='0.0.0.0', port=5000)

# Node.js/Express
app.listen(3000, '0.0.0.0')

# FastAPI/Uvicorn
uvicorn app:app --host 0.0.0.0 --port 8000
```

Do NOT bind to `127.0.0.1` or `localhost` - this prevents access from outside the container.

**Port mappings (container → host):**
| Container | Host | Use for |
|-----------|------|---------|
| 3000 | 23000 | Node.js/React |
| 5000 | 25000 | Flask |
| 8000 | 28000 | Django/FastAPI |
| 8080 | 28080 | General web |

## Available Skills

| Skill | Usage |
|-------|-------|
| `/plan` | Analyze workspace and create implementation plan (no approval needed) |
| `/tasks add <description>` | Add a new task |
| `/tasks list` | Show all tasks with status |
| `/tasks working <number>` | Mark task as in-progress |
| `/tasks done <number>` | Mark task as completed |
| `/tasks status` | Show summary (X of Y complete) |
| `/vision analyze <image_or_url> <prompt>` | Analyze image file OR screenshot URL |
| `/vision verify <image_or_url> <expected>` | Verify image/UI matches description |
| `/vision ocr <image_or_url>` | Extract text from image |
| `/vision logs` | View recent vision request logs |
| `/websearch query` | Search the web |
| `/memory store "text"` | Save for later |
| `/memory recall "topic"` | Retrieve saved info |
| `/pkg-install apt/pip pkg` | Install packages |

## Available Subagents

| Agent | Purpose |
|-------|---------|
| `debugger` | Investigate errors and bugs |
| `web-search-subagent` | Research using web search |
| `code-reviewer` | Review code quality |

## Error Recovery

If something fails during implementation:
1. Read the error message
2. Try to fix it
3. If stuck, use the debugger subagent
4. Continue with next task
5. Call `/supervisor` when done

## Rules

1. **NO PLAN MODE** - NEVER use `EnterPlanMode`. Just start working immediately.
2. **Chat vs Task** - For questions/chat, just respond. For implementation, use task workflow.
3. **Use /tasks skill** - NEVER use built-in TodoWrite. Always use `~/.claude/skills/tasks/tasks.sh`
4. **Keep working** - Don't stop until all tasks complete
5. **Verify everything** - Run tests AND use vision for UI
6. **Be honest** - If tests fail or UI looks wrong, fix it first
7. **Call /supervisor after implementation** - Only for actual work, not chat

## CRITICAL: When to Use /supervisor

**For implementation tasks only** - call `/supervisor` when you complete work.

When you finish implementing something:
1. Do NOT announce completion to the user
2. Do NOT stop working
3. Instead, call `/supervisor`

The supervisor will:
- Verify all tasks are actually complete
- Check that tests pass
- Decide if quality is acceptable
- Tell you to continue if more work is needed
- Only the supervisor can declare the task truly complete

```
[After finishing your implementation work]

I believe the task is complete. Calling supervisor for verification:
/supervisor
```

**For simple chat/questions:** Just respond normally - no supervisor needed.
