# Dockerfile for Claude Code with Local LLM Support
# Self-contained installation with full capabilities

FROM debian:bookworm-slim

# Install system dependencies including tools for skills
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
    # Node.js (for Claude Code and JS execution)
    nodejs \
    npm \
    # PDF tools (OCR handled by vision model)
    poppler-utils \
    # Virtual display for GUI apps (pygame, etc.)
    xvfb \
    x11-utils \
    imagemagick \
    # Database clients
    sqlite3 \
    postgresql-client \
    # Playwright dependencies
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    # Additional utilities
    htop \
    vim \
    less \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages for skills
RUN pip3 install --break-system-packages \
    markdown \
    pandas \
    requests \
    beautifulsoup4 \
    playwright

# Install Playwright browsers
RUN playwright install chromium

# Create non-root user with sudo access
RUN useradd -m -s /bin/bash claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories for Claude data and workspace
RUN mkdir -p /home/claude/.claude/skills \
    && mkdir -p /home/claude/.claude/agents \
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

# Copy skills and agents into the image
COPY --chown=claude:claude skills-backup/ /home/claude/.claude/skills/
COPY --chown=claude:claude agents-backup/ /home/claude/.claude/agents/

# Copy CLAUDE.md for autonomous operation instructions
COPY --chown=claude:claude CLAUDE.md /home/claude/workspace/CLAUDE.md

# Make all skill scripts executable
RUN find /home/claude/.claude/skills -name "*.sh" -exec chmod +x {} \;

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

# Create settings.json for Claude - allow all tools except native WebSearch
RUN echo '{\
  "permissions": {\
    "allow": ["*"],\
    "deny": ["WebSearch"]\
  },\
  "skipDangerousModePermissionPrompt": true\
}' > /home/claude/.claude/settings.json

WORKDIR /home/claude/workspace

# Environment variables set via docker-compose.yml
# ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN passed at runtime

# Build arg for model, converted to ENV for runtime use
ARG LLM_MODEL=nvidia.nvidia-nemotron-3-super-120b-a12b
ENV LLM_MODEL=${LLM_MODEL}

# Default shell
SHELL ["/bin/bash", "-c"]

# Entry point - fully automated mode with all tools allowed
ENTRYPOINT ["/bin/bash", "-c", "exec claude --model \"$LLM_MODEL\" --dangerously-skip-permissions --allowedTools '*' \"$@\"", "--"]
CMD []
