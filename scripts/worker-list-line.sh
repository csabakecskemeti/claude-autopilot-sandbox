#!/usr/bin/env bash
# Print one human line for a worker run: "  <id>: <effective_state> [<model>]"
# Effective state reconciles metadata with docker (agent + supervisor).
# Usage: worker-list-line.sh /path/to/metadata.json

META="${1:?metadata.json path required}"

FN=$(jq -r '.task.full_name // empty' "$META" 2>/dev/null) || FN=""
FSTATE=$(jq -r '.status.state // "unknown"' "$META" 2>/dev/null) || FSTATE="unknown"
AGENT=$(jq -r '.containers.agent.name // empty' "$META" 2>/dev/null) || AGENT=""
SUP=$(jq -r '.containers.supervisor.name // empty' "$META" 2>/dev/null) || SUP=""
MODEL=$(jq -r '.env.llm_model // "unknown"' "$META" 2>/dev/null) || MODEL="unknown"

agent_live=0
sup_live=0
if [ -n "$AGENT" ] && [ -n "$(docker ps -q --filter "name=$AGENT" 2>/dev/null || true)" ]; then
  agent_live=1
fi
if [ -n "$SUP" ] && [ -n "$(docker ps -q --filter "name=$SUP" 2>/dev/null || true)" ]; then
  sup_live=1
fi

if [ "$agent_live" -eq 1 ]; then
  DISP="running"
  if [ "$sup_live" -eq 0 ] && [ -n "$SUP" ]; then
    DISP="running (supervisor down)"
  fi
  if [ "$FSTATE" = "stopped" ] || [ "$FSTATE" = "cleaned" ]; then
    DISP="running (metadata: $FSTATE)"
  fi
elif [ "$sup_live" -eq 1 ]; then
  DISP="orphaned"
else
  case "$FSTATE" in
    running) DISP="stopped" ;;
    starting) DISP="starting" ;;
    *) DISP="$FSTATE" ;;
  esac
fi

[ -n "$FN" ] || exit 0
printf '  %s: %s [%s]\n' "$FN" "$DISP" "$MODEL"
