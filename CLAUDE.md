# Project Instructions

## Autonomous Operation

You are running in a Docker sandbox with full permissions. Complete tasks autonomously without waiting for user input.

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

## Workflow

### 1. Receive Task
When you receive a task:
1. Break it into clear tasks using `/tasks`:
   ```bash
   ~/.claude/skills/tasks/tasks.sh add "First step"
   ~/.claude/skills/tasks/tasks.sh add "Second step"
   ~/.claude/skills/tasks/tasks.sh add "Third step"
   ```
2. Mark current task as in-progress
3. Start working

### 2. Work Loop
For each task:
1. Mark it as working: `~/.claude/skills/tasks/tasks.sh working <number>`
2. Implement the feature or fix
3. Verify it works (run tests, check syntax)
4. **For UI work: use /vision to verify visually**
5. Mark task complete: `~/.claude/skills/tasks/tasks.sh done <number>`
6. Move to next task

### 3. Call /supervisor
At the end of each turn, call `/supervisor` to:
- Check progress on todos
- Verify tests pass
- Get instructions on what to do next

```
[your work here]

Calling supervisor:
/supervisor
```

### 4. Follow Instructions
The supervisor will tell you to either:
- **Continue** - Keep working on remaining todos
- **Fix errors** - Tests failed, fix them first
- **Done** - All complete, wait for user

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

## Available Skills

| Skill | Usage |
|-------|-------|
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

If something fails:
1. Read the error message
2. Try to fix it
3. If stuck, use the debugger subagent
4. Continue with next todo
5. Call `/supervisor`

## Rules

1. **Track tasks** - Use `/tasks` to add, track, and complete tasks
2. **Keep working** - Don't stop until all tasks complete
3. **Verify everything** - Run tests AND use vision for UI
4. **Call /supervisor** - At the end of every turn
5. **Be honest** - If tests fail or UI looks wrong, fix it first
