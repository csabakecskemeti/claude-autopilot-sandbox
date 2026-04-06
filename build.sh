#!/bin/bash
# Build script for Claude Sandbox containers
#
# Usage:
#   ./build.sh           # Build all (base + agent + supervisor)
#   ./build.sh base      # Build only base image
#   ./build.sh agent     # Build base + agent
#   ./build.sh supervisor # Build base + supervisor
#   ./build.sh --no-cache # Build all without cache

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
NO_CACHE=""
TARGET="${1:-all}"

if [ "$1" = "--no-cache" ]; then
    NO_CACHE="--no-cache"
    TARGET="${2:-all}"
fi

if [ "$2" = "--no-cache" ]; then
    NO_CACHE="--no-cache"
fi

echo "=========================================="
echo "Claude Sandbox Build"
echo "=========================================="
echo "Target: $TARGET"
echo "No cache: ${NO_CACHE:-no}"
echo ""

# Build base image first (required by agent and supervisor)
build_base() {
    echo ">>> Building claude-sandbox base image..."
    docker build $NO_CACHE -f Dockerfile.base -t claude-sandbox:latest .
    echo ">>> Base image built successfully"
    echo ""
}

# Build agent image
build_agent() {
    echo ">>> Building agent image..."
    docker compose build $NO_CACHE agent
    echo ">>> Agent image built successfully"
    echo ""
}

# Build supervisor image
build_supervisor() {
    echo ">>> Building supervisor image..."
    docker compose build $NO_CACHE supervisor
    echo ">>> Supervisor image built successfully"
    echo ""
}

case "$TARGET" in
    base)
        build_base
        ;;
    agent)
        build_base
        build_agent
        ;;
    supervisor)
        build_base
        build_supervisor
        ;;
    all)
        build_base
        build_agent
        build_supervisor
        ;;
    *)
        echo "Unknown target: $TARGET"
        echo "Usage: ./build.sh [base|agent|supervisor|all] [--no-cache]"
        exit 1
        ;;
esac

echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "To run: ./run.sh [workspace-name] [task]"
