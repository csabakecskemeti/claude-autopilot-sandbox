# Dockerfile - Claude Code Agent Container
# Autonomous coding agent with full capabilities
#
# Requires: claude-sandbox:latest (build with: docker build -f Dockerfile.base -t claude-sandbox:latest .)

FROM claude-sandbox:latest

# Create non-root user with sudo access
RUN useradd -m -s /bin/bash worker \
    && echo "worker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories for Claude data and workspace
RUN mkdir -p /home/worker/.claude/skills \
    && mkdir -p /home/worker/.claude/agents \
    && mkdir -p /home/worker/.claude/hooks \
    && mkdir -p /home/worker/.claude/state \
    && mkdir -p /home/worker/.local/bin \
    && mkdir -p /home/worker/workspace \
    && chown -R worker:worker /home/worker

# Switch to non-root user for installation
USER worker
WORKDIR /home/worker

# Install Claude Code CLI using native installer
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add Claude to PATH
ENV PATH="/home/worker/.local/bin:${PATH}"
ENV HOME="/home/worker"

# Copy skills, agents, hooks, and scripts into the image
COPY --chown=worker:worker skills-backup/ /home/worker/.claude/skills/
COPY --chown=worker:worker agents-backup/ /home/worker/.claude/agents/
COPY --chown=worker:worker worker-hooks/ /home/worker/.claude/hooks/
COPY --chown=worker:worker scripts/ /home/worker/.claude/scripts/

# Copy and install SearXNG MCP server for web search
COPY --chown=worker:worker searxng/mcp-server/ /home/worker/.claude/mcp-servers/searxng/
RUN cd /home/worker/.claude/mcp-servers/searxng && npm install --production

# Copy CLAUDE.md to .claude dir (will be copied to workspace by init-workspace.sh)
# Can't copy directly to workspace because volume mount shadows it
COPY --chown=worker:worker claude-backup/CLAUDE.md /home/worker/.claude/CLAUDE.md

# Make all skill, hook, and init scripts executable
RUN find /home/worker/.claude/skills -name "*.sh" -exec chmod +x {} \; \
    && find /home/worker/.claude/skills -name "*.py" -exec chmod +x {} \; \
    && find /home/worker/.claude/hooks -name "*.sh" -exec chmod +x {} \; \
    && find /home/worker/.claude/scripts -name "*.sh" -exec chmod +x {} \;

# Create directories for memory and notes persistence
RUN mkdir -p /home/worker/workspace/.memory \
    && mkdir -p /home/worker/workspace/.notes

# Create default Claude configuration
RUN echo '{\
  "hasCompletedOnboarding": true,\
  "projects": {\
    "/home/worker/workspace": {\
      "allowedTools": [],\
      "hasTrustDialogAccepted": true,\
      "projectOnboardingSeenCount": 1\
    }\
  }\
}' > /home/worker/.claude.json

# Create user-level settings.json for Claude (base config only)
# NOTE: MCP servers are configured in ~/.claude.json by init-workspace.sh
# NOTE: Hooks are configured in PROJECT-LEVEL settings by init-workspace.sh
RUN echo '{\
  "permissions": {\
    "allow": ["*"],\
    "deny": ["WebSearch", "WebFetch", "EnterPlanMode", "TodoWrite"]\
  },\
  "skipDangerousModePermissionPrompt": true\
}' > /home/worker/.claude/settings.json

WORKDIR /home/worker/workspace

# Build arg for model, converted to ENV for runtime use
ARG LLM_MODEL=nvidia.nvidia-nemotron-3-super-120b-a12b
ENV LLM_MODEL=${LLM_MODEL}

# Entry point - initialize workspace then run Claude in fully automated mode
# If ORIGINAL_TASK is set, pass it as positional argument (interactive mode with initial prompt)
# Without ORIGINAL_TASK, starts interactive mode with empty prompt
ENTRYPOINT ["/bin/bash", "-c", "~/.claude/scripts/init-workspace.sh && if [ -n \"$ORIGINAL_TASK\" ]; then exec claude --model \"$LLM_MODEL\" --dangerously-skip-permissions --allowedTools '*' \"$ORIGINAL_TASK\"; else exec claude --model \"$LLM_MODEL\" --dangerously-skip-permissions --allowedTools '*'; fi"]
CMD []
