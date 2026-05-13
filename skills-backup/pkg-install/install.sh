#!/usr/bin/env bash
# Runtime package installer for Docker container

set -e

OPERATION="$1"
shift || true

if [[ -z "$OPERATION" ]]; then
    echo "Usage: $0 <type> <packages...>"
    echo "       $0 check <package>"
    echo "       $0 list <type>"
    echo ""
    echo "Types: apt, pip, npm"
    echo ""
    echo "Examples:"
    echo "  $0 apt postgresql-client"
    echo "  $0 pip pandas numpy"
    echo "  $0 npm axios"
    echo "  $0 check pip:pandas"
    echo "  $0 list pip"
    exit 1
fi

case "$OPERATION" in
    apt)
        echo "Installing apt packages: $@"
        sudo apt-get update -qq
        sudo apt-get install -y -qq "$@"
        echo "Done."
        ;;
    pip)
        echo "Installing pip packages: $@"
        pip3 install --quiet --user "$@"
        echo "Done."
        ;;
    npm)
        echo "Installing npm packages: $@"
        npm install -g "$@" 2>/dev/null
        echo "Done."
        ;;
    check)
        PACKAGE="$1"
        if [[ "$PACKAGE" == pip:* ]]; then
            PKG_NAME="${PACKAGE#pip:}"
            if pip3 show "$PKG_NAME" &>/dev/null; then
                echo "✓ $PKG_NAME is installed (pip)"
                pip3 show "$PKG_NAME" | grep -E "^(Name|Version):"
            else
                echo "✗ $PKG_NAME is NOT installed (pip)"
                exit 1
            fi
        elif [[ "$PACKAGE" == npm:* ]]; then
            PKG_NAME="${PACKAGE#npm:}"
            if npm list -g "$PKG_NAME" &>/dev/null; then
                echo "✓ $PKG_NAME is installed (npm)"
            else
                echo "✗ $PKG_NAME is NOT installed (npm)"
                exit 1
            fi
        else
            if command -v "$PACKAGE" &>/dev/null; then
                echo "✓ $PACKAGE is available"
                command -v "$PACKAGE"
            elif dpkg -l "$PACKAGE" &>/dev/null; then
                echo "✓ $PACKAGE is installed (apt)"
            else
                echo "✗ $PACKAGE is NOT installed"
                exit 1
            fi
        fi
        ;;
    list)
        TYPE="$1"
        case "$TYPE" in
            apt)
                dpkg --get-selections | grep -v deinstall | head -50
                echo "... (showing first 50)"
                ;;
            pip)
                pip3 list --user 2>/dev/null || pip3 list
                ;;
            npm)
                npm list -g --depth=0 2>/dev/null
                ;;
            *)
                echo "Unknown type: $TYPE"
                echo "Use: apt, pip, npm"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Unknown operation: $OPERATION"
        echo "Use: apt, pip, npm, check, list"
        exit 1
        ;;
esac
