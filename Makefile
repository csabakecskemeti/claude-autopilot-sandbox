# Claude Autopilot Sandbox - Makefile
# Run 'make help' for available commands

.PHONY: help setup build build-clean run stop logs ps clean shell status prune test env

# Default target
help:
	@echo "Claude Autopilot Sandbox"
	@echo ""
	@echo "Setup:"
	@echo "  make setup          Interactive wizard to create .env file"
	@echo "  make env            Show current config (secrets hidden)"
	@echo "  make test           Test LLM server connection"
	@echo "  make build          Build Docker images"
	@echo "  make build-clean    Build Docker images (no cache)"
	@echo ""
	@echo "Running:"
	@echo "  make run W=myproject T=\"Build a todo app\""
	@echo "                      Start agent with workspace and task"
	@echo "  make run W=myproject TF=task.txt"
	@echo "                      Start agent with task from file (for complex prompts)"
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

# ============================================================================
# Setup
# ============================================================================

setup:
	@./scripts/setup-wizard.sh

build:
	docker compose build

build-clean:
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

test:
	@if [ ! -f .env ]; then \
		echo "No .env file found. Run 'make setup' first."; \
		exit 1; \
	fi
	@. ./.env && echo "Testing connection to $$LLM_HOST:$$LLM_PORT..."
	@. ./.env && curl -s --max-time 5 "http://$$LLM_HOST:$$LLM_PORT/v1/models" > /dev/null \
		&& echo "OK - LLM server is reachable" \
		|| echo "FAILED - Cannot reach LLM server"

# ============================================================================
# Running
# ============================================================================

# Usage: make run W=workspace T="task description"
#    or: make run W=workspace TF=task.txt  (read task from file)
run:
ifndef W
	@echo "Error: Workspace required."
	@echo "Usage: make run W=myproject T=\"task\""
	@echo "   or: make run W=myproject TF=task.txt"
	@exit 1
endif
ifdef TF
	./run.sh "$(W)" "$$(cat $(TF))"
else
	./run.sh "$(W)" "$(T)"
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
