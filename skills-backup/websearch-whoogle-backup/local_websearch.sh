#!/usr/bin/env bash
# Wrapper for the local web-search service (curl)

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <query>"
  exit 1
fi

# Use WHOOGLE_URL from environment, default to empty (disabled)
WHOOGLE_URL="${WHOOGLE_URL:-}"

if [[ -z "$WHOOGLE_URL" ]]; then
  echo "Error: WHOOGLE_URL not configured. Set it in .env file."
  exit 1
fi

QUERY="$*"
curl -sG "${WHOOGLE_URL}/search" \
     --data-urlencode "q=$QUERY" \
     --data-urlencode "format=json"
