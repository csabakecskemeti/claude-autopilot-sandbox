# Claude Autopilot Sandbox - Development Instructions

## What This Project Is

This project builds a **Docker container** that runs Claude Code CLI autonomously with local LLMs (LM Studio, Ollama, etc.).

**Critical distinction - there are TWO Claudes:**

| Claude | Where | Purpose |
|--------|-------|---------|
| **You (outer)** | Host machine | Developing this project, editing source files |
| **Inner Claude** | Docker container | Running autonomously, building apps for users |

## Two CLAUDE.md Files!

| File | Purpose | Git Status |
|------|---------|------------|
| `/CLAUDE.md` (this file) | Instructions for YOU developing this project | gitignored |
| `/claude-backup/CLAUDE.md` | Instructions for inner Claude in container | tracked |

The `claude-backup/CLAUDE.md` gets copied into Docker images during build.

## Project Structure

```
/
├── CLAUDE.md              # THIS FILE (for you, gitignored)
├── claude-backup/
│   └── CLAUDE.md          # For inner Claude (copied to container)
├── Dockerfile             # Container build definition
├── docker-compose.yml     # Service configuration
├── scripts/
│   └── init-workspace.sh  # Runs at container startup (creates settings.json)
├── skills-backup/         # Skills copied to ~/.claude/skills/ in container
├── agents-backup/         # Subagents copied to ~/.claude/agents/
├── hooks-backup/          # Hooks copied to ~/.claude/hooks/
├── workspaces/            # Mounted volumes (gitignored)
└── docs/                  # Project documentation
```

## Key Files to Know

### Container Configuration
- **`Dockerfile`** - Packages, Node/Python install, Claude CLI setup
- **`docker-compose.yml`** - Port mappings, env vars, volume mounts
- **`scripts/init-workspace.sh`** - Creates project-level settings.json with hooks + MCP servers

### Inner Claude's Tools
- **`skills-backup/`** - Bash skills invoked via `/skillname`
- **`agents-backup/`** - Subagent definitions (debugger, web-researcher, etc.)
- **`hooks-backup/`** - Event hooks (e.g., Langfuse tracing on Stop)
- **`claude-backup/CLAUDE.md`** - Instructions for autonomous operation

### Documentation
- **`README.md`** - User-facing documentation
- **`docs/PROJECT_CONTEXT.md`** - Context for understanding this project
- **`docs/TRACING.md`** - Langfuse setup
- **`docs/WEBSEARCH_MIGRATION.md`** - Whoogle → Playwright MCP migration notes

## Common Tasks

### Adding a New Skill
1. Create folder in `skills-backup/<skillname>/`
2. Add `SKILL.md` with frontmatter (name, description, allowed-tools)
3. Add implementation script(s)
4. Rebuild: `docker compose build`

### Modifying Container Startup
- Edit `scripts/init-workspace.sh`
- This creates `~/workspace/.claude/settings.json` inside container
- Hooks and MCP servers are configured here

### Browser Automation
Uses Playwright CLI (not MCP) via `/browser` skill. See `skills-backup/browser/`.

### Testing Changes
```bash
docker compose build --no-cache
./run.sh test-workspace
```

## Important Notes

1. **Settings hierarchy**: Project-level settings (`workspace/.claude/settings.json`) override user-level (`~/.claude/settings.json`)

2. **Port mappings**: Container ports are mapped with +20000 offset (5000 → 25000)

3. **Skills path**: `skills-backup/` on host → `~/.claude/skills/` in container

4. **Xvfb**: Container has virtual display for headless browser (Playwright CLI)

5. **No MCP**: We use Playwright CLI (not MCP) to avoid binary response issues with local LLMs

## TODO.md - Mandatory

**You MUST maintain `TODO.md` in the project root.**

When working on this project:
1. Check `TODO.md` for open items before starting
2. Add new TODOs with date, status, priority
3. Link to related docs (e.g., `docs/WEBSEARCH_PLAN.md`)
4. Mark items complete when done
5. Add comments/notes as you learn things

Format:
```markdown
### TODO-XXX: Short description
**Status:** 🔴 Open | 🟡 Partial | 🟢 Done
**Created:** YYYY-MM-DD
**Priority:** Critical | High | Medium | Low

Description and notes...
```

## Don't Forget

- After editing `claude-backup/CLAUDE.md`, changes only apply after `docker compose build`
- The root `CLAUDE.md` (this file) is gitignored - it's personal to your dev environment
- Always test changes with a fresh container build
- **Check and update TODO.md** when making changes
