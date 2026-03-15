# User Manual

## Overview

claude-autopilot-sandbox runs Claude Code CLI in a Docker container connected to your local LLM. It operates autonomously using a supervisor loop that keeps Claude working until tasks are complete.

**Key Features:**
- 100% local execution with your own LLM
- Autonomous task completion without human intervention
- Vision capabilities for UI testing and image analysis
- Isolated workspaces for different projects

## Starting Claude

### Basic Usage

```bash
./run.sh                    # Uses 'default' workspace
./run.sh myproject          # Uses 'myproject' workspace
./run.sh client-work        # Uses 'client-work' workspace
```

Each workspace is isolated in `./workspaces/<name>/` and mapped to `/home/claude/workspace` inside the container.

### Workspace Initialization

New workspaces are automatically initialized with `CLAUDE.md` containing the autonomous operation instructions. You can customize this file per-workspace.

## The Autonomous Loop

Claude operates in a self-sustaining loop:

1. **You give a task** - Type your request
2. **Claude breaks it down** - Creates todos to track progress
3. **Claude works** - Implements each todo, runs tests
4. **Claude verifies** - Uses vision to verify UI, runs tests
5. **Supervisor evaluates** - Claude calls `/supervisor` to check progress
6. **Loop continues** - Supervisor provides instructions, Claude follows them
7. **Completion** - Supervisor signals all done when complete

You don't need to keep prompting - Claude will keep working autonomously until the task is complete.

## Vision Capabilities

Claude can see and analyze images. This is especially useful for UI testing.

### Available Commands

| Command | Usage |
|---------|-------|
| `analyze` | `/vision analyze <image_or_url> <prompt>` |
| `ocr` | `/vision ocr <image_or_url>` |
| `verify` | `/vision verify <image_or_url> <expected>` |
| `logs` | `/vision logs` |

### Input Types

The `<image_or_url>` can be:
- **Local file**: `./screenshot.png`, `/path/to/image.jpg`
- **Web URL**: `http://localhost:5000` (takes screenshot automatically)
- **Image URL**: `https://example.com/photo.jpg` (downloads image)

### UI Testing Workflow

When building web applications, Claude verifies the UI visually:

```bash
# Start app
python app.py &
sleep 2

# Verify UI looks correct
~/.claude/skills/vision/vision.sh verify http://localhost:5000 \
    "Should show: a title, input form, and todo list"
```

All vision requests are logged to `~/workspace/.vision_logs/` for review.

## Available Skills

Skills are invoked with `/skillname` syntax:

| Skill | Usage | Description |
|-------|-------|-------------|
| `/vision` | `/vision analyze/verify/ocr` | Image analysis and UI verification |
| `/websearch` | `/websearch query` | Web search via Whoogle |
| `/memory` | `/memory store/recall` | Persistent memory across sessions |
| `/notes` | `/notes add/list` | Note-taking system |
| `/supervisor` | `/supervisor` | Evaluate progress and continue |
| `/pkg-install` | `/pkg-install apt/pip pkg` | Install packages at runtime |
| `/code-runner` | `/code-runner python 'code'` | Execute code snippets |
| `/file-convert` | `/file-convert pdf2txt in out` | Convert between formats |
| `/api-tester` | `/api-tester GET url` | Test HTTP APIs |
| `/sql-query` | `/sql-query sqlite db query` | Execute SQL queries |

### Memory System

The memory skill persists across sessions:

```
/memory store "Key finding about the codebase"
/memory store "Bug: X causes Y" --category bugs
/memory recall "bugs"
/memory list
```

### Web Search

Requires Whoogle configured in `.env`:

```
/websearch how to implement X in python
/websearch latest news about Y
```

## Available Subagents

Claude can delegate to specialized subagents:

| Agent | Purpose |
|-------|---------|
| `debugger` | Bug investigation and error fixing |
| `web-search` | Research tasks using web search |
| `code-reviewer` | Code quality and security review |

## Workspace Management

### Creating a New Workspace

```bash
./run.sh new-project
```

This creates `./workspaces/new-project/` with a fresh `CLAUDE.md`.

### Workspace Contents

Each workspace contains:
- Your project files
- `.memory/` - Persistent memory storage
- `.notes/` - Notes storage
- `.vision_logs/` - Vision request logs with screenshots
- `CLAUDE.md` - Workspace instructions

### Customizing CLAUDE.md

Edit the workspace's `CLAUDE.md` to add project-specific instructions:

```markdown
# Project Instructions

## Project-Specific Rules
- This is a Python 3.11 project
- Use pytest for testing
- Follow PEP 8 style guide

## Autonomous Operation Protocol
... (keep the supervisor loop instructions)
```

## Resource Limits

Default limits in `.env`:

```env
MEMORY_LIMIT=16G
MEMORY_RESERVATION=2G
```

Adjust based on your system and model requirements.

## Tips for Best Results

1. **Be specific** - Clear tasks get better results
2. **Let it work** - Don't interrupt the autonomous loop
3. **Use workspaces** - Isolate different projects
4. **Use vision** - For UI work, always verify visually
5. **Use memory** - Store important context for persistence

## Stopping Claude

- Press `Ctrl+C` to interrupt
- Type `exit` or `/exit` to quit gracefully
- The supervisor will stop when all tasks are complete

## Example Session

```
$ ./run.sh my-api

Starting Claude Code with workspace: my-api
  Host path: /path/to/workspaces/my-api
  Container path: /home/claude/workspace

You: Create a REST API with Flask that has user authentication

[Claude creates todos, implements the API, tests it, verifies UI with vision,
 calls /supervisor repeatedly until done]

Claude: I've completed the Flask REST API with user authentication. Here's what was built:
- app.py with routes for /register, /login, /logout
- auth.py with JWT token handling
- models.py with User model
- tests/test_auth.py with full test coverage

All tests pass. UI verified with vision. Calling supervisor for final evaluation.

[Supervisor confirms completion]
```
