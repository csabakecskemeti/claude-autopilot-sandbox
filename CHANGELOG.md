# Changelog

All notable changes to Claude Autopilot Sandbox will be documented in this file.

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
