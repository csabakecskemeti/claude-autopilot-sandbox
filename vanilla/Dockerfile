# Dockerfile for Vanilla Claude Code (Anthropic API)
# Uses native Claude tools + Playwright for browser automation

FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

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
    # Virtual display for headless browser
    xvfb \
    # Utilities
    htop \
    vim \
    less \
    uuid-runtime \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install --break-system-packages \
    requests \
    langfuse \
    playwright

# Install Playwright browsers (Chromium only - Chrome doesn't support ARM64)
# Install to shared location so claude user can access at runtime
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN playwright install chromium --with-deps \
    && chmod -R 755 /opt/ms-playwright

# Create non-root user with sudo access
RUN useradd -m -s /bin/bash worker \
    && echo "worker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories
RUN mkdir -p /home/worker/.claude/agents \
    && mkdir -p /home/worker/.claude/hooks \
    && mkdir -p /home/worker/.claude/skills \
    && mkdir -p /home/worker/.claude/state \
    && mkdir -p /home/worker/.local/bin \
    && mkdir -p /home/worker/workspace \
    && chown -R worker:worker /home/worker

# Switch to non-root user
USER worker
WORKDIR /home/worker

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add Claude to PATH
ENV PATH="/home/worker/.local/bin:${PATH}"

# Virtual display for Playwright
ENV DISPLAY=:99

# Copy agents from backup folder
COPY --chown=worker:worker agents-backup/ /home/worker/.claude/agents/

# Copy hooks from backup folder (for tracing)
COPY --chown=worker:worker worker-hooks/ /home/worker/.claude/hooks/

# Copy skills from backup folder
COPY --chown=worker:worker skills-backup/ /home/worker/.claude/skills/

# Copy scripts
COPY --chown=worker:worker scripts/ /home/worker/.claude/scripts/

# Copy CLAUDE.md to .claude dir (will be copied to workspace by init-workspace.sh)
# Can't copy directly to workspace because volume mount shadows it
COPY --chown=worker:worker claude-backup/CLAUDE.md /home/worker/.claude/CLAUDE.md

# Make scripts executable
RUN find /home/worker/.claude/hooks -name "*.sh" -exec chmod +x {} \; \
    && find /home/worker/.claude/scripts -name "*.sh" -exec chmod +x {} \; \
    && find /home/worker/.claude/skills -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true \
    && find /home/worker/.claude/skills -name "*.py" -exec chmod +x {} \; 2>/dev/null || true

# Create default Claude configuration with all prompts pre-accepted
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

# Create user-level settings.json to skip permission prompts
RUN echo '{\
  "permissions": {\
    "allow": ["*"],\
    "deny": []\
  },\
  "skipDangerousModePermissionPrompt": true,\
  "skipApiKeyConfirmation": true\
}' > /home/worker/.claude/settings.json

WORKDIR /home/worker/workspace

# Default model (can override via env, or leave empty for Claude's default)
ENV CLAUDE_MODEL=${CLAUDE_MODEL:-}

SHELL ["/bin/bash", "-c"]

# Entry point - initialize workspace then run Claude
ENTRYPOINT ["/bin/bash", "-c", "~/.claude/scripts/init-workspace.sh && exec claude --dangerously-skip-permissions \"$@\"", "--"]
CMD []
