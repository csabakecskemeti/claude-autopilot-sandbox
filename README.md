# Claude Autopilot Sandbox

Run Claude Code CLI autonomously in a Docker sandbox with your own local LLM. Execution stays on hardware you control, with full tool access for long-running, unattended work.

## Naming (CLI)

**Start a worker** (`make worker …`):

| Meaning | Short flag | Long flag |
|--------|------------|-----------|
| Worker label (becomes `<label>_timestamp`) | `W=` | `WORKER=` (also **`w=`** — same as `W`; Make is case-sensitive) |
| Goal / prompt | `T=` | `TASK=` |
| Task text from file | `TF=` | `TASKFILE=` |

`TASKFILE` / `TF` wins over `TASK` / `T` when both are set (file is used).

**Target one existing run** (`attach`, `stop`, `worker-info`, `worker-clean`, `worker-remove`): pass the **full worker run id** as **`W=`**, **`w=`**, or **`WORKER=`** (same value as in `make workers` / `metadata.json` → `task.full_name`). Omit those on `attach` / `worker-info` to use the interactive picker.

So: **short label** with **`W=`**, **`w=`**, or **`WORKER=`** when starting; **full id** with the same flags when attaching, stopping, or inspecting.

## Features

- **Local LLM** — LM Studio, Ollama, vLLM, etc. via OpenAI-compatible API
- **Autonomous operation** — A **dedicated supervisor** per worker run validates completion before the agent may stop
- **Multi-instance** — Several **worker** runs in parallel; each gets its own agent + supervisor, ports, and Compose network
- **Vision** — Screenshot and analyze UIs (see `/vision` skill)
- **Sandbox** — Broad capability inside the container; disk layout under your control
- **Makefile workflow** — `make help` lists commands

## Quick Start

```bash
git clone <repository-url>
cd local-claude-docker   # or your clone directory

make setup              # create/edit .env (LLM host, model, …)
make build              # base image + agent + supervisor images

# Optional host services (agent talks to them via host.docker.internal by default)
make searxng-start      # web search on :8888
make langfuse-start     # tracing UI on :3000 (optional)

make worker W=myproject TASK="Build a small CLI tool that prints hello"
```

Each **`make worker`** creates **`workspaces/<worker_run_id>/`**, starts **agent + supervisor** for that run only, then attaches your terminal to the agent (`Ctrl+P`, `Ctrl+Q` to detach without stopping containers).

## Makefile commands

Run **`make help`** for the canonical list. Common ones:

### Setup and build

```bash
make setup              # wizard → .env
make setup ENV=.env2
make env                # show config (secrets hidden)
make env-clone E=.env2  # copy .env
make test               # probe LLM, SearXNG, Langfuse; supervisor = count of supervisor containers
make build              # docker compose build (after Dockerfile.base)
make build-clean        # build --no-cache
```

### Start a worker

```bash
make worker W=myproject TASK="Task description"
make worker WORKER=myproject T="same as TASK"
make worker W=myproject TF=task.txt           # same as TASKFILE=
make worker W=myproject                     # interactive, no initial TASK
make worker W=myproject ENV=.env2
make worker W=myproject SEARXNG=1
```

### Worker runs and containers

```bash
make workers              # list worker runs
make worker-info W=myproject_20260503_143022   # or WORKER=…
make worker-info          # pick a **running** worker (menu, or auto if one)
make attach W=myproject_20260503_143022       # or WORKER=…
make attach               # same picker as worker-info
make stop W=myproject_20260503_143022         # or WORKER=…
make stop                 # same picker as attach / worker-info
make stop-all
make status
make ps
```

### Debugging and cleanup

```bash
make shell                # bash in first running agent (by container order)
make shell-supervisor
make worker-clean W=id    # or WORKER=id — stop/remove containers
make worker-remove W=id   # or WORKER=id — delete run folder
make workers-clean        # prune stopped worker runs
make clean                # stop/remove claude-* containers
make prune
```

### SearXNG and Langfuse

See **`make help`** for `searxng-*` and `langfuse-*` targets.

## Multi-instance and on-disk layout

Every **`make worker`** with label **`W=<label>`** or **`WORKER=<label>`** runs `run.sh`, which:

1. Creates **`workspaces/<label>_<YYYYMMDD_HHMMSS>/`**
2. Allocates **four host ports** in `30000–60000` (collision-aware via `scripts/allocate-ports.sh`)
3. Writes **`metadata.json`** (paths, container names, ports, original task)
4. Starts **one Compose project** named `claude-<label>_<timestamp>` with **agent** + **supervisor** on a private **`agentnet`**

Typical layout:

```text
workspaces/
  myproject_20260503_143022/
    metadata.json      # authoritative run + container + port info
    worker/            # agent workspace (mounted into agent)
    task/              # immutable copy of the original task text
    supervisor/        # supervisor scratch / outputs (host-visible)
```

Container names (override with `CONTAINER_PREFIX` in `.env`):

- Agent: `{CONTAINER_PREFIX}-agent-{worker_run_id}`
- Supervisor: `{CONTAINER_PREFIX}-supervisor-{worker_run_id}`

Default `CONTAINER_PREFIX` is **`claude`**.

### Published ports (per run)

| Service    | Container port | Host port source                          |
|-----------|----------------|-------------------------------------------|
| Agent     | 3000, 5000, 8000 | First three ports from allocation script |
| Supervisor| 8080           | Fourth allocated port                    |

Exact numbers are in **`metadata.json`**.

### Runtime overrides

```bash
LLM_HOST=192.168.1.50 make worker W=proj1 TASK="task 1"
```

### Alternate env files

```bash
make env-clone E=.env-dgx2
make worker W=myproject ENV=.env-dgx2 TASK="task"
```

## Architecture (current)

Each **worker run** is an **isolated pair** (agent + supervisor) on a **dedicated Docker network** for that Compose project. The agent’s Stop hook calls the supervisor HTTP API at **`http://supervisor:8080`** (in-stack DNS).

There is **no** separate global supervisor service required for **`make worker`** — each run brings up its own.

## Configuration

Prefer **`make setup`** → **`.env`**. Template: **`.env.example`**.

Project-level hook env is generated at container start (see `scripts/init-workspace.sh`).

## How the supervisor works (per run)

1. Agent tries to stop → Stop hook (Langfuse if enabled, then supervisor).
2. Hook **`POST`s** to **`/evaluate`** on the supervisor in the **same** Compose project.
3. Supervisor inspects the agent workspace (read-only) and returns **complete** or **not_complete** with feedback.
4. Loop limits (`SUPERVISOR_MAX_LOOPS`, etc.) cap runaway cycles.

## Skills

Under `skills-backup/`; invoke with **`/skillname`**:

| Skill | Role |
|-------|------|
| `/plan` | Implementation planning |
| `/tasks` | Task checklist |
| `/workflow` | Workflow state |
| `/vision` | Images / UI verification |
| `/browser` | Playwright CLI automation |
| `/fetch` | Fetch URLs to workspace |
| `/memory` | Persistent notes |
| `/supervisor` | Toward evaluation (see skill) |
| `/pkg-install` | Install packages |
| `/sql-query` | SQL helper |
| `/file-convert` | Format conversion |

Web search: **`make searxng-start`** or **`SEARXNG=1`** with **`make worker`**.

## Repository layout

```text
├── Makefile
├── run.sh
├── docker-compose.yml
├── Dockerfile
├── Dockerfile.base
├── build.sh
├── scripts/
│   ├── allocate-ports.sh
│   ├── pick-running-worker.sh   # attach / worker-info when W= omitted
│   ├── init-workspace.sh
│   └── setup-wizard.sh
├── supervisor/
├── skills-backup/
├── hooks-backup/
├── agents-backup/
├── claude-backup/
├── workspaces/
└── docs/
```

## Web search (SearXNG)

```bash
make searxng-start
make worker W=myproject SEARXNG=1 TASK="…"
```

## Troubleshooting

### LLM unreachable from the container

Use a host IP reachable from Docker. `make setup` documents this.

### Ports

Chosen by **`allocate-ports.sh`**; see **`metadata.json`**.

### attach / worker-info without `W` / `WORKER`

Interactive picker; needs at least one running worker from **`make worker`**.

### exFAT / network drives

Set **`WORKSPACE_BASE`** to a local APFS/HFS+/ext4 path.

## Security notes

- Containers run as **non-root** where images define it.
- **Memory limits** in compose via `.env`.
- Supervisor mounts agent workspace **read-only**; original task under **`task/`** (read-only in agent).

## License

[Your license here]
