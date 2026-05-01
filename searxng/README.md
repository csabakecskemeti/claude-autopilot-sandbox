# SearXNG Web Search Service

Self-hosted meta-search engine for Claude Code.

## Quick Start

```bash
# From project root:
make searxng-start   # Start service
make searxng-test    # Test it
make searxng-status  # Check health
```

## API

```bash
curl "http://localhost:8888/search?q=your+query&format=json"
```

## Claude Code Integration

Configure MCP server in `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "searxng": {
      "command": "node",
      "args": ["/full/path/to/searxng/mcp-server/index.js"],
      "env": {
        "SEARXNG_URL": "http://localhost:8888"
      }
    }
  }
}
```

## Files

- `docker-compose.yml` - Service definition
- `settings.yml` - Engine configuration
- `mcp-server/` - MCP server for Claude Code

## Full Documentation

See `docs/SEARXNG.md` for complete documentation.
