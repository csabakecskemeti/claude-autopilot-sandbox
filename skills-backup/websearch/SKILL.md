---
name: websearch
description: Search the web using Playwright browser automation (MCP). Use for web research when you need to search Google or browse web pages. Slower than API-based search but bypasses blocking.
allowed-tools: mcp__playwright__*
---

# Web Search (Playwright MCP)

Search the web using real browser automation via the Playwright MCP server.

**Why Playwright?** Google blocks API-like requests from Whoogle/proxies. Using a real browser bypasses this blocking.

## Available MCP Tools

The `playwright` MCP server provides these tools:

| Tool | Description |
|------|-------------|
| `browser_navigate` | Navigate to a URL |
| `browser_snapshot` | Get page accessibility snapshot (structured content) |
| `browser_click` | Click an element |
| `browser_type` | Type text into an element |
| `browser_screenshot` | Take a screenshot |

## How to Search Google

### Step 1: Navigate to Google
```
Use mcp__playwright__browser_navigate with url: "https://www.google.com"
```

### Step 2: Type Search Query
```
Use mcp__playwright__browser_type with:
  - element: "Search" (or the search box identifier from snapshot)
  - text: "your search query"
  - submit: true
```

### Step 3: Get Results
```
Use mcp__playwright__browser_snapshot to get the page content
```

## Example Workflow

1. Navigate to Google
2. Accept cookies if prompted (click "Accept all")
3. Type search query and submit
4. Get snapshot of results page
5. Parse results from the structured accessibility data

## Notes

- **Slower than Whoogle** - Real browser startup + page loads (~5-10s vs ~1s)
- **More reliable** - Bypasses Google's API blocking
- **Full browser** - Can handle JavaScript, cookies, consent dialogs
- **Headless** - Runs without visible window (uses Xvfb)

## Fallback

If MCP tools are unavailable, you can use the `/fetch` skill to retrieve specific URLs directly.
