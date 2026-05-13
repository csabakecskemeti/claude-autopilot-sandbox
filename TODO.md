# Project TODO List

**Last Updated:** 2026-05-12

**Mandatory:** Keep this file updated. Add dates, status, and links to related docs.

**Session Memory:** Check `.memory/` folder for detailed session notes (latest: `session_20260507.md`)

---

### TODO-013: Agent Can Bypass Own Guardrails (Security Risk)
**Status:** 🟢 Done (tested & verified)
**Created:** 2026-05-12
**Completed:** 2026-05-13
**Priority:** Critical (Security)
**Branch:** `feature/config-hardening`

**Problem:** Agent has full sudo access inside container and can edit:
- `~/.claude/hooks/langfuse_stop_hook.sh` - Remove supervisor call, fake completion
- `~/workspace/.claude/settings.json` - Disable hooks entirely
- `~/CLAUDE.md` - Change its own behavioral instructions

**Solution:** Read-only bind mounts (kernel-enforced, agent can't bypass even with sudo)

**Implementation:** See `docs/CONFIG_HARDENING_PLAN.md`

**Files modified:**
- `run.sh` - Added `generate_settings_json()`, generates config on host before container start
- `docker-compose.yml` - Added 4 read-only bind mounts for protected files
- `scripts/init-workspace.sh` - Simplified, removed config generation, added mount verification

**Protected paths:**
| Path | Mount Type |
|------|------------|
| `~/.claude/hooks/*` | Directory, ro |
| `~/.claude/CLAUDE.md` | File, ro |
| `~/workspace/.claude/settings.json` | File, ro |
| `~/workspace/CLAUDE.md` | File, ro |

**Test results (2026-05-13):**
- ✅ Agent can READ all config files
- ✅ Agent gets "EROFS: read-only file system" when trying to modify hooks
- ✅ Agent gets "EROFS: read-only file system" when trying to modify CLAUDE.md
- ✅ Agent gets "EROFS: read-only file system" when trying to modify settings.json
- ✅ Agent CAN still write to workspace (mysettings.txt created successfully)

**Related:** `docs/CONFIG_HARDENING_PLAN.md`, TODO-001 (workflow enforcement)

---

### TODO-012: Task Isolation & Image Blocking
**Status:** 🟢 Done (tested & committed)
**Completed:** 2026-05-12
**Created:** 2026-05-02
**Updated:** 2026-05-07
**Priority:** High

**Task Isolation (Implemented):**
- Each worker gets isolated folder: `workspaces/{name}_{timestamp}/`
- Embedded supervisor per agent (removed shared supervisor)
- Dynamic port allocation (30000-60000)
- Background mode with detach/reattach (`Ctrl+P,Q`)
- New commands: `make workers`, `make worker-info`, `make attach`, `make stop`

**Image Read Blocking (Implemented):**
- PreToolUse hook blocks Read tool on image files
- Prevents "Only text tool_result blocks" error with local LLMs
- Agent uses `/vision` skill instead
- Supervisor uses CLI tools (tesseract)

**Files:** See `.memory/session_20260507.md` for full list

**Next Steps:**
- [ ] `make build-clean` to rebuild
- [ ] Test worker creation and detach/reattach
- [ ] Test image blocking
- [ ] Commit to `feature/standalone-services`

**Related:** `docs/TASK_ISOLATION_PLAN.md`

---

### TODO-README-SYNC: README + make test match current stack
**Status:** 🟢 Done
**Created:** 2026-05-03
**Priority:** Low

README rewritten for per-task supervisor, `run.sh` layout, `allocate-ports`, `pick-running-worker`, Makefile commands. Removed obsolete shared-supervisor / `PORT_PREFIX` / `make supervisor-start` narrative. `make test` supervisor section now counts `claude-supervisor-*` containers instead of probing localhost:8080.

---

### TODO-CLI-WORKER: worker / worker-info / attach W= naming
**Status:** 🟢 Done
**Created:** 2026-05-03
**Priority:** Medium

CLI: `make worker` with **`W=`** / **`w=`** / **`WORKER=`** (label), **`T=`** / **`TASK=`**, **`TF=`** / **`TASKFILE=`**; lifecycle uses **`W=`** / **`w=`** / **`WORKER=`** (full id) or omit for picker. **`stop`/`attach`/`worker-info`** are shell-only (BSD make–safe, no **`$(or …)`**). Picker: `scripts/pick-running-worker.sh`. **Makefile pins `W`/`w`/`WORKER` to empty** at parse time so stray **`export W=…`** (or `WORKER`) in the shell cannot hijack `make worker-info` / `attach` / `stop` without an explicit `W=…` on the command line. **`make stop W=…`** now updates **`metadata.json`** (`state`, `stop_time`, `exit_code: null`); **`make workers`** / **`make status`** use **`scripts/worker-list-line.sh`**: reconcile metadata with **agent + supervisor** containers — **orphaned** when supervisor is up without agent; **stopped** when metadata says running but neither container is up. **`scripts/stop-worker-containers.sh`** stops by **metadata names plus** `${CONTAINER_PREFIX}-(agent|supervisor)-<WID>` **fallbacks** (deduped) so a supervisor is not left behind if metadata names were wrong or `docker stop` was previously swallowed; **`make worker-clean`** uses **`stop-worker-containers.sh --rm`**. **`make stop`** with no **`W=`** uses **`pick-running-worker.sh`** (same as attach / worker-info).

---

### TODO-DOC-EXAMPLE-TASKS: Example task specs location
**Status:** 🟢 Done
**Created:** 2026-04-04
**Priority:** Low

Example task markdown and `zero-shot-platformer-game/TASK.md` live under `docs/example_tasks/`. Copy into a workspace (or point the agent at them) when running demos.

---

### TODO-HOOK-SUPERVISOR: Stop hook stdout + supervisor always-on
**Status:** 🟢 Done
**Created:** 2026-04-05
**Priority:** High

Stop hook is **single file** again: `langfuse_stop_hook.sh` runs Langfuse then supervisor in process order. (Multiple Stop commands in settings run **in parallel** per Claude Code docs, so split hooks do not guarantee Langfuse-before-supervisor.) `supervisor_eval_stop_hook.sh` removed. Comments in `init-workspace.sh` + hook header document this. Updated loop behavior: supervisor now runs even when `stop_hook_active=true`, so stop decisions are re-evaluated every continued turn; `MAX_CONTINUE_CYCLES` remains the safety exit. Optional `SUPERVISOR_AUTONOMY_APPEND` appends a short autonomous-work nudge to every NOT_COMPLETE block reason (disable with `false`). Supervisor prompt (`supervisor/SUPERVISOR_PROMPT.md`): must read `.vision_logs/*.md`; explicit FAIL → `not_complete` (stops LLM claiming “visual verification” from code alone).

---

## Observations: Workflow Test (2026-03-31)

### Test Session: 8bfd0686-0041-4cbb-be04-6464141c4031

**Model:** openai.gpt-oss-120b (OpenAI OSS 120B)
**Task:** Build personal expense tracker web app

### What Worked Well
- ✅ Agent called `/workflow start` first
- ✅ Agent used `/plan` skill
- ✅ Agent created tasks using `/tasks` bash skill (not TodoWrite)
- ✅ Agent marked tasks working/done as it progressed
- ✅ Agent attempted `/vision verify` for UI verification
- ✅ Agent used `sudo` to install missing dependencies (self-healing)
- ✅ App was actually functional

### What Failed

| Issue | Description | Impact |
|-------|-------------|--------|
| **Task left incomplete** | Task 4 (Test) never marked done with `tasks.sh done 4` | .tasks shows `[>]` not `[x]` |
| **Vision fail not retried** | Vision verify FAILED (no data, no chart), agent rationalized instead of fixing | UI not properly verified |
| **No retry after fix** | Agent created test_ui.py to add data but never re-ran vision verify | Fix was not validated |
| **No qa-agent called** | Skipped QA step entirely | Test coverage not verified |
| **No supervisor called** | Agent declared "All core features are now functional" and stopped | Violated core workflow rule |
| **Self-declared completion** | Agent announced done instead of letting supervisor decide | Exact behavior we're trying to prevent |

### Root Causes

1. **Vision failure not blocking** - Agent treated FAIL as informational, not as "must fix"
2. **No completion checklist** - Agent has no systematic check before stopping
3. **"Never declare done" rule ignored** - Despite multiple warnings in CLAUDE.md
4. **Rationalization over fixing** - Agent said "missing due to no entries" instead of adding entries and retrying

### Proposed Fixes

| Fix | Description | Priority |
|-----|-------------|----------|
| **Vision fail = must retry** | If vision verify returns FAIL, agent MUST fix and re-run until PASS | High |
| **Completion checklist** | Add explicit checklist: all tasks [x], vision PASS, qa-agent called, supervisor called | High |
| **Stronger supervisor messaging** | Make it impossible to miss: "STOP. Call /supervisor. Do not output anything else." | High |
| **Workflow validation** | `/workflow validate` should check all requirements before allowing completion | Medium |
| **Hook enforcement** | PreToolCall hook could block certain actions if workflow incomplete | Low |

### Files with Issues Found
- `.tasks` - Task 4 left as `[>]` (in progress)
- `.vision_logs/2026-03-31_15-39-29_verify.md` - Shows FAIL status
- Agent output - Declared completion without supervisor

---

## Critical: Workflow Enforcement

### TODO-001: Implement Workflow State Machine
**Status:** 🔴 Open
**Created:** 2026-03-25
**Updated:** 2026-03-28
**Priority:** Critical

**Problem:** Current workflow relies on LLM following instructions. Models can skip steps.

**Solution:** Implement state machine with checkpoints that enforce workflow.

**Implementation Plan:** `docs/WORKFLOW_IMPLEMENTATION_PLAN.md`

**Phases:**
- [x] Phase 1: Create `/workflow` skill with state management ✅ 2026-03-28
- [ ] Phase 2: Checkpoint system integrated with existing skills
- [ ] Phase 3: Enhanced supervisor with workflow validation
- [x] Phase 4: QA agent integration (mandatory before completion) ✅ 2026-03-28
- [x] Phase 5: Simplified CLAUDE.md using workflow commands ✅ 2026-03-28
- [ ] Phase 6: (Optional) Hook-based enforcement

**Key Files to Create:**
- `skills-backup/workflow/workflow.sh`
- `skills-backup/workflow/SKILL.md`
- `skills-backup/supervisor/supervisor.sh`

**Key Files to Modify:**
- `skills-backup/tasks/tasks.sh` (add checkpoint hook)
- `skills-backup/vision/vision.sh` (add checkpoint hook)
- `skills-backup/supervisor/SKILL.md` (use supervisor.sh)
- `claude-backup/CLAUDE.md` (simplify to workflow commands)

---

## Critical: Web Search Solution

### TODO-002: Reliable Web Search for Local LLMs
**Status:** 🟢 Done
**Created:** 2026-03-25
**Updated:** 2026-04-29
**Completed:** 2026-04-29
**Priority:** Critical

**Problem:**
- Native `WebSearch` disabled (Anthropic server-side)
- Whoogle gets blocked by Google after some use
- Playwright browser is slow (5-10s per search)
- DuckDuckGo API has rate limits
- Tavily requires payment

**Solution Implemented (v2 - SearXNG):**
- ✅ SearXNG meta-search engine (self-hosted Docker container)
- ✅ Aggregates from multiple engines (Bing, DDG, Startpage, etc.)
- ✅ Resilient - if one engine blocks, others still work
- ✅ Fast (~1-2 seconds per query)
- ✅ JSON API for programmatic access
- ✅ MCP server for Claude Code integration
- ✅ Makefile commands: `make searxng-start`, `make searxng-test`, etc.

**Files:**
- `searxng/docker-compose.yml` - SearXNG container setup
- `searxng/settings.yml` - Engine configuration
- `searxng/mcp-server/` - MCP server for Claude Code
- `docs/SEARXNG.md` - Full documentation

**Previous solution (v1):** DuckDuckGo Python library (still works as fallback)

**Related:** `docs/SEARXNG.md`, `docs/SKILLS_ARCHITECTURE.md`

---

## Future: Multi-Container & Vanilla Version

### TODO-009: Multi-Container Support
**Status:** 🔴 Open
**Created:** 2026-03-31
**Priority:** Medium

**Goal:** Enable spinning up multiple agent containers simultaneously.

**Considerations:**
- Unique container names (suffix with timestamp or UUID)
- Port mapping conflicts (each container needs unique ports)
- Workspace isolation (separate workspace volumes per container)
- Resource limits (CPU/memory per container)

**Possible approach:**
- `./run.sh <workspace> [instance-id]`
- Dynamic port allocation (base + offset per instance)
- docker-compose profiles or separate compose files

---

### TODO-010: Vanilla Claude Code Version
**Status:** 🔴 Open
**Created:** 2026-03-31
**Priority:** Medium

**Goal:** Create a separate version that uses vanilla Claude Code with original Anthropic tools (WebSearch, WebFetch, etc.) instead of local LLM workarounds.

**Requirements:**
- Separate subfolder (e.g., `vanilla/` or `anthropic-version/`)
- Use real Anthropic API (requires ANTHROPIC_API_KEY)
- Enable native tools (WebSearch, WebFetch, TodoWrite, EnterPlanMode)
- Keep subagents (they should work with both)
- Simpler setup (no vision model config, no LM Studio)

**Files to create:**
- `vanilla/Dockerfile`
- `vanilla/docker-compose.yml`
- `vanilla/run.sh`
- `vanilla/CLAUDE.md` (simpler, uses native tools)
- `vanilla/scripts/init-workspace.sh` (minimal config)

**Shared files (symlink or copy):**
- `agents-backup/` - Subagents work with both
- Some skills may still be useful

**Key differences from local LLM version:**
| Aspect | Local LLM | Vanilla |
|--------|-----------|---------|
| API | LM Studio / Ollama | Anthropic API |
| WebSearch | `/websearch` skill | Native tool |
| WebFetch | `/fetch` skill | Native tool |
| TodoWrite | `/tasks` skill | Native tool |
| Vision | `/vision` skill + local model | Native (if supported) |
| Cost | Free | Pay per token |

---

## Investigation: Docker Networking

### TODO-011: Investigate mDNS Resolution in Docker Containers
**Status:** 🟢 Done
**Created:** 2026-05-02
**Completed:** 2026-05-02
**Priority:** Medium

**Question:** Can Docker containers resolve `.local` (mDNS/Bonjour) hostnames?

**Answer:** YES - mDNS hostnames work inside Docker containers on macOS.

**Confirmed working:**
```bash
# In .env-dgx2:
LLM_HOST=spark-7ceb.local  # Works!
```

**Conclusion:** Use mDNS hostnames when possible - they're more stable than IP addresses if DHCP assigns different IPs.

**Related:** `docs/NETWORK_NOTES.md`

---

## Medium: Cleanup & Fixes

### TODO-003: Fix Worker Agent (Outdated MCP References)
**Status:** 🟢 Done
**Created:** 2026-03-28
**Completed:** 2026-03-28
**Priority:** Medium

**Problem:** `agents-backup/worker.md` had outdated Playwright MCP references.

**Fix:** Updated to use `/browser` skill instead of MCP tools.

---

### TODO-004: Document WebFetch Replacement
**Status:** 🟡 Partial
**Created:** 2026-03-25
**Priority:** Medium

**Problem:** Native `WebFetch` disabled (Anthropic server-side)

**Current replacement:** `/fetch` skill downloads to file, agent reads manually.

**Gap:** No question-answering capability like native WebFetch had.

---

### TODO-005: Consider Blocking TodoWrite
**Status:** 🟢 Done
**Created:** 2026-03-25
**Completed:** 2026-03-31
**Priority:** Low

We use `/tasks` skill instead of native `TodoWrite`. Block it to reduce confusion?
**Resolution:** Added `TodoWrite` to deny list in init-workspace.sh

---

### TODO-006: Vision Fail Must Be Blocking
**Status:** 🟡 Partial
**Created:** 2026-03-31
**Updated:** 2026-03-31
**Priority:** High

**Problem:** Agent treats vision verify FAIL as informational. It rationalized "missing due to no entries" instead of fixing the issue and retrying.

**Solution:**
- ✅ Supervisor now checks vision logs and requires PASS for UI projects
- ⚠️ Could also update CLAUDE.md to emphasize "FAIL = must fix and retry"
- ⚠️ Could update vision.sh to output stronger messaging on FAIL

---

### TODO-007: Add Completion Checklist
**Status:** 🟢 Done
**Created:** 2026-03-31
**Completed:** 2026-03-31
**Priority:** High

**Problem:** Agent has no systematic check before stopping. It skipped qa-agent and supervisor.

**Solution:** Rewrote `/supervisor` skill to include rigorous checklist:
- Shows task status, workflow state, vision logs
- Clear decision logic with conditions
- Requires qa-agent before allowing completion
- Explicit CONTINUE vs ALL COMPLETE outputs
- Critical rules that prevent premature completion

---

### TODO-008: Stronger Supervisor Enforcement
**Status:** 🟢 Done
**Created:** 2026-03-31
**Completed:** 2026-03-31
**Priority:** High

**Problem:** Agent declared "All core features are now functional" and stopped without calling supervisor.

**Solution:** Supervisor skill now:
- Automatically displays checklist status
- Has strict rules: "NEVER output ALL COMPLETE if any task incomplete"
- Requires qa-agent call before completion
- If in doubt, output CONTINUE

---

## Workflow Implementation Subtasks

### Phase 1: Foundation (workflow.sh)

| Task | Status | Notes |
|------|--------|-------|
| Create workflow.sh skeleton | 🟢 Done | State management script |
| Implement state transitions | 🟢 Done | PLANNING→TASKED→TESTING→QA_CHECK→COMPLETE |
| Create .workflow_state file format | 🟢 Done | JSON with state + checkpoints |
| Add status command | 🟢 Done | Show current state |
| Add reset command | 🟢 Done | Clear workflow state |
| Create SKILL.md | 🟢 Done | Full workflow documentation with diagram |

### Phase 2: Checkpoints

| Task | Status | Notes |
|------|--------|-------|
| Add checkpoint command to workflow.sh | 🟢 Done | Records plan, tasks, test, vision, qa |
| Integrate with /tasks (auto-checkpoint) | 🔴 Open | When tasks added |
| Integrate with /vision (auto-checkpoint) | 🔴 Open | When verify called |
| Add validate command | 🟢 Done | Check if checkpoints exist |

### Phase 3: Enhanced Supervisor

| Task | Status | Notes |
|------|--------|-------|
| Create supervisor.sh script | 🔴 Open | Replaces SKILL.md logic |
| Read workflow state | 🔴 Open | Check current state |
| Validate required checkpoints | 🔴 Open | Based on project type |
| Return specific missing items | 🔴 Open | Helpful error messages |

### Phase 4: QA Integration

| Task | Status | Notes |
|------|--------|-------|
| Supervisor calls qa-agent | 🔴 Open | Automatic before completion |
| Store QA result in state | 🔴 Open | VERIFIED or GAPS_FOUND |
| Handle GAPS_FOUND | 🔴 Open | Add tasks, continue |

### Phase 5: CLAUDE.md Simplification

| Task | Status | Notes |
|------|--------|-------|
| Simplify to workflow commands | 🟢 Done | /workflow start referenced |
| Remove detailed step instructions | 🟢 Done | Points to SKILL.md for details |
| Add workflow command reference | 🟢 Done | Added to Available Capabilities |

---

## Completed

| ID | Description | Completed | Notes |
|----|-------------|-----------|-------|
| - | Replace Playwright MCP with CLI | 2026-03-25 | Fixes binary crash issue |
| - | Fix hook timeout | 2026-03-25 | 60s → 300s |
| - | Disable extended thinking | 2026-03-25 | MAX_THINKING_TOKENS=0 |
| - | Create qa-agent | 2026-03-28 | Test coverage verification |
| - | Document task completion loop | 2026-03-28 | `docs/TASK_COMPLETION_LOOP.md` |
| - | Create implementation plan | 2026-03-28 | `docs/WORKFLOW_IMPLEMENTATION_PLAN.md` |
| - | Create /workflow skill | 2026-03-28 | State management + full workflow docs |
| - | Update CLAUDE.md for workflow | 2026-03-28 | Points to /workflow skill |
| - | Block TodoWrite tool | 2026-03-31 | Added to deny list, agent uses /tasks |
| - | Add sudo instructions | 2026-03-31 | Agent can self-heal permission issues |
| - | Test with OpenAI OSS 120B | 2026-03-31 | Workflow mostly followed, see observations |
| - | Rigorous supervisor | 2026-03-31 | Checklist validation before completion |
| - | Fix browser skill | 2026-03-31 | Removed broken wrapper, use playwright-cli directly |
| - | Add /websearch skill | 2026-03-31 | DuckDuckGo Python lib, free, no API key |
| - | Consolidate search skills | 2026-03-31 | websearch (primary), browser (fallback), fetch (URLs) |
| - | Document skills architecture | 2026-03-31 | `docs/SKILLS_ARCHITECTURE.md` |
| - | SearXNG web search integration | 2026-04-29 | Self-hosted meta-search, MCP server, `docs/SEARXNG.md` |
