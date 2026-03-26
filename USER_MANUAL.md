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
| `/plan` | `/plan` | Create implementation plan (no approval needed) |
| `/tasks` | `/tasks add/list/done` | Track task progress |
| `/vision` | `/vision analyze/verify/ocr` | Image analysis and UI verification |
| `/webfetch` | `/webfetch <url> "<prompt>"` | Fetch URL and analyze with local LLM |
| `/supervisor` | `/supervisor` | Evaluate progress and continue |
| `/websearch` | `/websearch query` | Web search via Whoogle |
| `/memory` | `/memory store/recall` | Persistent memory across sessions |
| `/notes` | `/notes add/list` | Note-taking system |
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

## Tested Models

The following models have been tested and work well with this sandbox:

### Primary LLM

| Model | Context | Notes |
|-------|---------|-------|
| `nvidia.nvidia-nemotron-3-super-120b-a12b` | 1M | Excellent for autonomous coding tasks. Good instruction following. |

### Vision Model

| Model | Notes |
|-------|-------|
| `qwen/qwen3-vl-4b` | Fast, accurate for UI verification and OCR. |

### Configuration

Set in `.env`:
```env
LLM_MODEL=nvidia.nvidia-nemotron-3-super-120b-a12b
VISION_MODEL=qwen/qwen3-vl-4b
```

### Model Requirements

For autonomous operation, the LLM should have:
- **Large context window** - sessions can be long
- **Good instruction following** - must follow CLAUDE.md instructions
- **Tool use capability** - needs to call tools correctly

### LM Studio Setup

For detailed LM Studio configuration with these models, see [LM_STUDIO_SETUP.md](LM_STUDIO_SETUP.md).

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

## Example: Zero-Shot Platformer Game

This example shows the full autonomous workflow building a complete 2D platformer game from a single prompt.

### Setup

**User Prompt:** `accomplish TASK.md`

The TASK.md file contained detailed requirements for a web-based platformer game with:
- 10+ progressively harder levels
- Player movement, jumping, shooting
- Enemy AI and collision detection
- Cyberpunk theme with real sprites (not colored rectangles)
- Visual verification of the final result

**Model Configuration:**
| Component | Model | Hardware |
|-----------|-------|----------|
| LLM | `qwen/qwen3.5-35b-a3b` | NVIDIA DGX Spark |
| Vision | `qwen/qwen3-vl-4b` | NVIDIA DGX Spark |

**Total Time:** 1 hour 9 minutes (fully autonomous)

### What the Agent Did

1. **Planning Phase** - Broke down the project into components:
   - Rendering engine, physics system, input handling
   - Game state management, level design
   - Asset generation (procedural sprites)

2. **Implementation** - Created the game structure:
   - `index.html` - Game canvas and UI overlay
   - `styles.css` - Cyberpunk neon styling
   - `main.js` - Full game engine with 10 levels
   - `assets/sprites/` - Procedurally generated pixel art

3. **Visual Verification** - Used `/vision verify` to confirm UI:

   ```
   /vision verify http://localhost:8080 "Should show CYBER-RUNNER title,
   NEON PROTOCOL subtitle, story text, controls info, and START MISSION button"
   ```

   Vision response:
   ```
   1. PASS

   2. What you actually see:
   - The screen displays "CYBER-RUNNER" in large, glowing teal letters
   - Below it, "NEON PROTOCOL" is shown in a smaller, matching font
   - Story text: "The year is 2087. The city has fallen to the AI..."
   - A "CONTROLS:" box lists: "→ Move | SPACE / ↑ Jump | SHIFT Shoot"
   - A prominent "START MISSION" button is centered below

   3. No issues — all expected elements are present and correctly formatted.
   ```

4. **Supervisor Loop** - Continuously evaluated progress until complete

### Final Result

**Start Screen:**

![Platformer game start screen](assets/zero-shot-platformer-game1.png)

**Gameplay:**

![Platformer game gameplay](assets/zero-shot-platformer-game2.png)

### Vision Verification Logs

All vision requests were automatically logged to `.vision_logs/`:

```
.vision_logs/
├── 2026-03-23_20-41-29_analyze.md    # Initial UI analysis
├── 2026-03-23_20-43-16_analyze.md    # Start screen verification
├── 2026-03-23_20-43-16_analyze.png   # Screenshot
├── 2026-03-23_20-56-51_verify.md     # Full UI verification (PASS)
├── 2026-03-23_20-56-51_verify.png    # Screenshot
├── 2026-03-23_20-58-25_verify.md     # Final verification (PASS)
└── 2026-03-23_20-58-25_verify.png    # Screenshot
```

### Key Takeaways

1. **Zero-shot capability** - Complex game built from a single task file
2. **Self-verification** - Agent used vision to confirm UI matched requirements
3. **Autonomous completion** - No human intervention for 1+ hour
4. **Quality output** - Playable game with proper sprites, not placeholders

## Tracing with Langfuse

Track and evaluate agent sessions using Langfuse. This helps you understand agent behavior, debug issues, and measure performance.

### Setup

1. Add Langfuse credentials to `.env`:
   ```env
   TRACE_TO_LANGFUSE=true
   LANGFUSE_PUBLIC_KEY=pk-lf-xxx
   LANGFUSE_SECRET_KEY=sk-lf-xxx
   LANGFUSE_HOST=http://host.docker.internal:3000
   ```

2. Rebuild and run: `docker compose build && ./run.sh`

### Example: Todo App Task

Here's an example of tracing a simple task: "write a simple web based todo app"

**User Prompt:**

![User prompt for todo app task](assets/example-todo-app/user-prompt.png)

**Traces in Langfuse:**

All turns from the session are captured as individual traces, grouped by session ID:

![Traces overview in Langfuse](assets/example-todo-app/traces.png)

**Final Turn Details:**

Each trace shows the input (user message or skill invocation), output (Claude's response), and tool calls as spans:

![Final turn trace details](assets/example-todo-app/final-turns-trace.png)

**Produced Solution:**

The agent autonomously created a complete todo app:

![Completed todo app solution](assets/example-todo-app/produced-solution.png)

### What Gets Traced

| Component | Description |
|-----------|-------------|
| **Trace** | One per turn (user message → assistant response) |
| **Generation** | LLM call with input, output, and token usage |
| **Spans** | Tool calls (Read, Write, Bash, Skill, etc.) |
| **Session** | Groups all turns from one conversation |

### Debugging Tips

```bash
# Check if hooks are firing
docker exec $(docker ps -q -f name=claude) cat ~/.claude/state/hook.log

# View recent traces via API
curl -s -H "Authorization: Basic $(echo -n 'pk:sk' | base64)" \
  "http://localhost:3000/api/public/traces?limit=5" | jq '.data[].name'
```

See [docs/TRACING.md](docs/TRACING.md) for detailed setup and troubleshooting.
