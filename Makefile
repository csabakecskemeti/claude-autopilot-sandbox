# Claude Autopilot Sandbox - Makefile
# Run 'make help' for available commands

.PHONY: help setup build build-base build-clean run stop logs ps clean shell status prune test env env-clone \
        searxng-start searxng-stop searxng-status searxng-test searxng-logs \
        supervisor-start supervisor-stop supervisor-status supervisor-logs supervisor-build \
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
	@echo "  make test           Test LLM server connection"
	@echo "  make build          Build Docker images"
	@echo "  make build-clean    Build Docker images (no cache)"
	@echo ""
	@echo "Running:"
	@echo "  make run W=myproject T=\"Build a todo app\""
	@echo "                      Start agent with workspace and task"
	@echo "  make run W=myproject TF=task.txt"
	@echo "                      Start agent with task from file (for complex prompts)"
	@echo "  make run W=myproject ENV=.env2"
	@echo "                      Start agent using alternate env file"
	@echo "  make run W=myproject"
	@echo "                      Start agent (interactive, no initial task)"
	@echo ""
	@echo "Management:"
	@echo "  make ps             List running containers"
	@echo "  make status         Show status of all instances"
	@echo "  make logs           Follow logs (all containers)"
	@echo "  make logs C=agent   Follow logs for specific container"
	@echo "  make stop           Stop all containers"
	@echo "  make stop I=agent-abc123"
	@echo "                      Stop specific instance"
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
	@echo "Supervisor (Shared):"
	@echo "  make supervisor-start   Start shared supervisor service"
	@echo "  make supervisor-stop    Stop supervisor service"
	@echo "  make supervisor-status  Check supervisor health"
	@echo "  make supervisor-logs    Follow supervisor logs"
	@echo "  make supervisor-build   Rebuild supervisor image"
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
	@echo "Edit $(E), then run: make run W=myproject ENV=$(E)"

test:
	@if [ ! -f .env ]; then \
		echo "No .env file found. Run 'make setup' first."; \
		exit 1; \
	fi
	@echo "=== LLM Server ==="
	@. ./.env && echo "Testing $$LLM_HOST:$$LLM_PORT..."
	@. ./.env && curl -s --max-time 5 "http://$$LLM_HOST:$$LLM_PORT/v1/models" > /dev/null \
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
	@echo "=== Supervisor ==="
	@if curl -s --max-time 2 "http://localhost:8080/health" > /dev/null 2>&1; then \
		echo "  OK - Supervisor running at :8080"; \
	else \
		echo "  OFFLINE - Run 'make supervisor-start'"; \
	fi
	@echo ""
	@echo "=== Langfuse (Tracing) ==="
	@if curl -s --max-time 2 "http://localhost:3000" > /dev/null 2>&1; then \
		echo "  OK - Langfuse running at :3000"; \
	else \
		echo "  OFFLINE - Run 'make langfuse-start' (optional)"; \
	fi

# ============================================================================
# Running
# ============================================================================

# Usage: make run W=workspace T="task description"
#    or: make run W=workspace TF=task.txt  (read task from file)
#    or: make run W=workspace ENV=.env2    (use alternate env file)
#    or: make run W=workspace SEARXNG=1    (include SearXNG in same network)
run:
ifndef W
	@echo "Error: Workspace required."
	@echo "Usage: make run W=myproject T=\"task\""
	@echo "   or: make run W=myproject TF=task.txt"
	@echo "   or: make run W=myproject ENV=.env2"
	@echo "   or: make run W=myproject SEARXNG=1  (include SearXNG)"
	@exit 1
endif
ifdef ENV
	@echo "Using env file: $(ENV)"
endif
ifdef SEARXNG
	@echo "Including SearXNG in agent network"
endif
ifdef TF
	ENV_FILE=$(or $(ENV),.env) SEARXNG=$(SEARXNG) ./run.sh "$(W)" "$$(cat $(TF))"
else
	ENV_FILE=$(or $(ENV),.env) SEARXNG=$(SEARXNG) ./run.sh "$(W)" "$(T)"
endif

# ============================================================================
# Management
# ============================================================================

ps:
	@docker ps --filter "name=claude-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

status:
	@echo "=== Running Instances ==="
	@docker ps --filter "name=claude-" --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"
	@echo ""
	@echo "=== Workspaces ==="
	@if [ -f .env ]; then . ./.env; fi; \
	WSBASE="$${WORKSPACE_BASE:-./workspaces}"; \
	if [ -d "$$WSBASE" ]; then \
		ls -1d "$$WSBASE"/*/ 2>/dev/null | xargs -I {} basename {} | grep -v '\-supervisor$$\|\-task$$' || echo "No workspaces found"; \
	else \
		echo "Workspace directory not found: $$WSBASE"; \
	fi

logs:
ifdef C
	docker compose logs -f $(C)
else
	docker compose logs -f
endif

stop:
ifdef I
	@echo "Stopping instance: $(I)"
	docker stop claude-agent-$(I) claude-supervisor-$(I) 2>/dev/null || true
else
	@echo "Stopping all Claude containers..."
	docker ps -q --filter "name=claude-" | xargs -r docker stop
endif

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
# Shared Supervisor Service
# ============================================================================

supervisor-build:
	@echo "Building supervisor image..."
	@cd supervisor && docker compose build

supervisor-start:
	@if [ ! -f .env ]; then \
		echo "No .env file found. Run 'make setup' first."; \
		exit 1; \
	fi
	@echo "Starting shared supervisor service..."
	@set -a && . ./.env && set +a && cd supervisor && docker compose up -d
	@echo ""
	@echo "Supervisor is starting at http://localhost:$${SUPERVISOR_PORT:-8080}"
	@echo ""
	@echo "Waiting for service to be ready..."
	@sleep 3
	@curl -s --max-time 5 "http://localhost:$${SUPERVISOR_PORT:-8080}/health" > /dev/null 2>&1 \
		&& echo "Supervisor is ready!" \
		|| echo "Supervisor is still starting... try 'make supervisor-status' in a few seconds"

supervisor-stop:
	@echo "Stopping supervisor..."
	@cd supervisor && docker compose down

supervisor-status:
	@echo "=== Supervisor Status ==="
	@docker ps --filter "name=claude-supervisor" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Supervisor not running"
	@echo ""
	@if curl -s --max-time 2 "http://localhost:$${SUPERVISOR_PORT:-8080}/health" 2>/dev/null | jq -r '"API Status: ONLINE\nLoop counts: " + (.loop_count | tostring) + "/" + (.max_loops | tostring)' 2>/dev/null; then \
		:; \
	else \
		echo "API Status: OFFLINE"; \
		echo "Run 'make supervisor-start' to start the service"; \
	fi

supervisor-logs:
	@cd supervisor && docker compose logs -f

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
