#!/usr/bin/env bash
# Print one worker instance id (folder name under workspaces/) for a running agent.
# - 0 running agents: message on stderr, exit 1
# - 1 running agent: print id on stdout, exit 0
# - 2+: menu on stderr, read choice from tty, print selected id on stdout
#
# Used by Makefile when attach, worker-info, or stop is invoked without W=.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

ENV_FILE="${ENV_FILE:-${ENV:-.env}}"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

CONTAINER_PREFIX="${CONTAINER_PREFIX:-claude}"
AGENT_PREFIX="${CONTAINER_PREFIX}-agent-"

containers=()
while IFS= read -r line; do
  [ -n "$line" ] && containers+=("$line")
done < <(docker ps --filter "name=${AGENT_PREFIX}" --format '{{.Names}}' 2>/dev/null | LC_ALL=C sort)

n="${#containers[@]}"
if [ "$n" -eq 0 ]; then
  echo "No running worker containers found." >&2
  echo "Start one with: make worker W=myworker TASK=\"…\" (w=, WORKER=, T=, TASKFILE=/TF=)" >&2
  exit 1
fi

id_from_container() {
  local c="$1"
  echo "${c#"${AGENT_PREFIX}"}"
}

if [ "$n" -eq 1 ]; then
  id_from_container "${containers[0]}"
  exit 0
fi

echo "=== Running workers ===" >&2
i=1
for c in "${containers[@]}"; do
  wid="$(id_from_container "$c")"
  printf '  %d) %s\n' "$i" "$wid" >&2
  i=$((i + 1))
done
printf 'Select worker [1-%d]: ' "$n" >&2
choice=""
if [ -r /dev/tty ]; then
  read -r choice </dev/tty || true
else
  read -r choice || true
fi
if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
  echo "Invalid selection (need a number 1-$n)." >&2
  exit 1
fi
if [ "$choice" -lt 1 ] || [ "$choice" -gt "$n" ]; then
  echo "Invalid selection (need a number 1-$n)." >&2
  exit 1
fi
idx=$((choice - 1))
id_from_container "${containers[$idx]}"
