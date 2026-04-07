# Dockerfile - Claude Code Agent Container
# Autonomous coding agent with full capabilities
#
# Requires: claude-sandbox:latest (build with: docker build -f Dockerfile.base -t claude-sandbox:latest .)

FROM claude-sandbox:latest

# Create non-root user with sudo access
RUN useradd -m -s /bin/bash claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories for Claude data and workspace
RUN mkdir -p /home/claude/.claude/skills \
    && mkdir -p /home/claude/.claude/agents \
    && mkdir -p /home/claude/.claude/hooks \
    && mkdir -p /home/claude/.claude/state \
    && mkdir -p /home/claude/.local/bin \
    && mkdir -p /home/claude/workspace \
    && chown -R claude:claude /home/claude

# Switch to non-root user for installation
USER claude
WORKDIR /home/claude

# Install Claude Code CLI using native installer
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add Claude to PATH
ENV PATH="/home/claude/.local/bin:${PATH}"
ENV HOME="/home/claude"

# Copy skills, agents, hooks, and scripts into the image
COPY --chown=claude:claude skills-backup/ /home/claude/.claude/skills/
COPY --chown=claude:claude agents-backup/ /home/claude/.claude/agents/
COPY --chown=claude:claude hooks-backup/ /home/claude/.claude/hooks/
COPY --chown=claude:claude scripts/ /home/claude/.claude/scripts/

# Copy CLAUDE.md to .claude dir (will be copied to workspace by init-workspace.sh)
# Can't copy directly to workspace because volume mount shadows it
COPY --chown=claude:claude claude-backup/CLAUDE.md /home/claude/.claude/CLAUDE.md

# Make all skill, hook, and init scripts executable
RUN find /home/claude/.claude/skills -name "*.sh" -exec chmod +x {} \; \
    && find /home/claude/.claude/skills -name "*.py" -exec chmod +x {} \; \
    && find /home/claude/.claude/hooks -name "*.sh" -exec chmod +x {} \; \
    && find /home/claude/.claude/scripts -name "*.sh" -exec chmod +x {} \;

# Create directories for memory and notes persistence
RUN mkdir -p /home/claude/workspace/.memory \
    && mkdir -p /home/claude/workspace/.notes

# Create default Claude configuration
RUN echo '{\
  "hasCompletedOnboarding": true,\
  "projects": {\
    "/home/claude/workspace": {\
      "allowedTools": [],\
      "hasTrustDialogAccepted": true,\
      "projectOnboardingSeenCount": 1\
    }\
  }\
}' > /home/claude/.claude.json

# Create user-level settings.json for Claude (base config only)
# NOTE: Hooks are configured in PROJECT-LEVEL settings by init-workspace.sh
# because project-level settings take precedence over user-level
RUN echo '{\
  "permissions": {\
    "allow": ["*"],\
    "deny": ["WebSearch", "WebFetch", "EnterPlanMode", "TodoWrite"]\
  },\
  "skipDangerousModePermissionPrompt": true\
}' > /home/claude/.claude/settings.json

WORKDIR /home/claude/workspace

# Build arg for model, converted to ENV for runtime use
ARG LLM_MODEL=nvidia.nvidia-nemotron-3-super-120b-a12b
ENV LLM_MODEL=${LLM_MODEL}

# Entry point - initialize workspace then run Claude in fully automated mode
# If ORIGINAL_TASK is set, pass it as positional argument (interactive mode with initial prompt)
# Without ORIGINAL_TASK, starts interactive mode with empty prompt
ENTRYPOINT ["/bin/bash", "-c", "~/.claude/scripts/init-workspace.sh && if [ -n \"$ORIGINAL_TASK\" ]; then exec claude --model \"$LLM_MODEL\" --dangerously-skip-permissions --allowedTools '*' \"$ORIGINAL_TASK\"; else exec claude --model \"$LLM_MODEL\" --dangerously-skip-permissions --allowedTools '*'; fi"]
CMD []
