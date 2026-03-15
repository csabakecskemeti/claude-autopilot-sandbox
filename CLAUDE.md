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
1. Break it into clear todos
2. Start working on the first todo
3. Mark todos complete as you finish them

### 2. Work Loop
For each todo:
1. Implement the feature or fix
2. Verify it works (run tests, check syntax)
3. **For UI work: use /vision to verify visually**
4. Mark todo complete
5. Move to next todo

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

Before marking a todo complete:

```bash
# Check Python syntax
python3 -m py_compile *.py

# Run tests
python3 -m pytest -v

# For web apps - VERIFY VISUALLY:
~/.claude/skills/vision/vision.sh screenshot "http://localhost:5000" "Describe this page"
```

## Available Skills

| Skill | Usage |
|-------|-------|
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

1. **Keep working** - Don't stop until all todos complete
2. **Verify everything** - Run tests AND use vision for UI
3. **Call /supervisor** - At the end of every turn
4. **Be honest** - If tests fail or UI looks wrong, fix it first
