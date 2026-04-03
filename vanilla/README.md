# Vanilla Claude Code Container

Run Claude Code with Anthropic API in a Docker container with full permissions and optional Langfuse tracing.

## Requirements

- Docker
- Anthropic API key (`ANTHROPIC_API_KEY`)
- Optional: Langfuse instance for tracing

## Quick Start

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env and add your ANTHROPIC_API_KEY

# Build the container
docker compose build

# Run with default workspace
./run.sh

# Run with named workspace
./run.sh my-project
```

## Features

### Native Claude Tools
All native Claude Code tools are enabled and allowed:
- **WebSearch** - Search the web
- **WebFetch** - Fetch URL content
- **TodoWrite** - Track tasks
- **EnterPlanMode** - Plan complex tasks
- **Read/Write/Edit** - Full file access
- **Bash** - Shell commands with passwordless sudo
- **Glob/Grep** - Code search
- **Task** - Spawn subagents

### Subagents
Available subagents (in `~/.claude/agents/`):
- `debugger` - Deep error investigation
- `web-researcher` - Multi-source web research
- `code-reviewer` - Quality/security review
- `qa-agent` - Test coverage verification
- `worker` - Parallel task execution

### Browser Automation
Playwright with Chromium is pre-installed for:
- Taking screenshots of web apps
- Visual verification of built UIs
- Form filling and web interaction
- Web scraping

See `~/.claude/skills/browser/SKILL.md` for examples.

### Langfuse Tracing (Optional)
Enable tracing to monitor Claude's activity:

```bash
export TRACE_TO_LANGFUSE=true
export LANGFUSE_HOST=http://localhost:3000
export LANGFUSE_PUBLIC_KEY=pk-...
export LANGFUSE_SECRET_KEY=sk-...
export LANGFUSE_PROJECT=claude-vanilla
./run.sh
```

Or add to `.env` file in this directory.

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | Yes | - | Your Anthropic API key |
| `CLAUDE_MODEL` | No | claude-sonnet-4-20250514 | Model to use |
| `TRACE_TO_LANGFUSE` | No | false | Enable Langfuse tracing |
| `LANGFUSE_HOST` | No | http://localhost:3000 | Langfuse server URL |
| `LANGFUSE_PUBLIC_KEY` | No | - | Langfuse public key |
| `LANGFUSE_SECRET_KEY` | No | - | Langfuse secret key |
| `LANGFUSE_PROJECT` | No | claude-vanilla | Langfuse project name |

### Using .env File

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
# Edit .env with your keys
```

See `.env.example` for all available options.

## Workspaces

Workspaces are stored in `./workspaces/<name>/` and mounted to `/home/claude/workspace/` in the container.

Each workspace is isolated and persists between runs.

## Port Mappings

Container ports are mapped with +30000 offset:
- 8000 → 38000
- 8080 → 38080
- 3000 → 33000
- 5000 → 35000

When running a web server in the container, bind to `0.0.0.0` and access via the mapped port.

## Differences from Local LLM Version

| Feature | Local LLM | Vanilla |
|---------|-----------|---------|
| API | LM Studio/Ollama | Anthropic |
| Web Search | DuckDuckGo skill | Native WebSearch |
| Vision | LM Studio vision | Not available |
| Browser | Playwright | Playwright |
| Skills | Many custom skills | Native tools + browser |
| Tracing | Langfuse | Langfuse |

## Building

```bash
docker compose build
```

## Troubleshooting

### API Key Issues
Ensure `ANTHROPIC_API_KEY` is set before running:
```bash
echo $ANTHROPIC_API_KEY  # Should show your key
```

### Tracing Not Working
Check the hook logs:
```bash
cat workspaces/<name>/.claude/state/hook.log
```

### Network Issues
The container uses `host.docker.internal` to access host services (like Langfuse).
