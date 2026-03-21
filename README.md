# Claude Autopilot Sandbox

**Version 1.0.0** | [Changelog](CHANGELOG.md)

Run Claude Code CLI autonomously in a Docker sandbox with your own local LLM. 100% local execution with full tool access for long-running, unattended task completion.

## Features

- **100% Local** - Uses your own LLM (LM Studio, Ollama, vLLM, etc.)
- **Autonomous Operation** - Self-sustaining supervisor loop keeps Claude working
- **Vision Capabilities** - Screenshot and analyze UIs, verify web apps visually
- **Full Sandbox** - Claude has unrestricted access inside the container
- **Isolated Workspaces** - Run multiple projects simultaneously

## Quick Start

```bash
# 1. Clone and configure
git clone <repository-url>
cd claude-autopilot-sandbox
cp .env.example .env
# Edit .env with your LLM settings

# 2. Build and run
docker compose build
./run.sh

# 3. Give Claude a task and let it work
```

## Architecture

```
+---------------------------------------------------------------+
|                     Docker Container                           |
|  +-----------------------------------------------------------+ |
|  |                    Claude Code CLI                         | |
|  |  (Native installation via claude.ai/install.sh)           | |
|  +-----------------------------------------------------------+ |
|                            |                                   |
|  +-------------+  +-------------+  +-------------------------+ |
|  |   Skills    |  |  Subagents  |  |       Workspace         | |
|  | /vision     |  | debugger    |  | ~/workspace/            | |
|  | /supervisor |  | web-search  |  | (mounted volume)        | |
|  | /websearch  |  | code-review |  |                         | |
|  +-------------+  +-------------+  +-------------------------+ |
+---------------------------------------------------------------+
                            |
                   HTTP (OpenAI-compatible API)
                            |
+---------------------------------------------------------------+
|              Your LLM Backend (LM Studio, Ollama, etc.)       |
+---------------------------------------------------------------+
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```env
# LLM Backend
LLM_HOST=192.168.7.103
LLM_PORT=11234
LLM_AUTH_TOKEN=lmstudio
LLM_MODEL=your-model-name

# Vision Model (optional)
VISION_MODEL=qwen/qwen3-vl-4b

# Whoogle Search (optional)
WHOOGLE_URL=http://your-whoogle:5000

# Langfuse Tracing (optional - for agent evaluation)
TRACE_TO_LANGFUSE=true
LANGFUSE_PUBLIC_KEY=pk-lf-xxx
LANGFUSE_SECRET_KEY=sk-lf-xxx
LANGFUSE_HOST=http://host.docker.internal:3000
LANGFUSE_PROJECT=claude-autopilot-sandbox

# Resource Limits
MEMORY_LIMIT=16G
MEMORY_RESERVATION=2G

# Workspace
WORKSPACE_NAME=default
```

### LLM Backend Setup

See [LM_STUDIO_SETUP.md](LM_STUDIO_SETUP.md) for detailed instructions on setting up LM Studio with large context models.

**LM Studio (quick start):**
```bash
# Install LM Studio
curl -fsSL https://lmstudio.ai/install.sh | bash

# Start server
lms server start -p 11234 --bind 0.0.0.0

# Load model with large context
lms load <model-name> --gpu max -c 131072 -y
```

**Ollama:**
```bash
ollama serve
ollama pull llama3.3:70b
# Set LLM_PORT=11434 in .env
```

## Usage

### Running Claude

```bash
# Default workspace
./run.sh

# Named workspace (isolated)
./run.sh my-project
./run.sh client-work

# Direct docker-compose (with port access)
WORKSPACE_NAME=myproject docker compose run --rm --service-ports claude-local
```

Each workspace is isolated in `./workspaces/<name>/` and mapped to `/home/claude/workspace` in the container.

### Accessing Web Apps from Host

When the agent runs a web server inside the container, you can access it from your browser. **Ports are mapped with a +20000 offset** to avoid conflicts:

| Agent says | Access from host |
|------------|------------------|
| `http://localhost:3000` | `http://localhost:23000` |
| `http://localhost:5000` | `http://localhost:25000` |
| `http://localhost:8000` | `http://localhost:28000` |
| `http://localhost:8080` | `http://localhost:28080` |

**Rule of thumb:** Add 20000 to any port the agent mentions.

### Autonomous Operation

Claude operates in a self-sustaining loop:

1. **You give a task** - Type your request
2. **Claude breaks it down** - Creates todos to track progress
3. **Claude works** - Implements each todo, runs tests
4. **Claude verifies** - Uses vision to verify UI if applicable
5. **Supervisor evaluates** - Claude calls `/supervisor` to check progress
6. **Loop continues** - Until all todos complete and tests pass

**You don't need to keep prompting** - Claude will keep working autonomously.

### Vision Capabilities

Claude can see and analyze images. Essential for UI testing.

```bash
# Analyze any image
/vision analyze ./screenshot.png "What do you see?"

# Screenshot and analyze a web page
/vision analyze http://localhost:5000 "Describe this UI"

# Verify UI matches expectations
/vision verify http://localhost:5000 "Should show: login form with email and password fields"

# Extract text from image (OCR)
/vision ocr ./document.png

# View recent vision logs
/vision logs
```

**UI Testing Workflow:**
```bash
# Start app
python app.py &
sleep 2

# Verify UI
~/.claude/skills/vision/vision.sh verify http://localhost:5000 \
    "Should show: a title, input form, and todo list"
```

All vision requests are logged to `~/workspace/.vision_logs/` with screenshots.

## Skills

Skills are invoked with `/skillname` syntax:

| Skill | Usage | Description |
|-------|-------|-------------|
| `/plan` | `/plan` | Create implementation plan (no approval needed) |
| `/tasks` | `/tasks add/list/done` | Track task progress |
| `/vision` | `/vision analyze/verify/ocr <image_or_url>` | Image analysis, UI verification, OCR |
| `/supervisor` | `/supervisor` | Check progress and decide next action |
| `/websearch` | `/websearch <query>` | Web search via Whoogle |
| `/memory` | `/memory store/recall <text>` | Persistent memory across sessions |
| `/notes` | `/notes add/read <name>` | Note-taking system |
| `/pkg-install` | `/pkg-install apt/pip <pkg>` | Install packages at runtime |
| `/code-runner` | `/code-runner python '<code>'` | Execute code snippets |
| `/file-convert` | `/file-convert pdf2txt <in> <out>` | Convert between formats |
| `/api-tester` | `/api-tester GET <url>` | Test REST APIs |
| `/sql-query` | `/sql-query sqlite <db> <query>` | Execute SQL queries |

## Subagents

Claude can delegate to specialized subagents:

| Agent | Purpose |
|-------|---------|
| `debugger` | Bug investigation and error fixing |
| `web-search-subagent` | Research tasks using web search |
| `code-reviewer` | Code quality and security review |

## Tracing with Langfuse

Track and evaluate agent sessions using Langfuse (self-hosted).

### Quick Setup

1. Add to `.env`:
   ```env
   TRACE_TO_LANGFUSE=true
   LANGFUSE_PUBLIC_KEY=pk-lf-xxx
   LANGFUSE_SECRET_KEY=sk-lf-xxx
   LANGFUSE_HOST=http://host.docker.internal:3000
   ```

2. Rebuild: `docker compose build --no-cache`

3. Run a session - traces appear in Langfuse UI

### What Gets Traced

- Every turn (user message → assistant response)
- LLM calls with token usage
- Tool calls (Read, Write, Bash, etc.)
- Grouped by session for conversation view

See [docs/TRACING.md](docs/TRACING.md) for detailed setup and debugging.

## The Supervisor System

The supervisor keeps Claude working autonomously by checking progress at the end of each turn.

### How It Works

```
Agent works -> calls /supervisor -> Supervisor checks todos & tests -> Outputs instructions -> Agent continues
```

**Supervisor decisions:**
- **ERRORS FOUND** - Tests fail or errors exist - continue fixing
- **PROGRESS OK** - Tests pass, todos remain - continue with next todo
- **ALL COMPLETE** - All done, tests pass - wait for user

### Example Session

```
$ ./run.sh flask-app

You: Build a Flask todo app with add, complete, and delete functionality

[Claude creates todos]
[Claude implements app.py, templates, tests]
[Claude runs tests - they pass]
[Claude calls /supervisor]

Supervisor: PROGRESS OK - Continue with next todo
[Claude continues...]

[Eventually all todos complete]

Supervisor: ALL COMPLETE - Waiting for user
```

## Workspace Management

### Structure

Each workspace contains:
```
./workspaces/myproject/
├── app.py                # Your project files
├── tests/
├── .memory/              # Persistent memory
├── .notes/               # Notes
├── .vision_logs/         # Vision request logs
└── CLAUDE.md             # Workspace instructions
```

### Customizing CLAUDE.md

Edit the workspace's `CLAUDE.md` to add project-specific instructions:

```markdown
# Project Instructions

## Project-Specific Rules
- This is a Python 3.11 project
- Use pytest for testing
- Follow PEP 8

## Autonomous Operation
... (keep the supervisor instructions)
```

## Installed Tools

The container includes:

| Category | Tools |
|----------|-------|
| **Languages** | Python 3, Node.js |
| **PDF** | poppler-utils (pdftotext, pdftoppm) |
| **Databases** | sqlite3, postgresql-client |
| **Browser** | Playwright with Chromium |
| **Display** | Xvfb, ImageMagick (for GUI apps) |
| **Python** | pandas, requests, beautifulsoup4, playwright |
| **Utilities** | git, curl, jq, htop, vim |

### Installing Additional Packages

```bash
# Use the skill
/pkg-install pip numpy matplotlib
/pkg-install apt ffmpeg

# Or use sudo directly
sudo apt-get install -y package-name
```

Note: Packages installed at runtime don't persist after container exit.

## Building

```bash
# Standard build
docker compose build

# Full rebuild (no cache)
docker compose build --no-cache
```

## Troubleshooting

### Cannot connect to LLM

1. Verify LLM is running: `curl http://<LLM_HOST>:<LLM_PORT>/v1/models`
2. Check `.env` settings
3. Container uses host network - ensure LLM is accessible from host

### Model not found

- Verify `LLM_MODEL` matches exactly what your backend expects
- LM Studio: use model identifier shown in UI
- Ollama: use `ollama list` to see names

### Vision not working

1. Check `VISION_MODEL` is set in `.env`
2. Ensure vision model is loaded in your LLM backend
3. Test: `curl -X POST http://<host>:<port>/v1/chat/completions -d '...'`

### WebSearch not working

- Native WebSearch only works with Anthropic's API
- Use `/websearch` skill instead (requires Whoogle)
- Leave `WHOOGLE_URL` empty if you don't have Whoogle

### Container exits immediately

```bash
# Debug with shell access
docker compose run --rm --entrypoint /bin/bash claude-local

# Check environment
env | grep -E 'ANTHROPIC|LLM|VISION'
```

### Cannot access web app from browser

If the agent starts a web server but you can't access it from your Mac:

1. **Add 20000 to the port** - Agent says `localhost:5000`, use `localhost:25000`
2. **Restart container** - Port mappings only apply on fresh start
3. **Check server binding** - Server must bind to `0.0.0.0`, not `127.0.0.1`

### Out of memory

- Increase `MEMORY_LIMIT` in `.env`
- Use a smaller model
- Close other memory-intensive applications

### Cannot create files in subdirectories (exFAT issue)

If file creation works in workspace root but fails in subdirectories like `templates/`:

```
touch: cannot touch 'templates/test.txt': No such file or directory
```

This is caused by **exFAT filesystem** issues with Docker bind mounts. exFAT doesn't properly support Unix permissions, causing Docker's virtualization layer to fail.

**Fix:** Store workspaces on an internal APFS/HFS+ drive:

```env
# In .env
WORKSPACE_BASE=/Users/yourusername/claude-workspaces
```

Then run normally: `./run.sh myproject`

## Security

The container is a secure sandbox:

- **Isolated** - Cannot access host filesystem (except workspace)
- **Non-root** - Runs as unprivileged `claude` user
- **Removed on exit** - `--rm` flag cleans up
- **Memory limited** - Prevents runaway processes
- **Full automation inside** - Claude has unrestricted access within the sandbox

This is safe because all changes are isolated to the mounted workspace volume.

## File Structure

```
claude-autopilot-sandbox/
├── VERSION                # Current version (1.0.0)
├── CHANGELOG.md           # Version history
├── .env.example           # Configuration template
├── .env                   # Your configuration (gitignored)
├── .gitignore
├── .dockerignore          # Docker build exclusions
├── docker-compose.yml     # Service definition
├── Dockerfile             # Container build
├── run.sh                 # Workspace launcher
├── watchdog.sh            # External nudge script (optional)
├── INSTALL.md             # Detailed installation guide
├── USER_MANUAL.md         # User documentation
├── CLAUDE.md              # Template copied to new workspaces
├── LM_STUDIO_SETUP.md     # Guide for setting up LM Studio
├── docs/                  # Additional documentation
│   └── TRACING.md         # Langfuse tracing setup guide
├── assets/                # Screenshots and images
│   └── example-todo-app/  # Example task screenshots
├── scripts/               # Runtime scripts
│   └── init-workspace.sh  # Workspace initialization (runs at startup)
├── hooks-backup/          # Hooks (copied into image)
│   └── langfuse_stop_hook.sh  # Langfuse tracing hook
├── skills-backup/         # Skills (copied into image)
│   ├── plan/              # Implementation planning
│   ├── tasks/             # Task tracking
│   ├── vision/            # Image/screenshot analysis
│   ├── supervisor/        # Progress checking
│   ├── websearch/         # Web search
│   ├── memory/            # Persistent memory
│   └── ...
└── agents-backup/         # Subagents (copied into image)
    ├── debugger.md
    ├── web-search-subagent.md
    └── code-reviewer.md
```

**Note:** The `workspaces/` directory is created automatically when you first run `./run.sh`. It's gitignored since it contains user data.

## License

[Your license here]
