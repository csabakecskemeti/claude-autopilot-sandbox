# Claude Autopilot Sandbox - Makefile
# Run 'make help' for available commands

# Worker id flags (W / w / WORKER) collide with common shell exports; make imports
# the environment as macros. Empty defaults here so only this file and explicit
# CLI assignments (make attach W=…) define the worker id.
W :=
w :=
WORKER :=

.PHONY: help setup build build-base build-clean worker stop stop-all attach worker-info logs ps clean shell status prune test env env-clone \
        workers worker-clean worker-remove workers-clean \
        searxng-start searxng-stop searxng-status searxng-test searxng-logs \
        langfuse-install langfuse-start langfuse-stop langfuse-status langfuse-logs langfuse-clean

# Default target
help:
	@echo "Claude Autopilot Sandbox"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          Interactive wizard to create/edit .env"
	@echo "  make setup ENV=.env2"
	@echo "                      Create/edit alternate env file"
	@echo "  make env            Show current config (secrets hidden)"
	@echo "  make env-clone E=.env2"
	@echo "                      Clone .env to new file (quick copy)"
	@echo "  make test           Test LLM and services connection"
	@echo "  make test ENV=.env2 Test with alternate config"
	@echo "  make build          Build Docker images"
	@echo "  make build-clean    Build Docker images (no cache)"
	@echo ""
	@echo "Workers (agents):"
	@echo "  make worker W=myworker TASK=\"…\"     (aliases: w=, WORKER=, T=/TASK=, TF=/TASKFILE=)"
	@echo "  make worker W=myworker TASKFILE=task.txt"
	@echo "  make worker W=myworker ENV=.env2"
	@echo "  make worker W=myworker HARDENING=moderate"
	@echo "  make worker W=myworker                  (interactive, no initial TASK)"
	@echo ""
	@echo "  HARDENING levels (default: strict):"
	@echo "    strict:     All config locked (production, untrusted tasks)"
	@echo "    moderate:   Guardrails locked, other tools writable (trusted dev)"
	@echo "    permissive: Minimal protection (debugging, agent development)"
	@echo ""
	@echo "Worker management:"
	@echo "  make workers            List worker runs (folders under workspaces/)"
	@echo "  make worker-info [W=id] metadata.json; W, w, or WORKER=id; omit to pick running"
	@echo "                          (put W=… on the same line as make, not only export W)"
	@echo "  make worker-clean W=id  Stop/remove containers (w= or WORKER=id)"
	@echo "  make workers-clean      Clean all stopped worker runs"
	@echo "  make worker-remove W=id Remove worker folder (w= or WORKER=id)"
	@echo ""
	@echo "Container management:"
	@echo "  make ps             List running containers"
	@echo "  make status         Docker claude-* + recent runs (orphaned = supervisor without agent)"
	@echo "  make attach [W=id]  Attach (W, w, or WORKER = workername_timestamp; omit to pick)"
	@echo "  make logs           Follow logs (all containers)"
	@echo "  make logs C=agent   Follow logs for specific container"
	@echo "  make stop [W=id]    Stop agent+supervisor; omit W for picker (1 run auto, 2+ menu)"
	@echo "                      Same W= / w= / WORKER= as attach"
	@echo "  make stop-all       Stop all Claude containers"
	@echo ""
	@echo "Debugging:"
	@echo "  make shell          Shell into running agent container"
	@echo "  make shell-supervisor"
	@echo "                      Shell into running supervisor container"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean          Stop and remove all containers"
	@echo "  make prune          Remove unused images and volumes"
	@echo ""
	@echo "SearXNG (Web Search):"
	@echo "  make searxng-start  Start standalone SearXNG service"
	@echo "  make searxng-stop   Stop standalone SearXNG service"
	@echo "  make searxng-status Check SearXNG status and engines"
	@echo "  make searxng-test   Test search API with sample query"
	@echo "  make searxng-logs   Follow SearXNG logs"
	@echo ""
	@echo "Langfuse (Tracing - auto-installs to .langfuse/):"
	@echo "  make langfuse-start     Start Langfuse (auto-clones if needed)"
	@echo "  make langfuse-stop      Stop Langfuse service"
	@echo "  make langfuse-status    Check Langfuse status"
	@echo "  make langfuse-logs      Follow Langfuse logs"
	@echo "  make langfuse-clean     Remove Langfuse installation"

# ============================================================================
# Setup
# ============================================================================

setup:
ifdef ENV
	@./scripts/setup-wizard.sh $(ENV)
else
	@./scripts/setup-wizard.sh
endif

build-base:
	docker build -f Dockerfile.base -t claude-sandbox:latest .

build: build-base
	docker compose build

build-clean: build-base
	docker compose build --no-cache

env:
	@if [ -f .env ]; then \
		echo "=== Current Configuration ==="; \
		grep -v "SECRET\|KEY\|TOKEN\|PASSWORD" .env | grep -v "^#" | grep -v "^$$"; \
		echo ""; \
		echo "(Secrets hidden)"; \
	else \
		echo "No .env file found. Run 'make setup' first."; \
	fi

# Clone .env to a new file for customization
# Usage: make env-clone E=.env2
env-clone:
ifndef E
	@echo "Error: Target file required."
	@echo "Usage: make env-clone E=.env2"
	@exit 1
endif
	@if [ ! -f .env ]; then \
		echo "No .env file found. Run 'make setup' first."; \
		exit 1; \
	fi
	@cp .env $(E)
	@echo "Created $(E) from .env"
	@echo "Edit $(E), then run: make worker W=myworker ENV=$(E) TASK=\"…\"   (or WORKER= / T=)"

test:
	@ENV_FILE="$${ENV:-.env}"; \
	if [ ! -f "$$ENV_FILE" ]; then \
		echo "No $$ENV_FILE file found. Run 'make setup' first."; \
		exit 1; \
	fi; \
	echo "=== Config: $$ENV_FILE ==="; \
	echo ""; \
	echo "=== LLM Server ==="; \
	. ./$$ENV_FILE && echo "Testing $$LLM_HOST:$$LLM_PORT..."; \
	. ./$$ENV_FILE && curl -s --max-time 5 "http://$$LLM_HOST:$$LLM_PORT/v1/models" > /dev/null \
		&& echo "  OK - LLM server reachable" \
		|| echo "  FAILED - Cannot reach LLM server"
	@echo ""
	@echo "=== SearXNG (Web Search) ==="
	@if curl -s --max-time 2 "http://localhost:8888/healthz" > /dev/null 2>&1; then \
		echo "  OK - SearXNG running at :8888"; \
	else \
		echo "  OFFLINE - Run 'make searxng-start'"; \
	fi
	@echo ""
	@echo "=== Supervisor (per-task) ==="
	@ENV_FILE="$${ENV:-.env}"; \
	. ./$$ENV_FILE 2>/dev/null || true; \
	PREFIX="$${CONTAINER_PREFIX:-claude}"; \
	RUNNING=$$(docker ps -q --filter "name=$$PREFIX-supervisor-" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$RUNNING" -gt 0 ] 2>/dev/null; then \
		echo "  OK - $$RUNNING supervisor container(s) running (one per active task)"; \
	else \
		echo "  None running — start with: make worker W=… TASK=… (w=, WORKER=, T=, TASKFILE=/TF=)"; \
	fi
	@echo ""
	@echo "=== Langfuse (Tracing) ==="
	@if curl -s --max-time 2 "http://localhost:3000" > /dev/null 2>&1; then \
		echo "  OK - Langfuse running at :3000"; \
	else \
		echo "  OFFLINE - Run 'make langfuse-start' (optional)"; \
	fi

# ============================================================================
# Running (worker = one agent + supervisor + disk folder workername_timestamp)
# ============================================================================
#
# Usage: make worker W=myworker TASK="goal"   (aliases: WORKER=, T= or TASK=, TF= or TASKFILE=)
#    or: make worker W=myworker TASKFILE=path
#    or: make worker W=myworker ENV=.env2
#    or: make worker W=myworker SEARXNG=1
#
worker:
	@WL="$(strip $(W))"; [ -n "$$WL" ] || WL="$(strip $(w))"; [ -n "$$WL" ] || WL="$(strip $(WORKER))"; \
	if [ -z "$$WL" ]; then \
		echo "Error: worker name required (short label → folder <label>_timestamp)."; \
		echo "Usage: make worker W=myworker TASK=\"…\"   (aliases: w=, WORKER=, T= or TASK=)"; \
		echo "   or: make worker W=myworker TASKFILE=…   (alias: TF=)"; \
		echo "   or: make worker W=myworker ENV=.env2"; \
		echo "   or: make worker W=myworker SEARXNG=1"; \
		echo "   or: make worker W=myworker HARDENING=moderate"; \
		exit 1; \
	fi; \
	TFILE="$(strip $(TASKFILE))"; [ -n "$$TFILE" ] || TFILE="$(strip $(TF))"; \
	E="$(strip $(ENV))"; [ -n "$$E" ] || E=".env"; export ENV="$$E"; \
	H="$(strip $(HARDENING))"; [ -n "$$H" ] || H="strict"; \
	if [ -n "$$TFILE" ]; then \
		HARDENING="$$H" INCLUDE_SEARXNG=$(SEARXNG) ./run.sh "$$WL" "TF=$$TFILE"; \
	else \
		TT="$(strip $(TASK))"; [ -n "$$TT" ] || TT="$(strip $(T))"; \
		HARDENING="$$H" INCLUDE_SEARXNG=$(SEARXNG) ./run.sh "$$WL" "$$TT"; \
	fi

# ============================================================================
# Worker management
# ============================================================================

# List worker runs (folders under workspaces/)
workers:
	@echo "=== Workers ==="
	@if [ -f .env ]; then . ./.env; fi; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	if [ -d "$$WSBASE" ]; then \
		for meta in "$$WSBASE"/*/metadata.json; do \
			if [ -f "$$meta" ]; then \
				"$(CURDIR)/scripts/worker-list-line.sh" "$$meta" 2>/dev/null || true; \
			fi; \
		done | head -20; \
		COUNT=$$(ls -1d "$$WSBASE"/*/ 2>/dev/null | wc -l | tr -d ' '); \
		echo ""; \
		echo "Total: $$COUNT worker run(s) (id = name_timestamp; use W=, w=, or WORKER= with attach/stop/info)"; \
	else \
		echo "No workspaces found"; \
	fi

# Show metadata for one worker run (W, w, or WORKER = full id — portable; no GNU $(or))
worker-info:
	@if [ -f .env ]; then . ./.env; fi; \
	WID="$(strip $(W))"; [ -n "$$WID" ] || WID="$(strip $(w))"; [ -n "$$WID" ] || WID="$(strip $(WORKER))"; \
	if [ -n "$$WID" ]; then \
		WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
		META="$$WSBASE/$$WID/metadata.json"; \
		if [ -f "$$META" ]; then \
			echo "=== Worker: $$WID ==="; \
			echo ""; \
			jq '.' "$$META"; \
		else \
			echo "Worker not found: $$WID"; \
			echo "Use 'make workers' to list runs"; \
			exit 1; \
		fi; \
	else \
		W_PICKED=$$($(CURDIR)/scripts/pick-running-worker.sh) || exit 1; \
		[ -n "$$W_PICKED" ] || exit 1; \
		$(MAKE) worker-info W="$$W_PICKED"; \
	fi

# Stop and remove containers for a worker run (W, w, or WORKER = full id)
worker-clean:
	@ID="$(strip $(W))"; [ -n "$$ID" ] || ID="$(strip $(w))"; [ -n "$$ID" ] || ID="$(strip $(WORKER))"; \
	if [ -z "$$ID" ]; then \
		echo "Usage: make worker-clean W=workername_20260502_223000   (or WORKER=…)"; \
		exit 1; \
	fi; \
	if [ -f .env ]; then . ./.env; fi; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	TASK_DIR="$$WSBASE/$$ID"; \
	META="$$TASK_DIR/metadata.json"; \
	if [ ! -d "$$TASK_DIR" ]; then \
		echo "Worker not found: $$ID"; \
		exit 1; \
	fi; \
	echo "Cleaning worker: $$ID"; \
	"$(CURDIR)/scripts/stop-worker-containers.sh" --rm "$$ID"; \
	if [ -f "$$META" ]; then \
		jq '.status.state = "cleaned"' "$$META" > "$$META.tmp" && mv "$$META.tmp" "$$META"; \
	fi; \
	echo "Worker cleaned: $$ID"

# Remove worker folder completely (W, w, or WORKER = full id)
worker-remove:
	@ID="$(strip $(W))"; [ -n "$$ID" ] || ID="$(strip $(w))"; [ -n "$$ID" ] || ID="$(strip $(WORKER))"; \
	if [ -z "$$ID" ]; then \
		echo "Usage: make worker-remove W=workername_20260502_223000   (or WORKER=…)"; \
		exit 1; \
	fi; \
	if [ -f .env ]; then . ./.env; fi; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	TASK_DIR="$$WSBASE/$$ID"; \
	if [ ! -d "$$TASK_DIR" ]; then \
		echo "Worker not found: $$ID"; \
		exit 1; \
	fi; \
	echo "Removing worker folder: $$ID"; \
	rm -rf "$$TASK_DIR"; \
	echo "Removed"

# Clean all stopped worker runs
workers-clean:
	@echo "Cleaning stopped worker runs..."
	@if [ -f .env ]; then . ./.env; fi; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	COUNT=0; \
	for meta in "$$WSBASE"/*/metadata.json; do \
		if [ -f "$$meta" ]; then \
			STATE=$$(jq -r '.status.state // "unknown"' "$$meta"); \
			if [ "$$STATE" = "stopped" ]; then \
				TASK_DIR=$$(dirname "$$meta"); \
				TASK_NAME=$$(basename "$$TASK_DIR"); \
				AGENT=$$(jq -r '.containers.agent.name // empty' "$$meta"); \
				SUPERVISOR=$$(jq -r '.containers.supervisor.name // empty' "$$meta"); \
				echo "  Cleaning: $$TASK_NAME"; \
				docker rm "$$AGENT" 2>/dev/null || true; \
				docker rm "$$SUPERVISOR" 2>/dev/null || true; \
				jq '.status.state = "cleaned"' "$$meta" > "$$meta.tmp" && mv "$$meta.tmp" "$$meta"; \
				COUNT=$$((COUNT + 1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "Cleaned $$COUNT worker run(s)"

# ============================================================================
# Container Management
# ============================================================================

ps:
	@docker ps --filter "name=claude-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

status:
	@echo "=== Running Containers ==="
	@docker ps --filter "name=claude-" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"
	@echo ""
	@echo "=== Recent worker runs ==="
	@if [ -f .env ]; then . ./.env; fi; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	if [ -d "$$WSBASE" ]; then \
		for meta in "$$WSBASE"/*/metadata.json; do \
			if [ -f "$$meta" ]; then \
				"$(CURDIR)/scripts/worker-list-line.sh" "$$meta" 2>/dev/null || true; \
			fi; \
		done | tail -10; \
	else \
		echo "  No workspaces found"; \
	fi

logs:
ifdef C
	docker compose logs -f $(C)
else
	docker compose logs -f
endif

stop:
	@if [ -f .env ]; then . ./.env; fi; \
	WID="$(strip $(W))"; [ -n "$$WID" ] || WID="$(strip $(w))"; [ -n "$$WID" ] || WID="$(strip $(WORKER))"; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	if [ -n "$$WID" ]; then \
		echo "Stopping worker: $$WID"; \
		META="$$WSBASE/$$WID/metadata.json"; \
		"$(CURDIR)/scripts/stop-worker-containers.sh" "$$WID"; \
		if [ -f "$$META" ]; then \
			STOP_TS=$$(date -u +%Y-%m-%dT%H:%M:%SZ); \
			if jq --arg stop_time "$$STOP_TS" \
				'.status.state = "stopped" | .status.stop_time = $$stop_time | .status.exit_code = null' \
				"$$META" > "$$META.tmp" 2>/dev/null && mv "$$META.tmp" "$$META" 2>/dev/null; then \
				:; \
			else \
				rm -f "$$META.tmp" 2>/dev/null || true; \
				echo "  Warning: could not update metadata (jq or JSON)" >&2; \
			fi; \
			echo "Worker stopped: $$WID"; \
		else \
			echo "No metadata at $$META — containers were stopped if names matched (see script fallbacks)."; \
			echo "Use 'make workers' to list runs"; \
		fi; \
	else \
		W_PICKED=$$($(CURDIR)/scripts/pick-running-worker.sh) || exit 1; \
		[ -n "$$W_PICKED" ] || exit 1; \
		$(MAKE) stop W="$$W_PICKED"; \
	fi

# Stop all Claude containers (force)
stop-all:
	@echo "Stopping all Claude containers..."
	@docker ps -q --filter "name=claude-" | xargs -r docker stop
	@echo "All containers stopped."

# Attach to a running agent (W, w, or WORKER = full worker id workername_timestamp)
attach:
	@if [ -f .env ]; then . ./.env; fi; \
	WID="$(strip $(W))"; [ -n "$$WID" ] || WID="$(strip $(w))"; [ -n "$$WID" ] || WID="$(strip $(WORKER))"; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	if [ -n "$$WID" ]; then \
		META="$$WSBASE/$$WID/metadata.json"; \
		if [ -f "$$META" ]; then \
			AGENT=$$(jq -r '.containers.agent.name // empty' "$$META"); \
			if [ -n "$$AGENT" ] && docker ps -q --filter "name=$$AGENT" | grep -q .; then \
				echo "Attaching to $$AGENT (Ctrl+P, Ctrl+Q to detach)..."; \
				docker attach "$$AGENT"; \
			else \
				echo "Agent container not running: $$AGENT"; \
			fi; \
		else \
			echo "Worker not found: $$WID"; \
		fi; \
	else \
		W_PICKED=$$($(CURDIR)/scripts/pick-running-worker.sh) || exit 1; \
		[ -n "$$W_PICKED" ] || exit 1; \
		$(MAKE) attach W="$$W_PICKED"; \
	fi

# ============================================================================
# Debugging
# ============================================================================

shell:
	@CONTAINER=$$(docker ps -q --filter "name=claude-agent-" | head -1); \
	if [ -z "$$CONTAINER" ]; then \
		echo "No running agent container found"; \
		exit 1; \
	fi; \
	docker exec -it $$CONTAINER /bin/bash

shell-supervisor:
	@CONTAINER=$$(docker ps -q --filter "name=claude-supervisor-" | head -1); \
	if [ -z "$$CONTAINER" ]; then \
		echo "No running supervisor container found"; \
		exit 1; \
	fi; \
	docker exec -it $$CONTAINER /bin/bash

# ============================================================================
# Cleanup
# ============================================================================

clean:
	@echo "Stopping all Claude containers..."
	docker ps -q --filter "name=claude-" | xargs -r docker stop
	@echo "Removing all Claude containers..."
	docker ps -aq --filter "name=claude-" | xargs -r docker rm

prune:
	@echo "Removing unused Docker resources..."
	docker system prune -f
	docker volume prune -f

# ============================================================================
# SearXNG Web Search Service
# ============================================================================

searxng-start:
	@echo "Starting SearXNG search service..."
	@cd searxng && docker compose up -d
	@echo ""
	@echo "SearXNG is starting at http://localhost:8888"
	@echo "JSON API: http://localhost:8888/search?q=query&format=json"
	@echo ""
	@echo "Waiting for service to be ready..."
	@sleep 3
	@curl -s --max-time 5 "http://localhost:8888/healthz" > /dev/null 2>&1 \
		&& echo "SearXNG is ready!" \
		|| echo "SearXNG is still starting... try 'make searxng-test' in a few seconds"

searxng-stop:
	@echo "Stopping SearXNG..."
	@cd searxng && docker compose down

searxng-status:
	@echo "=== SearXNG Status ==="
	@docker ps --filter "name=searxng" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "SearXNG not running"
	@echo ""
	@if curl -s --max-time 2 "http://localhost:8888/healthz" > /dev/null 2>&1; then \
		echo "API Status: ONLINE"; \
		echo ""; \
		echo "=== Engine Status (from last query) ==="; \
		curl -s "http://localhost:8888/search?q=test&format=json" 2>/dev/null | \
			jq -r '.unresponsive_engines // [] | if length == 0 then "All engines responding" else .[] | "\(.[0]): \(.[1])" end' 2>/dev/null || echo "Could not check engines"; \
	else \
		echo "API Status: OFFLINE"; \
		echo "Run 'make searxng-start' to start the service"; \
	fi

searxng-test:
	@echo "=== Testing SearXNG Search API ==="
	@echo ""
	@if ! curl -s --max-time 2 "http://localhost:8888/healthz" > /dev/null 2>&1; then \
		echo "SearXNG is not running. Start with: make searxng-start"; \
		exit 1; \
	fi
	@echo "Query: 'docker compose tutorial'"
	@echo ""
	@curl -s -w "\nTime: %{time_total}s\n" "http://localhost:8888/search?q=docker+compose+tutorial&format=json" | \
		jq -r 'if type == "object" then "Results: \(.results | length)\nEngines: \([.results[].engines] | flatten | unique | join(", "))\nUnresponsive: \((.unresponsive_engines // []) | map(.[0]) | join(", ") | if . == "" then "none" else . end)\n\nTop 3 Results:\n\(.results[:3] | to_entries | map("  \(.key + 1). \(.value.title[0:60])\n     \(.value.url)") | join("\n"))" else . end' 2>/dev/null || cat

searxng-logs:
	@cd searxng && docker compose logs -f

# ============================================================================
# Langfuse Tracing Service (auto-installs to .langfuse/)
# ============================================================================

LANGFUSE_DIR := $(CURDIR)/.langfuse

langfuse-install:
	@if [ ! -d "$(LANGFUSE_DIR)" ]; then \
		echo "Cloning Langfuse..."; \
		git clone --depth 1 https://github.com/langfuse/langfuse.git $(LANGFUSE_DIR); \
	else \
		echo "Langfuse already installed at $(LANGFUSE_DIR)"; \
	fi

langfuse-start: langfuse-install
	@echo "Starting Langfuse..."
	@cd $(LANGFUSE_DIR) && docker compose up -d
	@echo ""
	@echo "Langfuse starting at http://localhost:3000"
	@echo "Waiting for service..."
	@sleep 5
	@curl -s --max-time 5 "http://localhost:3000" > /dev/null 2>&1 \
		&& echo "Langfuse is ready!" \
		|| echo "Langfuse is still starting... try 'make langfuse-status'"

langfuse-stop:
	@if [ -d "$(LANGFUSE_DIR)" ]; then \
		cd $(LANGFUSE_DIR) && docker compose down; \
	else \
		echo "Langfuse not installed"; \
	fi

langfuse-status:
	@echo "=== Langfuse Status ==="
	@docker ps --filter "name=langfuse" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Langfuse not running"
	@echo ""
	@if curl -s --max-time 2 "http://localhost:3000" > /dev/null 2>&1; then \
		echo "UI: http://localhost:3000 (ONLINE)"; \
	else \
		echo "UI: OFFLINE - run 'make langfuse-start'"; \
	fi

langfuse-logs:
	@if [ -d "$(LANGFUSE_DIR)" ]; then \
		cd $(LANGFUSE_DIR) && docker compose logs -f; \
	else \
		echo "Langfuse not installed - run 'make langfuse-start'"; \
	fi

langfuse-clean:
	@echo "Removing Langfuse installation..."
	@if [ -d "$(LANGFUSE_DIR)" ]; then \
		cd $(LANGFUSE_DIR) && docker compose down -v 2>/dev/null || true; \
		rm -rf $(LANGFUSE_DIR); \
		echo "Langfuse removed"; \
	else \
		echo "Langfuse not installed"; \
	fi
