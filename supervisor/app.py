#!/usr/bin/env python3
"""
Supervisor API - Agent-Based QA Validator

Uses Claude Code CLI to evaluate if the agent has completed its task.
The supervisor has full Claude Code capabilities but READ-ONLY access to agent workspace.

Flow:
1. Stop hook calls POST /evaluate
2. Supervisor creates isolated workspace for this turn
3. Runs Claude Code CLI with evaluation prompt
4. Returns raw output - no JSON parsing (simpler, more robust)
5. Determines status by looking for "complete" vs "not_complete" keywords
"""

import os
import re
import subprocess
import logging
from datetime import datetime, timezone
from pathlib import Path
from flask import Flask, jsonify, request

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
log = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration - using SUPERVISOR_ prefix for clarity
WORKSPACE = os.environ.get("WORKSPACE_PATH", "/workspace")
SUPERVISOR_WORKSPACES = os.environ.get("SUPERVISOR_WORKSPACES", "/supervisor-workspaces")
TASK_STORAGE = os.environ.get("TASK_STORAGE", "/task")  # Immutable task storage (read-only mount)
MAX_LOOPS = int(os.environ.get("SUPERVISOR_MAX_LOOPS", "20"))
TIMEOUT = int(os.environ.get("SUPERVISOR_TIMEOUT", "3600"))  # 1 hour default for complex tasks

# LLM config (supervisor uses same backend as agent)
LLM_MODEL = os.environ.get("LLM_MODEL", "")

# Supervisor prompt template - loaded from file
PROMPT_FILE = Path(__file__).parent / "SUPERVISOR_PROMPT.md"


def load_prompt_template() -> str:
    """Load supervisor prompt template from file"""
    if PROMPT_FILE.exists():
        return PROMPT_FILE.read_text()

    # Fallback if file not found
    log.warning(f"Prompt file not found: {PROMPT_FILE}, using fallback")
    return '''# SUPERVISOR TASK: Evaluate Agent's Work

## ORIGINAL USER REQUEST
---
{original_task}
---

Evaluate if this task is complete. Check /workspace for the agent's code.

If the task is COMPLETE, say "status: complete" in your response.
If the task is NOT COMPLETE, say "status: not_complete" and explain what needs to be done.
'''


def get_loop_count() -> int:
    """Get current loop count from supervisor workspace"""
    counter_file = Path(SUPERVISOR_WORKSPACES) / ".loop_count"
    if counter_file.exists():
        try:
            return int(counter_file.read_text().strip())
        except (ValueError, IOError):
            return 0
    return 0


def increment_loop_count() -> int:
    """Increment and return new loop count"""
    counter_file = Path(SUPERVISOR_WORKSPACES) / ".loop_count"
    current = get_loop_count()
    new_count = current + 1
    counter_file.write_text(str(new_count))
    return new_count


def reset_loop_count():
    """Reset loop count (called when task is complete)"""
    counter_file = Path(SUPERVISOR_WORKSPACES) / ".loop_count"
    if counter_file.exists():
        counter_file.unlink()


def read_original_task() -> str:
    """
    Read original task from IMMUTABLE task storage.

    The task storage is a host folder mounted read-only to both containers.
    Neither agent nor supervisor can modify it - Docker enforces this at kernel level.
    """
    # Primary: Read from immutable task storage (host-controlled, read-only mount)
    immutable_task = Path(TASK_STORAGE) / "original_task"
    if immutable_task.exists():
        log.info("Reading task from immutable storage (tamper-proof)")
        return immutable_task.read_text().strip()

    # Fallback: Read from agent workspace (less secure, for backwards compatibility)
    log.warning("Immutable task storage not found, falling back to agent workspace")

    task_file = Path(WORKSPACE) / ".original_task"
    if task_file.exists():
        return task_file.read_text().strip()

    # Last resort: try TASK.md or similar
    for fallback in ["TASK.md", "task.md", "README.md"]:
        fb_path = Path(WORKSPACE) / fallback
        if fb_path.exists():
            content = fb_path.read_text()
            return content[:500] + ("..." if len(content) > 500 else "")

    return "Unknown task - no task file found in /task or /workspace"


def prepare_turn_workspace(turn: int) -> Path:
    """Create isolated workspace for this evaluation turn"""
    turn_dir = Path(SUPERVISOR_WORKSPACES) / f"TURN{turn}"
    turn_dir.mkdir(parents=True, exist_ok=True)

    # Create .claude directory for this turn
    claude_dir = turn_dir / ".claude"
    claude_dir.mkdir(exist_ok=True)

    # Copy settings to turn workspace (for hooks config)
    settings_src = Path.home() / ".claude" / "settings.json"
    if settings_src.exists():
        (claude_dir / "settings.json").write_text(settings_src.read_text())

    return turn_dir


def build_prompt(original_task: str) -> str:
    """Build the supervisor evaluation prompt"""
    template = load_prompt_template()
    return template.format(original_task=original_task)


def determine_status(output: str) -> str:
    """
    Determine completion status from supervisor output.

    Simple keyword matching - no complex JSON parsing.
    The LLM will understand the raw feedback anyway.
    """
    output_lower = output.lower()

    # Look for explicit status indicators
    # Order matters - check "not_complete" first since it contains "complete"
    if "status: not_complete" in output_lower or "status:not_complete" in output_lower:
        return "not_complete"
    if '"status": "not_complete"' in output_lower or "'status': 'not_complete'" in output_lower:
        return "not_complete"
    if "not complete" in output_lower or "not_complete" in output_lower:
        return "not_complete"

    # Check for complete indicators
    if "status: complete" in output_lower or "status:complete" in output_lower:
        return "complete"
    if '"status": "complete"' in output_lower or "'status': 'complete'" in output_lower:
        return "complete"
    if "task is complete" in output_lower or "task complete" in output_lower:
        return "complete"

    # Default to not_complete if unclear
    return "not_complete"


def run_supervisor(prompt: str, workspace: Path) -> tuple[str, str]:
    """
    Run Claude Code CLI for evaluation.

    Returns: (status, raw_output)
    """
    log.info(f"Running supervisor in workspace: {workspace}")

    cmd = [
        "claude",
        "--dangerously-skip-permissions",
        "--allowedTools", "*",
        "-p", prompt
    ]

    # Add model if specified
    if LLM_MODEL:
        cmd.extend(["--model", LLM_MODEL])

    env = os.environ.copy()
    env["HOME"] = str(Path.home())

    try:
        result = subprocess.run(
            cmd,
            cwd=str(workspace),
            env=env,
            capture_output=True,
            text=True,
            timeout=TIMEOUT
        )

        stdout = result.stdout
        stderr = result.stderr

        # Save full output for debugging
        (workspace / "supervisor_stdout.txt").write_text(stdout)
        if stderr:
            (workspace / "supervisor_stderr.txt").write_text(stderr)

        log.info(f"Claude exit code: {result.returncode}")
        log.info(f"Output length: {len(stdout)} chars")

        # Determine status from output
        status = determine_status(stdout)
        log.info(f"Determined status: {status}")

        return status, stdout

    except subprocess.TimeoutExpired:
        log.error(f"Supervisor timed out after {TIMEOUT}s")
        return "not_complete", f"Supervisor evaluation timed out after {TIMEOUT} seconds. Please continue working on your task."

    except Exception as e:
        log.error(f"Supervisor error: {e}")
        return "not_complete", f"Supervisor encountered an error: {str(e)}"


@app.route("/evaluate", methods=["POST", "GET"])
def evaluate():
    """
    Main evaluation endpoint.
    Called by stop hook to verify task completion.

    Returns:
        {
            "status": "complete" | "not_complete",
            "message": "Raw supervisor output (feedback for the agent)"
        }
    """
    log.info("=" * 50)
    log.info("Evaluation requested")

    # Increment loop count
    loop_count = increment_loop_count()
    log.info(f"Evaluation loop: {loop_count} / {MAX_LOOPS}")

    # Check limit
    if loop_count > MAX_LOOPS:
        log.warning(f"MAX LOOPS ({MAX_LOOPS}) exceeded - forcing allow")
        reset_loop_count()
        return jsonify({
            "status": "complete",
            "message": f"MAX SUPERVISOR LOOPS ({MAX_LOOPS}) REACHED.\n\nTask may be incomplete but allowing stop to prevent infinite loop.\n\nPlease review the work manually."
        })

    # Read original task
    original_task = read_original_task()
    log.info(f"Original task: {original_task[:100]}...")

    # Prepare workspace for this turn
    turn_workspace = prepare_turn_workspace(loop_count)
    log.info(f"Turn workspace: {turn_workspace}")

    # Build prompt
    prompt = build_prompt(original_task)

    # Save prompt for debugging
    (turn_workspace / "prompt.txt").write_text(prompt)

    # Run supervisor
    status, output = run_supervisor(prompt, turn_workspace)

    # Reset loop counter on completion
    if status == "complete":
        reset_loop_count()

    # Build response message
    if status == "complete":
        message = f"TASK COMPLETE (verified by supervisor, loop {loop_count})\n\n"
        message += "--- Supervisor Evaluation ---\n"
        message += output
    else:
        message = f"TASK NOT COMPLETE (loop {loop_count}/{MAX_LOOPS})\n\n"
        message += "--- Supervisor Feedback ---\n"
        message += output

    log.info(f"Returning status: {status}")

    return jsonify({
        "status": status,
        "message": message
    })


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": "supervisor",
        "loop_count": get_loop_count(),
        "max_loops": MAX_LOOPS
    })


@app.route("/reset", methods=["POST"])
def reset():
    """Reset loop counter (for testing)"""
    reset_loop_count()
    return jsonify({"status": "reset", "loop_count": 0})


if __name__ == "__main__":
    log.info("=" * 50)
    log.info("Starting Supervisor API")
    log.info(f"Workspace (agent): {WORKSPACE}")
    log.info(f"Supervisor workspaces: {SUPERVISOR_WORKSPACES}")
    log.info(f"Max loops: {MAX_LOOPS}")
    log.info(f"Timeout: {TIMEOUT}s")
    log.info(f"Model: {LLM_MODEL or '(default)'}")
    log.info("=" * 50)

    app.run(host="0.0.0.0", port=8080)
