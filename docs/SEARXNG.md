# SearXNG Web Search Integration

Self-hosted meta-search engine providing reliable, free, mass-scale web search for Claude Code.

## Why SearXNG?

| Previous Solution | Problem |
|-------------------|---------|
| Whoogle | Google blocks after some use |
| Playwright browser | Slow (5-10s per search) |
| DuckDuckGo API | Rate limited |
| Tavily | Paid/limited free tier |

**SearXNG solves this by:**
- Aggregating results from multiple engines (Bing, DDG, Startpage, etc.)
- If one engine blocks you, others still return results
- Self-hosted = no API limits
- Fast (~1-2 seconds per query)
- JSON API for programmatic access

## Quick Start

```bash
# Start SearXNG
make searxng-start

# Test it
make searxng-test

# Check status
make searxng-status

# Stop when done
make searxng-stop
```

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make searxng-start` | Start SearXNG service (port 8888) |
| `make searxng-stop` | Stop SearXNG service |
| `make searxng-status` | Check status and engine health |
| `make searxng-test` | Test search with sample query |
| `make searxng-logs` | Follow SearXNG logs |

## Direct API Usage

### JSON API

```bash
# Basic search
curl "http://localhost:8888/search?q=your+query&format=json"

# With category
curl "http://localhost:8888/search?q=your+query&format=json&categories=it"
```

### Response Format

```json
{
  "query": "docker compose",
  "number_of_results": 21,
  "results": [
    {
      "url": "https://docs.docker.com/compose/",
      "title": "Docker Compose",
      "content": "Snippet text...",
      "engines": ["bing", "duckduckgo", "startpage"],
      "score": 23.04
    }
  ],
  "unresponsive_engines": [
    ["engine_name", "error reason"]
  ]
}
```

## Claude Code Integration

### For Docker Agent

The agent container automatically configures the SearXNG MCP server. The inner Claude can use:

```
Use the web_search tool to search for "your query"
```

**Two modes available:**

#### Mode 1: Standalone SearXNG (Recommended)

Run SearXNG separately, agent connects via host network:

```bash
# Start SearXNG once (keep running)
make searxng-start

# Run agent (connects via host.docker.internal:8888)
make worker W=myproject TASK="task"
```

Best for: Running multiple agents, persistent search service.

#### Mode 2: Integrated SearXNG

Start SearXNG with the agent in the same Docker network:

```bash
# Run agent with SearXNG included
make worker W=myproject TASK="task" SEARXNG=1
```

Best for: Single-run tasks, simpler setup, Linux hosts.

**Note:** Standalone mode uses `host.docker.internal` which works on Docker Desktop (Mac/Windows) and Linux with Docker 20.10+.

### For Host Claude Code (Manual Setup)

To use SearXNG from Claude Code on your host machine:

#### Installation

```bash
cd searxng/mcp-server
npm install
```

#### Configure Claude Code

Add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "searxng": {
      "command": "node",
      "args": ["/path/to/local-claude-docker/searxng/mcp-server/index.js"],
      "env": {
        "SEARXNG_URL": "http://localhost:8888"
      }
    }
  }
}
```

#### Usage

Once configured, Claude Code can use:

```
Use the web_search tool to find information about "kubernetes deployment best practices"
```

The tool returns formatted results with titles, URLs, snippets, and source engines.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Claude Code                                                │
│                                                             │
│  Uses MCP tool: web_search                                  │
└─────────────────┬───────────────────────────────────────────┘
                  │ stdio (MCP protocol)
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  SearXNG MCP Server (Node.js)                               │
│                                                             │
│  - Translates MCP calls to HTTP                             │
│  - Formats results for Claude                               │
└─────────────────┬───────────────────────────────────────────┘
                  │ HTTP (JSON API)
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  SearXNG Container (port 8888)                              │
│                                                             │
│  ┌─────────┐ ┌─────────┐ ┌───────────┐ ┌─────────┐         │
│  │  Bing   │ │  DDG    │ │ Startpage │ │  Wiby   │  ...    │
│  └────┬────┘ └────┬────┘ └─────┬─────┘ └────┬────┘         │
│       └───────────┴────────────┴────────────┘               │
│                         │                                   │
│              Aggregate & Deduplicate                        │
│                         │                                   │
│              Return ranked results                          │
└─────────────────────────────────────────────────────────────┘
```

## Configured Engines

### Primary (most reliable)
- **Bing** - Microsoft search
- **Startpage** - Google results via privacy proxy
- **DuckDuckGo** - Privacy-focused search
- **Mojeek** - Independent index

### Secondary (fallbacks)
- **Yep** - Ahrefs-powered search
- **Yahoo** - Yahoo search
- **Wiby** - Indie web search
- **Curlie** - Directory-based

### Specialized
- **Wikipedia** - Encyclopedia
- **StackOverflow** - Programming Q&A
- **GitHub** - Code search
- **MDN** - Web documentation
- **npm/PyPI/crates.io** - Package registries
- **Docker Hub** - Container images
- **Arch Wiki** - Linux documentation

### Disabled (unreliable)
- Google (direct) - Aggressive blocking
- Brave - Quick rate limits
- Qwant - Frequent parsing errors

## Customization

### Edit Engine Configuration

```bash
# Edit settings
vim searxng/settings.yml

# Restart to apply
make searxng-stop && make searxng-start
```

### Add More Engines

See full list: https://docs.searxng.org/user/configured_engines.html

Example - enable Brave with timeout:
```yaml
engines:
  - name: brave
    disabled: false
    timeout: 6.0
```

### Change Port

Edit `searxng/docker-compose.yml`:
```yaml
ports:
  - "9999:8080"  # Change 8888 to your preferred port
```

Update MCP server env:
```json
"env": {
  "SEARXNG_URL": "http://localhost:9999"
}
```

## Troubleshooting

### No results returned

```bash
# Check engine status
make searxng-status

# View logs for errors
make searxng-logs
```

Common causes:
- All engines temporarily blocked (wait and retry)
- Network issues (check Docker networking)

### Specific engine failing

Check `unresponsive_engines` in the JSON response. Common issues:
- "CAPTCHA" - Engine detecting bot traffic
- "access denied" - IP blocked
- "parsing error" - Engine changed their HTML

Solution: The other engines should still work. If critical, disable the failing engine in settings.yml.

### MCP server not connecting

1. Verify SearXNG is running: `make searxng-status`
2. Check URL in MCP config matches port
3. Test direct API: `curl http://localhost:8888/search?q=test&format=json`

## Performance

Typical results:
- **Response time:** 0.7 - 2.0 seconds
- **Results per query:** 15-30 (deduplicated)
- **Engines responding:** 3-5 out of configured
- **Rate limits:** None (self-hosted)

## Files

```
searxng/
├── docker-compose.yml    # Service definition
├── settings.yml          # Engine configuration
├── limiter.toml          # Rate limiting (disabled)
└── mcp-server/
    ├── package.json
    ├── index.js          # MCP server implementation
    └── install.sh        # Setup script
```
