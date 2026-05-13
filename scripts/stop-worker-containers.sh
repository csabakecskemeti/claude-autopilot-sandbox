#!/usr/bin/env bash
# Stop (and optionally rm) agent + supervisor for a worker run id (TASK_FULL_NAME).
# Uses names from metadata when present, plus canonical fallbacks so a missed
# supervisor (e.g. empty/wrong jq field) is still stopped.
#
# Usage:
#   stop-worker-containers.sh <worker_id>
#   stop-worker-containers.sh --rm <worker_id>    # stop then docker rm

set -euo pipefail

DO_RM=0
if [ "${1:-}" = "--rm" ]; then
  DO_RM=1
  shift
fi

WID="${1:?worker id (e.g. mylabel_20260503_120000) required}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env
  set +a
fi

WSBASE="${WORKSPACE_BASE:-./workspaces}"
PREFIX="${CONTAINER_PREFIX:-claude}"
META="${WSBASE}/${WID}/metadata.json"

AGENT=""
SUP=""
if [ -f "$META" ]; then
  AGENT=$(jq -r '.containers.agent.name // empty' "$META" 2>/dev/null || true)
  SUP=$(jq -r '.containers.supervisor.name // empty' "$META" 2>/dev/null || true)
fi

A_FALL="${PREFIX}-agent-${WID}"
S_FALL="${PREFIX}-supervisor-${WID}"

SEEN="|"
names=()
for n in "$AGENT" "$A_FALL" "$SUP" "$S_FALL"; do
  [ -n "$n" ] || continue
  case "$SEEN" in *"|${n}|"*) continue ;; esac
  SEEN="${SEEN}${n}|"
  names+=("$n")
done

for n in "${names[@]}"; do
  if docker inspect "$n" >/dev/null 2>&1; then
    echo "  Stopping: $n"
    if ! docker stop -t 10 "$n" >/dev/null 2>&1; then
      echo "  Warning: docker stop failed for $n" >&2
    fi
  fi
done

if [ "$DO_RM" -eq 1 ]; then
  for n in "${names[@]}"; do
    if docker inspect "$n" >/dev/null 2>&1; then
      echo "  Removing: $n"
      docker rm "$n" >/dev/null 2>&1 || true
    fi
  done
fi
