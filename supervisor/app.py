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
import json
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
# For shared supervisor mode, these are base paths; actual paths come from request
WORKSPACES_BASE = os.environ.get("WORKSPACES_BASE", "/workspaces")  # Base for all agent workspaces
SUPERVISOR_WORKSPACES = os.environ.get("SUPERVISOR_WORKSPACES", "/supervisor-workspaces")
MAX_LOOPS = int(os.environ.get("SUPERVISOR_MAX_LOOPS", "20"))
TIMEOUT = int(os.environ.get("SUPERVISOR_TIMEOUT", "3600"))  # 1 hour default for complex tasks

# Legacy single-workspace mode (backwards compatibility)
WORKSPACE = os.environ.get("WORKSPACE_PATH", "/workspace")
TASK_STORAGE = os.environ.get("TASK_STORAGE", "/task")

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

Evaluate if this task is complete. Check {workspace_path} for the agent's code.

If the task is COMPLETE, say "status: complete" in your response.
If the task is NOT COMPLETE, say "status: not_complete" and explain what needs to be done.
'''


def get_loop_count(suffix: str = "") -> int:
    """Get current loop count from supervisor workspace"""
    counter_file = Path(SUPERVISOR_WORKSPACES) / f".loop_count{suffix}"
    if counter_file.exists():
        try:
            return int(counter_file.read_text().strip())
        except (ValueError, IOError):
            return 0
    return 0


def increment_loop_count(suffix: str = "") -> int:
    """Increment and return new loop count"""
    counter_file = Path(SUPERVISOR_WORKSPACES) / f".loop_count{suffix}"
    current = get_loop_count(suffix)
    new_count = current + 1
    counter_file.write_text(str(new_count))
    return new_count


def reset_loop_count(suffix: str = ""):
    """Reset loop count (called when task is complete)"""
    counter_file = Path(SUPERVISOR_WORKSPACES) / f".loop_count{suffix}"
    if counter_file.exists():
        counter_file.unlink()


def get_history_file(instance_id: str) -> Path:
    """Get path to evaluation history file for an instance"""
    return Path(SUPERVISOR_WORKSPACES) / f".history_{instance_id}.jsonl"


def save_evaluation(instance_id: str, loop: int, status: str, output: str, workspace: str = None):
    """Save evaluation result to instance history (JSONL format)"""
    history_file = get_history_file(instance_id)
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "instance": instance_id,
        "loop": loop,
        "status": status,
        "workspace": workspace,
        "output_preview": output[:500] if output else "",
        "output_length": len(output) if output else 0
    }
    with open(history_file, "a") as f:
        f.write(json.dumps(entry) + "\n")
    log.info(f"Saved evaluation to history: {instance_id} loop={loop} status={status}")


def get_evaluation_history(instance_id: str) -> list:
    """Get evaluation history for an instance"""
    history_file = get_history_file(instance_id)
    if not history_file.exists():
        return []

    history = []
    with open(history_file, "r") as f:
        for line in f:
            try:
                history.append(json.loads(line.strip()))
            except json.JSONDecodeError:
                continue
    return history


def list_instances() -> list:
    """List all known instance IDs from history files"""
    instances = []
    supervisor_dir = Path(SUPERVISOR_WORKSPACES)
    if not supervisor_dir.exists():
        return instances

    for f in supervisor_dir.glob(".history_*.jsonl"):
        instance_id = f.stem.replace(".history_", "")
        history = get_evaluation_history(instance_id)
        loop_count = get_loop_count(f"_{instance_id}" if instance_id != "default" else "")
        instances.append({
            "instance_id": instance_id,
            "evaluations": len(history),
            "current_loop": loop_count,
            "last_status": history[-1]["status"] if history else None,
            "last_evaluation": history[-1]["timestamp"] if history else None
        })
    return instances


def read_original_task(workspace_path: str = None, task_path: str = None) -> str:
    """
    Read original task from IMMUTABLE task storage.

    Args:
        workspace_path: Path to agent workspace (for shared supervisor mode)
        task_path: Path to task storage (for shared supervisor mode)

    The task storage is a host folder mounted read-only to both containers.
    Neither agent nor supervisor can modify it - Docker enforces this at kernel level.
    """
    # Use provided paths or fall back to legacy environment variables
    task_storage = task_path or TASK_STORAGE
    workspace = workspace_path or WORKSPACE

    # Primary: Read from immutable task storage (host-controlled, read-only mount)
    immutable_task = Path(task_storage) / "original_task"
    if immutable_task.exists():
        log.info(f"Reading task from immutable storage: {immutable_task}")
        return immutable_task.read_text().strip()

    # Fallback: Read from agent workspace (less secure, for backwards compatibility)
    log.warning("Immutable task storage not found, falling back to agent workspace")

    task_file = Path(workspace) / ".original_task"
    if task_file.exists():
        return task_file.read_text().strip()

    # Last resort: try TASK.md or similar
    for fallback in ["TASK.md", "task.md", "README.md"]:
        fb_path = Path(workspace) / fallback
        if fb_path.exists():
            content = fb_path.read_text()
            return content[:500] + ("..." if len(content) > 500 else "")

    return "Unknown task - no task file found in task storage or workspace"


def prepare_turn_workspace(turn: int, instance_id: str = "default") -> Path:
    """Create isolated workspace for this evaluation turn"""
    # Include instance_id in path for multi-agent isolation
    if instance_id != "default":
        turn_dir = Path(SUPERVISOR_WORKSPACES) / instance_id / f"TURN{turn}"
    else:
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


def build_prompt(original_task: str, workspace_path: str = "/workspace") -> str:
    """Build the supervisor evaluation prompt"""
    template = load_prompt_template()
    return template.format(original_task=original_task, workspace_path=workspace_path)


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

    Query/Body params (for shared supervisor mode):
        workspace: Name of workspace (e.g., "myproject") - resolved to /workspaces/<name>
        task: Name of task storage (e.g., "myproject-task") - resolved to /workspaces/<name>
        instance: Instance identifier for loop counting (optional)

    Returns:
        {
            "status": "complete" | "not_complete",
            "message": "Raw supervisor output (feedback for the agent)"
        }
    """
    log.info("=" * 50)
    log.info("Evaluation requested")

    # Get workspace info from request (for shared supervisor mode)
    if request.method == "POST" and request.is_json:
        data = request.get_json()
        workspace_name = data.get("workspace")
        task_name = data.get("task")
        instance_id = data.get("instance", "default")
    else:
        workspace_name = request.args.get("workspace")
        task_name = request.args.get("task")
        instance_id = request.args.get("instance", "default")

    # Resolve paths
    if workspace_name:
        workspace_path = f"{WORKSPACES_BASE}/{workspace_name}"
        task_path = f"{WORKSPACES_BASE}/{task_name}" if task_name else None
        log.info(f"Shared mode - workspace: {workspace_name}, task: {task_name}, instance: {instance_id}")
    else:
        workspace_path = WORKSPACE
        task_path = TASK_STORAGE
        instance_id = "default"
        log.info("Legacy mode - using environment paths")

    # Use instance-specific loop counter for shared mode
    loop_file_suffix = f"_{instance_id}" if instance_id != "default" else ""

    # Increment loop count (instance-specific)
    loop_count = increment_loop_count(loop_file_suffix)
    log.info(f"Evaluation loop: {loop_count} / {MAX_LOOPS} (instance: {instance_id})")

    # Check limit
    if loop_count > MAX_LOOPS:
        log.warning(f"MAX LOOPS ({MAX_LOOPS}) exceeded - forcing allow")
        reset_loop_count(loop_file_suffix)
        return jsonify({
            "status": "complete",
            "message": f"MAX SUPERVISOR LOOPS ({MAX_LOOPS}) REACHED.\n\nTask may be incomplete but allowing stop to prevent infinite loop.\n\nPlease review the work manually."
        })

    # Read original task
    original_task = read_original_task(workspace_path, task_path)
    log.info(f"Original task: {original_task[:100]}...")

    # Prepare workspace for this turn
    turn_workspace = prepare_turn_workspace(loop_count, instance_id)
    log.info(f"Turn workspace: {turn_workspace}")

    # Build prompt (include workspace path for shared mode)
    prompt = build_prompt(original_task, workspace_path)

    # Save prompt for debugging
    (turn_workspace / "prompt.txt").write_text(prompt)

    # Run supervisor
    status, output = run_supervisor(prompt, turn_workspace)

    # Save evaluation to history
    save_evaluation(instance_id, loop_count, status, output, workspace_path)

    # Reset loop counter on completion
    if status == "complete":
        reset_loop_count(loop_file_suffix)

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
    """Health check endpoint with optional instance stats"""
    instances = list_instances()
    return jsonify({
        "status": "healthy",
        "service": "supervisor",
        "loop_count": get_loop_count(),
        "max_loops": MAX_LOOPS,
        "active_instances": len(instances),
        "instances": instances
    })


@app.route("/instances", methods=["GET"])
def instances():
    """List all agent instances with their evaluation history"""
    return jsonify({
        "instances": list_instances()
    })


@app.route("/history/<instance_id>", methods=["GET"])
def history(instance_id: str):
    """Get evaluation history for a specific instance"""
    evals = get_evaluation_history(instance_id)
    loop_count = get_loop_count(f"_{instance_id}" if instance_id != "default" else "")
    return jsonify({
        "instance_id": instance_id,
        "current_loop": loop_count,
        "evaluations": evals
    })


@app.route("/reset", methods=["POST"])
def reset():
    """Reset loop counter and optionally history for an instance"""
    if request.is_json:
        data = request.get_json()
        instance_id = data.get("instance")
    else:
        instance_id = request.args.get("instance")

    if instance_id:
        # Reset specific instance
        loop_file_suffix = f"_{instance_id}" if instance_id != "default" else ""
        reset_loop_count(loop_file_suffix)

        # Optionally clear history
        if request.args.get("clear_history") == "true" or (request.is_json and data.get("clear_history")):
            history_file = get_history_file(instance_id)
            if history_file.exists():
                history_file.unlink()
                log.info(f"Cleared history for instance: {instance_id}")

        return jsonify({"status": "reset", "instance": instance_id, "loop_count": 0})
    else:
        # Reset global (legacy)
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
