# Changelog

All notable changes to Claude Autopilot Sandbox will be documented in this file.

## [1.1.0] - 2026-03-25

### Added
- **Browser Skill** (`/browser`) - New skill wrapping Playwright CLI
  - Screenshots save to files (no binary in response)
  - 4x fewer tokens vs MCP approach
  - Commands: navigate, snapshot, click, type, screenshot
- **QA Agent** (`qa-agent`) - Verifies test coverage before supervisor
  - Runs in isolated context
  - Checks requirements coverage, UI verification, edge cases
  - Returns VERIFIED or GAPS FOUND
- **Task Completion Loop** - Documented full workflow
  - plan → tasks → work → test → qa-agent → supervisor
  - See `docs/TASK_COMPLETION_LOOP.md`
- **TODO.md** - Project-level todo tracking with dates and status

### Fixed
- **Hook Timeout** - Increased from 60s to 300s for large transcripts
- **Hook Content Truncation** - Tool results capped at 10KB, outputs at 20KB
- **Session Crashes** - Replaced MCP with CLI (MCP returned binary data that crashed local LLMs)
- **Extended Thinking Error** - Added `MAX_THINKING_TOKENS=0` for local LLM compatibility

### Changed
- **Playwright MCP → CLI** - Switched from `@playwright/mcp` to `@playwright/cli`
  - CLI saves screenshots to files instead of returning binary in response
  - Designed specifically for AI coding agents with filesystem access
- **Websearch Skill** - Now uses `/browser` skill (Playwright CLI)
- **Web-Researcher Subagent** - Updated to use `/browser` skill
- **CLAUDE.md** - Replaced MCP instructions with `/browser` skill usage
- **Supervisor** - Uses marker file for completion detection

### Removed
- **Playwright MCP** - Removed MCP server registration (replaced by CLI)
- **Whoogle Websearch** - Removed `websearch-whoogle-backup/` skill
- **Deprecated Skills** - Removed `/notes`, `/code-runner`, `/api-tester` (unused)

### Infrastructure
- **Xvfb** - Starts automatically for headless browser
- **Dockerfile** - Installs `@playwright/cli` instead of `@playwright/mcp`

## [1.0.0] - 2026-03-21

### Added
- **Langfuse Tracing** - Full session tracing with Langfuse integration
  - Stop hook captures every turn (user → assistant)
  - Aggregates LLM responses and token usage
  - Records tool calls as spans
  - Groups traces by session ID
- **Plan Skill** (`/plan`) - Create implementation plans without approval
- **Tasks Skill** (`/tasks`) - Track task progress during autonomous operation
- **Vision Skill** (`/vision`) - Screenshot and analyze UIs, verify web apps
- **Supervisor System** - Autonomous loop that keeps Claude working
- **Docker Sandbox** - Isolated container with full tool access
- **Local LLM Support** - Works with LM Studio, Ollama, vLLM, etc.
- **Workspace Isolation** - Separate workspaces per project

### Configuration
- Environment-based configuration via `.env`
- Project-level Claude Code settings via `init-workspace.sh`
- Hooks directory for extensibility

### Documentation
- README with quick start and architecture
- USER_MANUAL with detailed usage guide
- TRACING.md with Langfuse setup instructions
- Example screenshots for todo app task

### Skills
- `/plan` - Implementation planning
- `/tasks` - Task tracking
- `/vision` - Image analysis and UI verification
- `/supervisor` - Progress evaluation
- `/websearch` - Web search via Whoogle
- `/memory` - Persistent memory
- `/notes` - Note-taking
- `/pkg-install` - Package installation
- `/code-runner` - Code execution
- `/file-convert` - File format conversion
- `/api-tester` - HTTP API testing
- `/sql-query` - SQL query execution

### Subagents
- `debugger` - Bug investigation
- `web-search-subagent` - Research tasks
- `code-reviewer` - Code quality review
