# Dockerfile for Vanilla Claude Code (Anthropic API)
# Uses native Claude tools - simpler setup

FROM debian:bookworm-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Basic tools
    git \
    curl \
    wget \
    bash \
    ca-certificates \
    sudo \
    jq \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    # Node.js
    nodejs \
    npm \
    # Utilities
    htop \
    vim \
    less \
    uuid-runtime \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --break-system-packages \
    requests \
    langfuse

# Create non-root user with sudo access
RUN useradd -m -s /bin/bash claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories
RUN mkdir -p /home/claude/.claude/agents \
    && mkdir -p /home/claude/.claude/hooks \
    && mkdir -p /home/claude/.claude/state \
    && mkdir -p /home/claude/.local/bin \
    && mkdir -p /home/claude/workspace \
    && chown -R claude:claude /home/claude

# Switch to non-root user
USER claude
WORKDIR /home/claude

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add Claude to PATH
ENV PATH="/home/claude/.local/bin:${PATH}"

# Copy agents from backup folder
COPY --chown=claude:claude agents-backup/ /home/claude/.claude/agents/

# Copy hooks from backup folder (for tracing)
COPY --chown=claude:claude hooks-backup/ /home/claude/.claude/hooks/

# Copy scripts
COPY --chown=claude:claude scripts/ /home/claude/.claude/scripts/

# Copy CLAUDE.md from backup (the one for inner Claude)
COPY --chown=claude:claude claude-backup/CLAUDE.md /home/claude/workspace/CLAUDE.md

# Make scripts executable
RUN find /home/claude/.claude/hooks -name "*.sh" -exec chmod +x {} \; \
    && find /home/claude/.claude/scripts -name "*.sh" -exec chmod +x {} \;

# Create default Claude configuration with all prompts pre-accepted
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

# Create user-level settings.json to skip permission prompts
RUN echo '{\
  "permissions": {\
    "allow": ["*"],\
    "deny": []\
  },\
  "skipDangerousModePermissionPrompt": true,\
  "skipApiKeyConfirmation": true\
}' > /home/claude/.claude/settings.json

WORKDIR /home/claude/workspace

# Default model (can override via env)
ENV CLAUDE_MODEL=claude-sonnet-4-20250514

SHELL ["/bin/bash", "-c"]

# Entry point - initialize workspace then run Claude
ENTRYPOINT ["/bin/bash", "-c", "~/.claude/scripts/init-workspace.sh && exec claude --dangerously-skip-permissions \"$@\"", "--"]
CMD []
