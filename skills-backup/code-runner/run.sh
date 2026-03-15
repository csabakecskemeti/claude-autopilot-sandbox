#!/usr/bin/env bash
# Code runner - executes code snippets in various languages

set -e

LANG="$1"
CODE="$2"

if [[ -z "$LANG" ]] || [[ -z "$CODE" ]]; then
    echo "Usage: $0 <language> '<code>'"
    echo "Languages: python, javascript, bash"
    exit 1
fi

case "$LANG" in
    python|py)
        echo "$CODE" | python3
        ;;
    javascript|js|node)
        echo "$CODE" | node
        ;;
    bash|sh)
        echo "$CODE" | bash
        ;;
    *)
        echo "Unknown language: $LANG"
        echo "Supported: python, javascript, bash"
        exit 1
        ;;
esac
