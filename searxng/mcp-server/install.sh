#!/bin/bash
# Install SearXNG MCP Server for Claude Code

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing SearXNG MCP Server..."

cd "$SCRIPT_DIR"

# Install dependencies
npm install

echo ""
echo "Installation complete!"
echo ""
echo "To configure Claude Code to use this MCP server, add to your settings:"
echo ""
echo "For project-level (~/.claude/settings.json or .claude/settings.json):"
echo ""
cat << 'EOF'
{
  "mcpServers": {
    "searxng": {
      "command": "node",
      "args": ["<path-to>/searxng/mcp-server/index.js"],
      "env": {
        "SEARXNG_URL": "http://localhost:8888"
      }
    }
  }
}
EOF
echo ""
echo "Replace <path-to> with the actual path to this directory."
