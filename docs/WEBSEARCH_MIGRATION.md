# WebSearch Migration: Whoogle to Playwright MCP

## Issue (2026-03-21)

**Problem:** The Whoogle-based websearch skill stopped working because Google is blocking search requests from the host IP address.

**Symptoms:**
- Whoogle returns empty results or errors
- Google detects automated/API-like requests and blocks them
- This affects the `/websearch` skill used by Claude for research tasks

## Root Cause

Whoogle works by proxying Google searches, but Google's anti-bot systems detect the pattern of requests coming from a single IP (especially via API-like calls) and block them.

## Solution

Replace the Whoogle-based skill with a **Playwright MCP server** that:

1. **Uses a real browser** - Playwright controls a headless Chromium instance
2. **Searches Google directly** - Appears as normal browser traffic
3. **Bypasses blocking** - Real browser with JavaScript execution, cookies, etc.
4. **MCP integration** - Implements Model Context Protocol for Claude Code integration

## Trade-offs

| Aspect | Whoogle (old) | Playwright MCP (new) |
|--------|---------------|----------------------|
| Speed | Fast (~1s) | Slower (~5-10s) |
| Reliability | Blocked by Google | Works reliably |
| Resource usage | Low | Higher (browser process) |
| Results quality | Same as Google | Same as Google |
| Setup complexity | External service | Built into container |

## Implementation

- **Backup:** `skills-backup/websearch-whoogle-backup/`
- **New approach:** Uses `@playwright/mcp` (official Microsoft package)
- **Integration:** Claude Code connects via MCP stdio protocol

## Files Changed

- `Dockerfile` - Added `npm install -g @playwright/mcp`
- `scripts/init-workspace.sh` - Added MCP server config to project settings
- `skills-backup/websearch/SKILL.md` - Updated to document MCP tools usage
- `skills-backup/websearch/local_websearch.sh` - Removed (no longer needed)
- `skills-backup/websearch-whoogle-backup/` - Old Whoogle implementation preserved
- `README.md` - Updated websearch documentation
- `CLAUDE.md` - Updated skill reference

## How Inner Claude Uses It

The `@playwright/mcp` server provides these MCP tools to Claude inside the container:

1. `mcp__playwright__browser_navigate` - Go to URL
2. `mcp__playwright__browser_type` - Type text (with submit option)
3. `mcp__playwright__browser_snapshot` - Get page content
4. `mcp__playwright__browser_click` - Click elements
5. `mcp__playwright__browser_screenshot` - Take screenshots

To search:
1. Navigate to google.com
2. Type query in search box with submit=true
3. Get snapshot of results

## Rebuild Required

After these changes, rebuild the container:
```bash
docker compose build --no-cache
```
