# Dockerfile - Claude Code Supervisor Container
# Agent-based QA validator with full capabilities (same as agent)
# Has READ-ONLY access to agent workspace
#
# Requires: claude-sandbox:latest (build with: docker build -f Dockerfile.base -t claude-sandbox:latest .)

FROM claude-sandbox:latest

# Create supervisor user with sudo access
RUN useradd -m -s /bin/bash supervisor \
    && echo "supervisor ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create directories for supervisor
RUN mkdir -p /home/supervisor/.claude/hooks \
    && mkdir -p /home/supervisor/.claude/state \
    && mkdir -p /home/supervisor/.local/bin \
    && mkdir -p /workspace \
    && mkdir -p /supervisor-workspaces \
    && mkdir -p /app \
    && chown -R supervisor:supervisor /home/supervisor \
    && chown -R supervisor:supervisor /supervisor-workspaces \
    && chown -R supervisor:supervisor /app

# Switch to supervisor user
USER supervisor
WORKDIR /home/supervisor

# Install Claude Code CLI using native installer
RUN curl -fsSL https://claude.ai/install.sh | bash

# Add Claude to PATH
ENV PATH="/home/supervisor/.local/bin:${PATH}"
ENV HOME="/home/supervisor"

# Copy supervisor files
COPY --chown=supervisor:supervisor app.py /app/
COPY --chown=supervisor:supervisor SUPERVISOR_PROMPT.md /app/
COPY --chown=supervisor:supervisor supervisor_stop_hook.sh /home/supervisor/.claude/hooks/
COPY --chown=supervisor:supervisor CLAUDE.md /home/supervisor/.claude/
COPY --chown=supervisor:supervisor settings.json /home/supervisor/.claude/

# Make hook executable
RUN chmod +x /home/supervisor/.claude/hooks/supervisor_stop_hook.sh

# Create default Claude configuration (skip onboarding)
RUN echo '{\
  "hasCompletedOnboarding": true,\
  "projects": {}\
}' > /home/supervisor/.claude.json

WORKDIR /app

# Expose API port (internal only - not published to host)
EXPOSE 8080

# Entry point - start Xvfb for Playwright, then run Flask API
ENTRYPOINT ["/bin/bash", "-c", "Xvfb :99 -screen 0 1920x1080x24 &>/dev/null & exec python3 app.py"]
